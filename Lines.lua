-- FrogLib Lines: lines drawn over the world map and the minimap, for routes (FrogRoute's). World map:
-- on the map's canvas, so they pan and zoom with it (their width staying the same on screen), worked
-- out again when the map or its zoom changes. Minimap: around you, clipped to its round (or square)
-- edge, turned with it when it turns, a few times a second.

local Lines = FrogLib:Module("Lines", 1)
if not Lines then return end

local issecret = FrogLib.issecret

-- The minimap's width in yards at each zoom level (0-5), outdoors and indoors (as HereBeDragons
-- has them).
local YARDS = {
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}

-- Pixels per yard, radius (pixels), whether it turns, your facing, whether it's square.
local function MinimapScale()
    local zoom = Minimap:GetZoom() or 0
    local yards = (IsIndoors and IsIndoors() and YARDS.indoor or YARDS.outdoor)[zoom + 1] or 400
    local width = Minimap:GetWidth()
    local rotating = GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotating then
        local playerFacing = GetPlayerFacing()
        facing = (playerFacing and not issecret(playerFacing)) and playerFacing or 0
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    return width / yards, width / 2, rotating, facing, square
end

-- A place `north` and `west` of you, from the minimap's centre: west is left, north is up, turned
-- with the minimap when it turns.
local function MinimapPoint(north, west, scale, rotating, facing)
    local x, y = -west * scale, north * scale
    if rotating then
        local cos, sin = math.cos(facing), math.sin(facing)
        x, y = x * cos + y * sin, -x * sin + y * cos
    end
    return x, y
end

-- The part of the segment (x1, y1)-(x2, y2) inside the circle of radius `radius` (or the square), or nil.
local function Clip(x1, y1, x2, y2, radius, square)
    local spanX, spanY = x2 - x1, y2 - y1
    local enter, leave = 0, 1
    if square then
        for _, side in ipairs({ { -spanX, x1 + radius }, { spanX, radius - x1 }, { -spanY, y1 + radius }, { spanY, radius - y1 } }) do
            local toward, room = side[1], side[2]
            if toward == 0 then
                if room < 0 then return end
            else
                local crossing = room / toward
                if toward < 0 then
                    if crossing > leave then return end
                    if crossing > enter then enter = crossing end
                else
                    if crossing < enter then return end
                    if crossing < leave then leave = crossing end
                end
            end
        end
    else
        -- Where the line meets the circle: the quadratic's two roots.
        local squared = spanX * spanX + spanY * spanY
        local linear = 2 * (x1 * spanX + y1 * spanY)
        local constant = x1 * x1 + y1 * y1 - radius * radius
        if squared == 0 then
            if constant > 0 then return end
        else
            local discriminant = linear * linear - 4 * squared * constant
            if discriminant < 0 then return end
            local root = math.sqrt(discriminant)
            local first, second = (-linear - root) / (2 * squared), (-linear + root) / (2 * squared)
            if first > enter then enter = first end
            if second < leave then leave = second end
            if enter >= leave then return end
        end
    end
    return x1 + spanX * enter, y1 + spanY * enter, x1 + spanX * leave, y1 + spanY * leave
end

local layers = {}
local Methods = {}

local function Pool(parent)
    return { parent = parent, used = 0, lines = {} }
end

local function Take(pool, level)
    pool.used = pool.used + 1
    local line = pool.lines[pool.used]
    if not line then
        line = pool.parent:CreateLine(nil, "OVERLAY", nil, level or 0)
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        pool.lines[pool.used] = line
    end
    line:Show()
    return line
end

-- Hides the lines past the ones used this time.
local function Finish(pool)
    for i = pool.used + 1, #pool.lines do pool.lines[i]:Hide() end
end

-- World map ------------------------------------------------------------------------------------

local mapHooked = false

local function Canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

