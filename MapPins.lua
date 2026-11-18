-- FrogLib MapPins: an addon's own pins on the world map, drawn the way EllesmereUI draws its map markers
-- (ForeverEssentials MapTravel): plain frames of ours on a layer frame of ours over the map's canvas, so they pan and
-- zoom with it, placed when a data provider of ours hears that the map has shown, changed map, zoomed or resized (the
-- map calls each provider sealed off from its own code). Never the map's own pins or pin pools: acquiring or
-- releasing one runs the map's code from ours, which marks its scroll container dirty under our taint, and Blizzard's
-- quest pins read that just before a call that's protected in combat. No hooks on the map, and nothing of Blizzard's
-- is written: the map's ID, the canvas's size and scale and its pin levels are only read. The map is never opened,
-- moved or super-tracked from here either (each taints it): Link makes a map pin link for chat, whose click is the
-- player's own, so the game's code opens the map.
--
--   local set = FrogLib.MapPins.New({
--       level = "PIN_FRAME_LEVEL_AREA_POI",    -- the map's pin level the set's layer sits at
--       kinds = {                              -- each kind of pin, its frames pooled apart
--           dot = {
--               Create = function(parent) return frame end, -- made on the layer; mouse scripts are its own
--               Setup = function(frame, data) end,          -- given each time it's placed (size, look)
--               screen = true,     -- the same size on screen at every zoom (else it zooms with the map)
--               pass = "RightButton", -- a button its clicks pass on to the map (set out of combat: protected)
--               raise = 1,         -- 1 (the default): at the level named; 0: one below it
--           },
--       },
--       Draw = function(set, mapID) set:Add("dot", x, y, data) end, -- the pins for that map (x, y 0-1)
--       OnShow = fn, OnHide = fn, OnMapChanged = fn(mapID),          -- optional: the map's own news, sealed off
--   })
--   set:Enable(true)   -- the provider on the map (made the first time; waits for the map's addon if need be)
--   set:Refresh()      -- drawn again now, if the map is open
--   set:Enable(false)  -- off the map, with OnHide if it was open (not from inside one of its callbacks)
--
-- A change of map comes as several of the map's calls in a row (its size, the map, its overlays refreshing all
-- providers): the pins are only drawn again when the map, the canvas's size or the addon's data (Refresh) changed,
-- and always the first time after the map opens. Nothing is drawn, and no map news passed on, while it's hidden.

local MapPins = FrogLib:Module("MapPins", 1)
if not MapPins then return end

local Set = {}
Set.__index = Set

local unpassed = {} -- frames whose clicks are still to be passed on to the map, waiting for the end of combat
local passer

local function PassLater()
    if not passer then
        passer = CreateFrame("Frame")
        passer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            for frame, button in pairs(unpassed) do frame:SetPassThroughButtons(button) end
            wipe(unpassed)
        end)
    end
    passer:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- The canvas's size and scale (the widget's own scale: nothing of the map's code runs).
local function Canvas(layer)
    local canvas = layer:GetParent()
    local width, height = canvas:GetSize()
    return canvas, width, height, math.max(0.01, canvas:GetScale())
end

local function Anchor(frame, canvas, width, height, scale)
    frame:ClearAllPoints()
    if frame.mapScreen then
        frame:SetScale(1 / scale)
        frame:SetPoint("CENTER", canvas, "TOPLEFT", frame.mapX * width * scale, -frame.mapY * height * scale)
    else
        frame:SetScale(1)
        frame:SetPoint("CENTER", canvas, "TOPLEFT", frame.mapX * width, -frame.mapY * height)
    end
end

