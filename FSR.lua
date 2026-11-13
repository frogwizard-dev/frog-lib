-- FrogLib FSR: the five-second rule. Spending mana stops your mana regen for five seconds; this
-- tells the addons that show it (Personal Resource Tweaks, XIVPlayer) when it starts: from the
-- spell cast and its mana cost, not from your mana, which the game may keep secret. A secret spell
-- falls back to a drop in your mana a moment before or after the cast, when your mana can be read.

local FSR = FrogLib:Module("FSR", 1)
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

-- Listens to your casts and mana itself.
function Watcher:Listen()
    if self.events then return end
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" }) do
        pcall(events.RegisterUnitEvent, events, event, "player")
    end
    events:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            self:OnCast(spellID)
        else
            self:ReadMana()
        end
    end)
    self:ReadMana()
end
