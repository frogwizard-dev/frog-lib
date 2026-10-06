-- FrogLib FSR: the five-second rule. Spending mana stops your mana regen for five seconds; this
-- tells the addons that show it (Personal Resource Tweaks, XIVPlayer) when it starts.
-- It starts from the spell cast (its mana cost, in spell data), not from your mana, which the game
-- may keep secret. When the spell itself is secret and can't be looked up, a drop in your mana
-- just before or after the cast (when your mana can be read) starts it instead.
--   FrogLib.FSR.RULE                -> 5 (seconds)
--   FrogLib.FSR.CostsMana(spellID)  -> whether the spell costs mana (false when it can't be told)
--   local w = FrogLib.FSR.NewWatcher(onStart)
--       onStart(t): the rule started, or started over, at time t (GetTime()).
--       w:OnCast(spellID)    a UNIT_SPELLCAST_SUCCEEDED of yours (the ID may be secret)
--       w:OnMana(value, max) your mana as it changes (either may be secret)
--       w:Listen()           or let it listen to your casts and mana itself
--       w:Left(now)          seconds of the rule left, or nil when it isn't running

local FSR = FrogLib:Module("FSR", 1)
if not FSR then return end

local issecret = FrogLib.issecret
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local WINDOW = 0.5 -- how close a mana drop and a secret cast must be to count as one

FSR.RULE = 5

-- Every part of a cost can be secret; a cost that can't be read doesn't count.
local function Costs(costs)
    for _, c in ipairs(costs) do
        if type(c) == "table" and not issecret(c.type) and c.type == MANA then
            local cost, percent = c.cost, c.costPercent
            if not issecret(cost) and type(cost) == "number" and cost > 0 then return true end
            if not issecret(percent) and type(percent) == "number" and percent > 0 then return true end
        end
    end
    return false
end

function FSR.CostsMana(spellID)
    if issecret(spellID) or spellID == nil then return false end
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return false end
    local fine, yes = pcall(Costs, costs)
    return fine and yes or false
end

------------------------------------------------------------------------------
-- Watchers
------------------------------------------------------------------------------

FSR.WatcherMethods = FSR.WatcherMethods or {}
local Watcher = FSR.WatcherMethods
FSR.WatcherMeta = FSR.WatcherMeta or { __index = Watcher }

function FSR.NewWatcher(onStart)
    return setmetatable({ onStart = onStart }, FSR.WatcherMeta)
end

function Watcher:Start(at)
    at = at or GetTime()
    self.castAt, self.dropAt = nil, nil
    self.ends = at + FSR.RULE
    if self.onStart then self.onStart(at) end
end

function Watcher:Left(now)
    if not self.ends then return nil end
    local left = self.ends - (now or GetTime())
    if left <= 0 then
        self.ends = nil
        return nil
    end
    return left
end

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

function Watcher:Listen()
    if self.events then return end
    local ev = CreateFrame("Frame")
    self.events = ev
    for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" }) do
        pcall(ev.RegisterUnitEvent, ev, event, "player")
    end
    ev:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            self:OnCast(spellID)
        else
            self:ReadMana()
        end
    end)
    self:ReadMana()
end
