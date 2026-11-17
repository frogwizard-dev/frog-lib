-- FrogLib FSR: the five-second rule. Spending mana stops your mana regen for five seconds; this
-- tells the addons that show it (Personal Resource Tweaks, XIVPlayer, FrogFrames) when it
-- starts: from the spell cast and its mana cost, not from your mana, which the game may keep secret. A
-- secret spell falls back to a drop in your mana a moment before or after the cast, when your mana can
-- be read. And the strip they show it with, under a mana bar.

local FSR = FrogLib:Module("FSR", 4) -- 2: NewStrip; 3: Listen reads each mana change once, and only mana's;
-- 4: mana listened to only after a secret cast, nothing for classes without mana
if not FSR then return end

local issecret = FrogLib.issecret
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local WINDOW = 0.5 -- how close a mana drop and a secret cast must be to count as one

FSR.RULE = 5

-- Every part of a cost can be secret; a cost that can't be read doesn't count.
local function Costs(costs)
    for _, part in ipairs(costs) do
        if type(part) == "table" and not issecret(part.type) and part.type == MANA then
            local cost, percent = part.cost, part.costPercent
            if not issecret(cost) and type(cost) == "number" and cost > 0 then return true end
            if not issecret(percent) and type(percent) == "number" and percent > 0 then return true end
        end
    end
    return false
end

-- Whether the spell costs mana (false when it can't be told).
function FSR.CostsMana(spellID)
    if issecret(spellID) or spellID == nil then return false end
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return false end
    local read, costsMana = pcall(Costs, costs)
    return read and costsMana or false
end

------------------------------------------------------------------------------
-- Watchers
------------------------------------------------------------------------------

FSR.WatcherMethods = FSR.WatcherMethods or {}
local Watcher = FSR.WatcherMethods
FSR.WatcherMeta = FSR.WatcherMeta or { __index = Watcher }

-- onStart(time): the rule started, or started over, at GetTime() `time`. Feed it with OnCast and
-- OnMana, or let it Listen.
function FSR.NewWatcher(onStart)
    return setmetatable({ onStart = onStart }, FSR.WatcherMeta)
end

function Watcher:Start(at)
    at = at or GetTime()
    self.castAt, self.dropAt = nil, nil
    self.ends = at + FSR.RULE
    if self.onStart then self.onStart(at) end
end

-- Seconds of the rule left, or nil when it isn't running.
function Watcher:Left(now)
    if not self.ends then return nil end
    local left = self.ends - (now or GetTime())
    if left <= 0 then
        self.ends = nil
        return nil
    end
    return left
end

-- A UNIT_SPELLCAST_SUCCEEDED of yours (the ID may be secret).
function Watcher:OnCast(spellID)
    if issecret(spellID) then
        -- Can't be looked up: a drop in your mana a moment ago, or in a moment, stands in.
        self:WatchMana()
        local now = GetTime()
        if self.dropAt and now - self.dropAt < WINDOW then
            self:Start(now)
        else
            self.castAt = now
        end
    elseif FSR.CostsMana(spellID) then
        self:Start()
    end
end

-- Your mana as it changes (either may be secret).
function Watcher:OnMana(value, max)
    if issecret(value) or issecret(max) or type(value) ~= "number" then
        self.lastMana, self.lastMax = nil, nil
        return
    end
    if self.lastMana and value < self.lastMana and max == self.lastMax then
        local now = GetTime()
        if self.castAt and now - self.castAt < WINDOW then
            self:Start(now)
        else
            self.dropAt = now
        end
    end
    self.lastMana, self.lastMax = value, max
end

function Watcher:ReadMana()
    self:OnMana(UnitPower("player", MANA), UnitPowerMax("player", MANA))
end

------------------------------------------------------------------------------
-- The strip: under a mana bar, a fill and a spark running across the rule's five seconds
------------------------------------------------------------------------------

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local Strip = {}

-- Under `bar`, `below` units down: 2 `unit`s tall (a screen pixel, or 1 for the bar's own units), the
-- spark 8 by 10.
function Strip:Place(bar, below, unit)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -below)
    self:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -below)
    self:SetHeight(unit * 2)
    self.spark:SetSize(unit * 8, unit * 10)
end

function Strip:SetColor(r, g, b, a)
    self.fill:SetColorTexture(r, g, b, a or 0.95)
    self.spark:SetVertexColor(r, g, b)
end

-- left: seconds of the rule left (filled that far across), or nil to hide it.
function Strip:SetLeft(left)
    if not left then
        self:Hide()
        return
    end
    local x = (1 - left / FSR.RULE) * (self:GetWidth() or 0)
    self.fill:SetWidth(math.max(0.01, x))
    self:Show()
end

-- A hidden strip in `parent`; track: the opacity of a dark track behind the fill (nil: none).
function FSR.NewStrip(parent, track)
    local strip = CreateFrame("Frame", nil, parent)
    if track then
        strip.track = strip:CreateTexture(nil, "BACKGROUND")
        strip.track:SetAllPoints()
        strip.track:SetColorTexture(0, 0, 0, track)
    end
    strip.fill = strip:CreateTexture(nil, "ARTWORK")
    strip.fill:SetPoint("TOPLEFT")
    strip.fill:SetPoint("BOTTOMLEFT")
    strip.spark = strip:CreateTexture(nil, "OVERLAY")
    strip.spark:SetTexture(SPARK)
    strip.spark:SetBlendMode("ADD")
    strip.spark:SetPoint("CENTER", strip.fill, "RIGHT") -- on the fill's end: SetLeft only sizes the fill
    for name, method in pairs(Strip) do strip[name] = method end
    strip:Hide()
    return strip
end

-- Your mana, listened to only once a cast's spell has come secret (its cost can't be looked up, so a drop in your
-- mana is what tells); until then each cast's cost says it all, and mana ticking up costs nothing.
function Watcher:WatchMana()
    local events = self.events
    if not events or self.watchingMana then return end
    self.watchingMana = true
    pcall(events.RegisterUnitEvent, events, "UNIT_MAXPOWER", "player")
    -- Every change of your mana once: UNIT_POWER_FREQUENT has them all (UNIT_POWER_UPDATE came with it, so each
    -- change was read twice); UNIT_POWER_UPDATE only on a client without it.
    if not pcall(events.RegisterUnitEvent, events, "UNIT_POWER_FREQUENT", "player") then
        pcall(events.RegisterUnitEvent, events, "UNIT_POWER_UPDATE", "player")
    end
    self:ReadMana()
end

-- Listens to your casts (and, when needed, your mana) itself. Warriors and rogues have no mana: nothing.
function Watcher:Listen()
    if self.events then return end
    local _, class = UnitClass("player")
    if not issecret(class) and (class == "WARRIOR" or class == "ROGUE") then return end
    local events = CreateFrame("Frame")
    self.events = events
    pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Spells come secret in fights: mana is listened to from your first one too, so the first secret cast has your
    -- mana from before it to compare with (its drop can come before the cast's event).
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- A power event's token (a cast's GUID in that place) says which power: rage and energy are skipped.
    events:SetScript("OnEvent", function(_, event, _, token, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            self:OnCast(spellID)
        elseif event == "PLAYER_REGEN_DISABLED" then
            events:UnregisterEvent(event)
            self:WatchMana()
        elseif issecret(token) or token == nil or token == "MANA" then
            self:ReadMana()
        end
    end)
end
