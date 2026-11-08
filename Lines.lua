-- FrogLib Lines: lines drawn over the world map and the minimap, for routes (FrogRoute's, and
-- FrogGuide's through it).
--   local layer = FrogLib.Lines.New(key, { map = true, minimap = true })
--   layer:Set(lines)    lines = { { inst = continent, points = { north1, west1, north2, west2, ... },
--                                   r =, g =, b =, a =, width = (pixels), minimap = false (map only) } }
--                       (positions in UnitPosition's order); nil or {} clears them
--   layer:SetShown(on)
-- World map: on the map's canvas, so they pan and zoom with it (their width stays the same on
-- screen); worked out again when the map or its zoom changes. Minimap: around you, clipped to its
-- round (or square) edge, turned with it when it turns, a few times a second.
-- Also the minimap's sums, for pins (FrogGuide's):
--   FrogLib.Lines.MinimapScale() -> pixels per yard, radius (pixels), rotating, facing, square
--   FrogLib.Lines.MinimapPoint(dn, dw, scale, rotating, facing) -> x, y from the minimap's centre

local Lines = FrogLib:Module("Lines", 1)
if not Lines then return end

local issecret = FrogLib.issecret

-- The minimap's width in yards at each zoom level (0-5), outdoors and indoors (as HereBeDragons
-- has them).
Lines.YARDS = {
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}

function Lines.MinimapScale()
    local zoom = Minimap:GetZoom() or 0
    local yards = (IsIndoors and IsIndoors() and Lines.YARDS.indoor or Lines.YARDS.outdoor)[zoom + 1] or 400
    local w = Minimap:GetWidth()
    local rotating = GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotating then
        local f = GetPlayerFacing()
        facing = (f and not issecret(f)) and f or 0
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    return w / yards, w / 2, rotating, facing, square
end

-- Screen: west is left, north is up; turned with the minimap when it turns.
function Lines.MinimapPoint(dn, dw, scale, rotating, facing)
    local sx, sy = -dw * scale, dn * scale
    if rotating then
        local c, s = math.cos(facing), math.sin(facing)
        sx, sy = sx * c + sy * s, -sx * s + sy * c
    end
    return sx, sy
end

-- The part of the segment (x1, y1)-(x2, y2) inside the circle of radius r (or the square), or nil.
local function Clip(x1, y1, x2, y2, r, square)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    if square then
        for _, e in ipairs({ { -dx, x1 + r }, { dx, r - x1 }, { -dy, y1 + r }, { dy, r - y1 } }) do
            local p, q = e[1], e[2]
            if p == 0 then
                if q < 0 then return end
            else
                local t = q / p
                if p < 0 then
                    if t > t1 then return end
                    if t > t0 then t0 = t end
                else
                    if t < t0 then return end
                    if t < t1 then t1 = t end
                end
            end
        end
    else
        local a = dx * dx + dy * dy
        local b = 2 * (x1 * dx + y1 * dy)
        local c = x1 * x1 + y1 * y1 - r * r
        if a == 0 then
            if c > 0 then return end
        else
            local disc = b * b - 4 * a * c
            if disc < 0 then return end
            local s = math.sqrt(disc)
            local ta, tb = (-b - s) / (2 * a), (-b + s) / (2 * a)
            if ta > t0 then t0 = ta end
            if tb < t1 then t1 = tb end
            if t0 >= t1 then return end
        end
    end
    return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

local layers = {}
local Methods = {}

local function Pool(parent)
    return { parent = parent, used = 0, lines = {} }
end

local function Take(pool, level)
    pool.used = pool.used + 1
    local l = pool.lines[pool.used]
    if not l then
        l = pool.parent:CreateLine(nil, "OVERLAY", nil, level or 0)
        l:SetTexture("Interface\\Buttons\\WHITE8X8")
        pool.lines[pool.used] = l
    end
    l:Show()
    return l
end

local function Release(pool)
    for i = pool.used + 1, #pool.lines do pool.lines[i]:Hide() end
    pool.used = 0
end

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
        if self.mapPool then Release(self.mapPool); Finish(self.mapPool) end
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
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local scale = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    if mapID and W > 0 and C_Map.GetMapPosFromWorldPos then
        for _, line in ipairs(self.lines or {}) do
            local pts = line.points
            local prevU, prevV
            for i = 1, #pts - 1, 2 do
                local _, pos = C_Map.GetMapPosFromWorldPos(line.inst, CreateVector2D(pts[i], pts[i + 1]), mapID)
                local u, v
                if pos then u, v = pos:GetXY() end
                if u and prevU then
                    local l = Take(pool)
                    l:SetThickness((line.width or 4) / scale)
                    l:SetVertexColor(line.r or 1, line.g or 0.2, line.b or 0.2, line.a or 0.9)
                    l:SetStartPoint("TOPLEFT", canvas, prevU * W, -prevV * H)
                    l:SetEndPoint("TOPLEFT", canvas, u * W, -v * H)
                end
                prevU, prevV = u, v
            end
        end
    end
    Finish(pool)
end

local function HookMap()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    local function redraw()
        for _, layer in pairs(layers) do layer:DrawMap() end
    end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", redraw)
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", redraw) end
    WorldMapFrame:HookScript("OnShow", redraw)
    if WorldMapFrame.ScrollContainer then WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", redraw) end
end

-- Minimap --------------------------------------------------------------------------------------

function Methods:DrawMinimap()
    if not Minimap then return end
    if not self.mmHolder then
        local h = CreateFrame("Frame", nil, Minimap)
        h:SetAllPoints()
        h:SetFrameLevel(Minimap:GetFrameLevel() + 4)
        self.mmHolder = h
        self.mmPool = Pool(h)
        local elapsed = 0
        h:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
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
    local north, west, _, inst = UnitPosition("player")
    if north and not issecret(north) then
        local scale, radius, rotating, facing, square = Lines.MinimapScale()
        local r = radius - 2
        local reach = r / scale * 1.5   -- yards: segments further off than this are skipped
        for _, line in ipairs(self.lines or {}) do
            if line.inst == inst and line.minimap ~= false then
                local pts = line.points
                for i = 1, #pts - 3, 2 do
                    local n1, w1, n2, w2 = pts[i] - north, pts[i + 1] - west, pts[i + 2] - north, pts[i + 3] - west
                    if not ((n1 > reach and n2 > reach) or (n1 < -reach and n2 < -reach)
                        or (w1 > reach and w2 > reach) or (w1 < -reach and w2 < -reach)) then
                        local x1, y1 = Lines.MinimapPoint(n1, w1, scale, rotating, facing)
                        local x2, y2 = Lines.MinimapPoint(n2, w2, scale, rotating, facing)
                        local a, b, c, d = Clip(x1, y1, x2, y2, r, square)
                        if a then
                            local l = Take(pool)
                            l:SetThickness(line.mmWidth or 3)
                            l:SetVertexColor(line.r or 1, line.g or 0.2, line.b or 0.2, line.a or 0.9)
                            l:SetStartPoint("CENTER", Minimap, a, b)
                            l:SetEndPoint("CENTER", Minimap, c, d)
                        end
                    end
                end
            end
        end
    end
    Finish(pool)
end

-- Layers ---------------------------------------------------------------------------------------

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

function Lines.New(key, opts)
    if layers[key] then return layers[key] end
    opts = opts or {}
    local layer = setmetatable({ key = key, opts = opts, mapShown = opts.map ~= false,
        minimapShown = opts.minimap ~= false }, { __index = Methods })
    layers[key] = layer
    return layer
end

-- The world map can load after the addons that use this.
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if WorldMapFrame and next(layers) then HookMap() end
end)