function Methods:DrawMap()
    local canvas = Canvas()
    if not (canvas and self.mapShown and WorldMapFrame:IsShown()) then
        if self.mapPool then
            self.mapPool.used = 0
            Finish(self.mapPool)
        end
        return
    end
    if not self.mapHolder then
        self.mapHolder = CreateFrame("Frame", nil, canvas)
        self.mapHolder:SetAllPoints()
        self.mapPool = Pool(self.mapHolder)
    end
    self.mapHolder:SetFrameLevel(canvas:GetFrameLevel() + 2000)
    local pool = self.mapPool
    pool.used = 0
    local mapID = WorldMapFrame:GetMapID()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    if mapID and width > 0 and C_Map.GetMapPosFromWorldPos then
        for _, line in ipairs(self.lines or {}) do
            local points = line.points
            local lastU, lastV
            for i = 1, #points - 1, 2 do
                local _, position = C_Map.GetMapPosFromWorldPos(line.inst, CreateVector2D(points[i], points[i + 1]), mapID)
                local u, v
                if position then u, v = position:GetXY() end
                if u and lastU then
                    local drawn = Take(pool)
                    drawn:SetThickness((line.width or 4) / scale)
                    drawn:SetVertexColor(line.r or 1, line.g or 0.2, line.b or 0.2, line.a or 0.9)
                    drawn:SetStartPoint("TOPLEFT", canvas, lastU * width, -lastV * height)
                    drawn:SetEndPoint("TOPLEFT", canvas, u * width, -v * height)
                end
                lastU, lastV = u, v
            end
        end
    end
    Finish(pool)
end

local function HookMap()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    local function Redraw()
        for _, layer in pairs(layers) do layer:DrawMap() end
    end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Redraw)
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Redraw) end
    WorldMapFrame:HookScript("OnShow", Redraw)
    if WorldMapFrame.ScrollContainer then WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", Redraw) end
end

-- Minimap --------------------------------------------------------------------------------------

function Methods:DrawMinimap()
    if not Minimap then return end
    if not self.mmHolder then
        local holder = CreateFrame("Frame", nil, Minimap)
        holder:SetAllPoints()
        holder:SetFrameLevel(Minimap:GetFrameLevel() + 4)
        self.mmHolder = holder
        self.mmPool = Pool(holder)
        local elapsed = 0
        holder:SetScript("OnUpdate", function(_, sinceLast)
            elapsed = elapsed + sinceLast
            if elapsed < 0.05 then return end
            elapsed = 0
            self:DrawMinimapNow()
        end)
    end
    self.mmHolder:SetShown(self.minimapShown and self.lines ~= nil and #self.lines > 0)
end

function Methods:DrawMinimapNow()
    local pool = self.mmPool
    pool.used = 0
    local north, west, _, instance = UnitPosition("player")
    if north and not issecret(north) then
        local scale, radius, rotating, facing, square = MinimapScale()
        local edge = radius - 2
        local reach = edge / scale * 1.5 -- yards: segments further off than this are skipped
        for _, line in ipairs(self.lines or {}) do
            if line.inst == instance and line.minimap ~= false then
                local points = line.points
                for i = 1, #points - 3, 2 do
                    local north1, west1 = points[i] - north, points[i + 1] - west
                    local north2, west2 = points[i + 2] - north, points[i + 3] - west
                    if not ((north1 > reach and north2 > reach) or (north1 < -reach and north2 < -reach)
                        or (west1 > reach and west2 > reach) or (west1 < -reach and west2 < -reach)) then
                        local x1, y1 = MinimapPoint(north1, west1, scale, rotating, facing)
                        local x2, y2 = MinimapPoint(north2, west2, scale, rotating, facing)
                        local startX, startY, endX, endY = Clip(x1, y1, x2, y2, edge, square)
                        if startX then
                            local drawn = Take(pool)
                            drawn:SetThickness(line.mmWidth or 3)
                            drawn:SetVertexColor(line.r or 1, line.g or 0.2, line.b or 0.2, line.a or 0.9)
                            drawn:SetStartPoint("CENTER", Minimap, startX, startY)
                            drawn:SetEndPoint("CENTER", Minimap, endX, endY)
                        end
                    end
                end
            end
        end
    end
    Finish(pool)
end

-- Layers ---------------------------------------------------------------------------------------

-- lines = { { inst = continent, points = { north1, west1, north2, west2, ... }, r, g, b, a, width
-- (pixels), minimap = false (map only) } }, in UnitPosition's order; nil or {} clears them.
function Methods:Set(lines)
    self.lines = lines
    HookMap()
    self:DrawMap()
    self:DrawMinimap()
end

function Methods:SetShown(on)
    self.mapShown = on and self.opts.map ~= false
    self.minimapShown = on and self.opts.minimap ~= false
    self:DrawMap()
    self:DrawMinimap()
end

-- opts = { map = true, minimap = true }: where it draws.
function Lines.New(key, opts)
    if layers[key] then return layers[key] end
    opts = opts or {}
    local layer = setmetatable({ key = key, opts = opts, mapShown = opts.map ~= false,
        minimapShown = opts.minimap ~= false }, { __index = Methods })
    layers[key] = layer
    return layer
end

-- The world map can load after the addons that use this.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if WorldMapFrame and next(layers) then HookMap() end
end)