-- A pin of `kind` at x, y (0-1) on the map shown, given `data` (its kind's Setup has it). Only from Draw.
function Set:Add(kind, x, y, data)
    local spec = self.kinds[kind]
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local frame = pool[pool.used]
    if not frame then
        frame = spec.Create(self.layer)
        frame:SetFrameLevel(self.layer:GetFrameLevel() + math.max(0, spec.raise or 1))
        frame.mapScreen = spec.screen and true or false
        if spec.pass then
            if InCombatLockdown() then
                unpassed[frame] = spec.pass
                PassLater()
            else
                frame:SetPassThroughButtons(spec.pass)
            end
        end
        pool[pool.used] = frame
    end
    frame.mapX, frame.mapY = x, y
    if spec.Setup then spec.Setup(frame, data) end
    Anchor(frame, Canvas(self.layer))
    frame:Show()
    return frame
end

-- Drawn again from scratch at the next chance (the map closed, or the pins were taken off).
local function Forget(self)
    self.drawnMap = nil
end

local function HideAll(self)
    for _, pool in pairs(self.pools) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.used = 0
    end
    Forget(self)
end

-- Every pin for the map shown, made again, unless nothing they're drawn from has changed since the last time.
local function Draw(self)
    local map = self.provider:GetMap()
    if not (map and map:IsShown()) then return end
    local mapID = map:GetMapID()
    local width, height = map:GetCanvas():GetSize()
    if mapID == self.drawnMap and width == self.drawnWidth and height == self.drawnHeight
        and self.drawnData == self.data then
        return
    end
    self.drawnMap, self.drawnWidth, self.drawnHeight, self.drawnData = mapID, width, height, self.data
    for _, pool in pairs(self.pools) do pool.used = 0 end
    if mapID then
        local ok, err = pcall(self.spec.Draw, self, mapID)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
    for _, pool in pairs(self.pools) do
        for i = pool.used + 1, #pool do pool[i]:Hide() end
    end
end

-- A zoom: the pins that keep their size on screen are scaled and placed again (the rest zoom with the canvas).
local function Rescale(self)
    local canvas, width, height, scale = Canvas(self.layer)
    for _, pool in pairs(self.pools) do
        for i = 1, pool.used do
            if pool[i].mapScreen then Anchor(pool[i], canvas, width, height, scale) end
        end
    end
end

local function Build(self)
    local map = WorldMapFrame
    if self.provider or not (map and map.AddDataProvider and map.GetCanvas and MapCanvasDataProviderMixin) then
        return self.provider ~= nil
    end
    local layer = CreateFrame("Frame", nil, map:GetCanvas())
    layer:SetAllPoints()
    -- One below the level the map gives that kind of its own pins (only read), so a pin's raise of 1 is that level.
    local ok, level = pcall(function() return map:GetPinFrameLevelsManager():GetValidFrameLevel(self.spec.level) end)
    layer:SetFrameLevel((ok and type(level) == "number" and level or 2000) - 1)
    self.layer = layer
    local spec, set = self.spec, self
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RemoveAllData = function() HideAll(set) end
    provider.RefreshAllData = function() Draw(set) end
    provider.OnMapChanged = function(p)
        local map = p:GetMap()
        if spec.OnMapChanged and map:IsShown() then spec.OnMapChanged(map:GetMapID()) end
        Draw(set)
    end
    provider.OnCanvasScaleChanged = function() Rescale(set) end
    provider.OnCanvasSizeChanged = function() Draw(set) end
    provider.OnShow = function()
        Forget(set)
        if spec.OnShow then spec.OnShow() end
    end
    provider.OnHide = function()
        Forget(set)
        if spec.OnHide then spec.OnHide() end
    end
    self.provider = provider
    return true
end

function Set:Enable(on)
    self.wanted = on and true or false
    if not on then
        if self.added then
            local open = WorldMapFrame:IsShown()
            WorldMapFrame:RemoveDataProvider(self.provider)
            self.added = false
            if open and self.spec.OnHide then self.spec.OnHide() end
        end
        if self.layer then HideAll(self) end
        return
    end
    if not Build(self) then
        -- The world map loads with the game on Forever; waited for only if it hasn't yet.
        if not self.waiter then
            local set = self
            self.waiter = CreateFrame("Frame")
            self.waiter:SetScript("OnEvent", function(frame, _, name)
                if name ~= "Blizzard_WorldMap" then return end
                frame:UnregisterAllEvents()
                if set.wanted then set:Enable(true) end
            end)
        end
        self.waiter:RegisterEvent("ADDON_LOADED")
        return
    end
    if not self.added then
        WorldMapFrame:AddDataProvider(self.provider)
        self.added = true
        if WorldMapFrame:IsShown() then
            if self.spec.OnShow then self.spec.OnShow() end
            Draw(self)
        end
    end
end

-- The addon's data changed: drawn again now if the map is open (else the next time it opens).
function Set:Refresh()
    self.data = (self.data or 0) + 1
    if self.added and WorldMapFrame:IsShown() then Draw(self) end
end

-- Whether the world map is open (and the set on it).
function Set:Shown()
    return self.added and WorldMapFrame:IsShown() or false
end

function MapPins.New(spec)
    local set = setmetatable({ spec = spec, kinds = spec.kinds, pools = {}, data = 0 }, Set)
    for kind in pairs(spec.kinds) do set.pools[kind] = { used = 0 } end
    return set
end

-- A map pin link for chat (x, y 0-1), as /way prints them, or nil where the game allows no waypoint. Clicked, the
-- game places its own waypoint pin there and opens the map on it: the player's click, so the game's code does it.
function MapPins.Link(mapID, x, y)
    if not (mapID and x and y) then return nil end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return nil end
    return string.format("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r", mapID, math.floor(x * 10000 + 0.5),
        math.floor(y * 10000 + 0.5), MAP_PIN_HYPERLINK or "Map Pin")
end
