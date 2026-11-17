-- FrogLib Lines: lines drawn over the world map and the minimap, for routes (FrogRoute's). World map:
-- on the map's canvas, so they pan and zoom with it (their width staying the same on screen), worked
-- out again when the map changes (a zoom only changes their width). Minimap: around you, clipped to
-- its round (or square) edge, turned with it when it turns, a few times a second while anything moves.

local Lines = FrogLib:Module("Lines", 2) -- 2: the minimap's scale from FrogLib's MinimapView
if not Lines then return end

local sqrt = math.sqrt
local NONE = {}

-- One side of the square: [enter, leave] narrowed to the part inside it, or nil when none is.
local function Side(toward, room, enter, leave)
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
    return enter, leave
end

-- The part of the segment (x1, y1)-(x2, y2) inside the circle of radius `radius` (or the square), or nil.
local function Clip(x1, y1, x2, y2, radius, square)
    local spanX, spanY = x2 - x1, y2 - y1
    local enter, leave = 0, 1
    if square then
        enter, leave = Side(-spanX, x1 + radius, enter, leave)
        if enter then enter, leave = Side(spanX, radius - x1, enter, leave) end
        if enter then enter, leave = Side(-spanY, y1 + radius, enter, leave) end
        if enter then enter, leave = Side(spanY, radius - y1, enter, leave) end
        if not enter then return end
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
            local root = sqrt(discriminant)
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
local loader -- made with the first layer: the world map can load after the addons that use this
local spot -- one place on the map, reused for every point (the game only reads it)

local function Canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

function Methods:DrawMap()
    local canvas = Canvas()
    if not (canvas and self.mapShown and WorldMapFrame:IsShown()) then
        self.mapFor = nil
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
    local mapID = WorldMapFrame:GetMapID()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    -- A zoom (every frame of one) only changes how thick they're drawn: where they lie stays put.
    if mapID and mapID == self.mapFor and width == self.mapWidth and height == self.mapHeight then
        for i = 1, pool.used do
            local drawn = pool.lines[i]
            drawn:SetThickness(drawn.width / scale)
        end
        return
    end
    self.mapFor, self.mapWidth, self.mapHeight = mapID, width, height
    pool.used = 0
    if mapID and width > 0 and C_Map.GetMapPosFromWorldPos then
        spot = spot or CreateVector2D(0, 0)
        for _, line in ipairs(self.lines or NONE) do
            local points = line.points
            local lastU, lastV
            for i = 1, #points - 1, 2 do
                spot:SetXY(points[i], points[i + 1])
                local _, position = C_Map.GetMapPosFromWorldPos(line.inst, spot, mapID)
                local u, v
                if position then u, v = position:GetXY() end
                if u and lastU then
                    local drawn = Take(pool)
                    drawn.width = line.width or 4
                    drawn:SetThickness(drawn.width / scale)
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
    if loader then loader:UnregisterAllEvents() end
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
        holder:Hide()
        self.mmHolder = holder
        self.mmPool = Pool(holder)
        -- 20 times a second while it shows, on a ticker, so nothing runs on the frames between.
        local ticker
        local function Tick() self:DrawMinimapNow() end
        holder:SetScript("OnShow", function() ticker = ticker or C_Timer.NewTicker(0.05, Tick) end)
        holder:SetScript("OnHide", function()
            if ticker then ticker:Cancel() end
            ticker = nil
        end)
    end
    self.mmHolder:SetShown(self.minimapShown and self.lines ~= nil and #self.lines > 0)
end

-- Drawn again only when what it's drawn from has changed: standing still, there's nothing to do.
function Methods:DrawMinimapNow()
    local View = FrogLib.MinimapView
    local north, west, instance = View.Player()
    local scale, radius, rotating, facing, square
    if north then scale, radius, rotating, facing, square = View.Read() end
    local seen = self.mmSeen
    if seen and seen[1] == north and seen[2] == west and seen[3] == instance and seen[4] == scale
        and seen[5] == radius and seen[6] == rotating and seen[7] == facing and seen[8] == square then
        return
    end
    seen = seen or {}
    self.mmSeen = seen
    seen[1], seen[2], seen[3], seen[4], seen[5], seen[6], seen[7], seen[8] =
        north, west, instance, scale, radius, rotating, facing, square
    local pool = self.mmPool
    pool.used = 0
    if north then
        local edge = radius - 2
        local reach = edge / scale * 1.5 -- yards: segments further off than this are skipped
        for _, line in ipairs(self.lines or NONE) do
            if line.inst == instance and line.minimap ~= false then
                local points = line.points
                for i = 1, #points - 3, 2 do
                    local north1, west1 = points[i] - north, points[i + 1] - west
                    local north2, west2 = points[i + 2] - north, points[i + 3] - west
                    if not ((north1 > reach and north2 > reach) or (north1 < -reach and north2 < -reach)
                        or (west1 > reach and west2 > reach) or (west1 < -reach and west2 < -reach)) then
                        local x1, y1 = View.Offset(north1, west1, scale, rotating, facing)
                        local x2, y2 = View.Offset(north2, west2, scale, rotating, facing)
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
-- (pixels), minimap = false (map only) } }, in UnitPosition's order; nil or {} clears them. Set
-- again after any change: only then are they worked out afresh.
function Methods:Set(lines)
    self.lines = lines
    self.mapFor, self.mmSeen = nil, nil
    HookMap()
    self:DrawMap()
    self:DrawMinimap()
end

function Methods:SetShown(on)
    self.mapShown = on and self.opts.map ~= false
    self.minimapShown = on and self.opts.minimap ~= false
    self.mapFor, self.mmSeen = nil, nil
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
    HookMap()
    if not (mapHooked or loader) then
        loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", HookMap)
    end
    return layer
end
