-- FrogLib Idle: "fade when idle", for the addons that fade something while you're at rest
-- (Personal Resource Tweaks' display, FrogUI's bars, FrogFrames' unit frames).
-- Idle: out of combat, at full health, with the power at rest (rage empty, mana or energy full)
-- and, if wanted, nothing targeted. Anything else ends it at once.
-- Health and power the game keeps secret can't be compared with their maximum:
--   * Health: the game reads it through a curve (FrogLib.Curve), so the fade itself only happens
--     at full health, worked out engine-side (GateAlpha). Below full it stays shown, even though
--     nothing here can tell. Without curves (an older client), it waits for the health to settle.
--   * Power: out of combat it ticks (regen, rage decay) until it's full or empty and then stops,
--     so a few quiet seconds mean it's settled.
--
--   local w = FrogLib.Idle.NewWatcher(opts)
--       opts.unit: whose health and power ("player"). opts.onUpdate(kind): time to look again;
--       kind is "health" or "power" after a change to it, nil otherwise (combat, a target, Edit
--       Mode, or things having settled). opts.events: true to listen to the game itself (the
--       unit's health and power, combat, target, death, loading screens, Edit Mode); otherwise
--       call w:Changed(kind) on your own events. opts.enabled() -> false: no settle re-check
--       (nothing is fading).
--   w:Changed(kind)     "health" or "power" changed: noted, and looked at again once settled
--   w:Settled(kind)     quiet for Idle.SETTLE seconds
--   w:Evaluate(opts) -> idle, why, healthSecret. Never errors: when it can't tell, not idle.
--       opts.unit (default the watcher's), opts.noTarget (a target stops it), opts.hover (the
--       mouse is over it), opts.unlocked (being moved), opts.editMode (Edit Mode open stops it).
--       healthSecret: idle but for a health the game hides; fade through GateAlpha (or a fader
--       with SetGate), which keeps it shown unless the health is full.
--   FrogLib.Idle.CanGate()                 -> whether the client can read a secret health this way
--   FrogLib.Idle.GateAlpha(unit, alpha, shown) -> for SetAlpha: `shown` (default 1) below full
--       health, `alpha` at full; may be secret. nil when the client has no curves.
--   local f = FrogLib.Idle.NewFader(frame, { speedIn = 8, speedOut = 2 }) (opacity per second)
--       f:Set(want, how): fade smoothly to `want`; how "now" jumps there, "again" starts over
--       from the frame's own opacity (after Blizzard has set it back).
--       f:SetGate(unit): while set, what's written below 1 goes through GateAlpha (nil: plain).
--       f:Replay(): the gated health changed: the fade plays again from shown (unseen below full
--       health; at full it fades out smoothly). f.frame can be set or changed at any time.
-- Watchers and faders keep their methods in this part's table, so a newer copy's apply to them.

local Idle = FrogLib:Module("Idle", 1)
if not Idle then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

Idle.SETTLE = 4 -- quiet seconds after which a secret power counts as settled
-- Power that sits at empty when you're resting (it builds up in combat), rather than full.
Idle.EMPTY_AT_REST = { RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true, MAELSTROM = true,
    INSANITY = true, FURY = true, PAIN = true }
local NONE = {}

------------------------------------------------------------------------------
-- The full-health gate
------------------------------------------------------------------------------

-- Whole hundredths: one curve per opacity, however many steps a fade takes.
local function Round(v) return math.floor(v * 100 + 0.5) / 100 end

function Idle.CanGate()
    return UnitHealthPercent ~= nil and FrogLib.Curve ~= nil and FrogLib.Curve.Full(0) ~= nil
end

function Idle.GateAlpha(unit, alpha, shown)
    local Curve = FrogLib.Curve
    if not (Curve and UnitHealthPercent) then return nil end
    return Curve.Health(unit, Curve.Full(Round(alpha), Round(shown or 1)))
end

------------------------------------------------------------------------------
-- The rule
------------------------------------------------------------------------------

local function Evaluate(w, o)
    local unit = o.unit or w.unit
    if o.unlocked then return false, "unlocked" end
    if o.editMode and EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return false, "Edit Mode is open"
    end
    if o.hover then return false, "the mouse is over it" end
    if InCombatLockdown() or Safe(UnitAffectingCombat("player"))
        or (unit ~= "player" and Safe(UnitAffectingCombat(unit))) then
        return false, "in combat"
    end
    if o.noTarget then
        local t = UnitExists("target")
        if issecret(t) or t then return false, "you have a target" end
    end
    local secret = false
    local h, hm = UnitHealth(unit), UnitHealthMax(unit)
    if issecret(h) or issecret(hm) then
        -- Waiting for it to settle isn't enough on its own: a health that stays put below full
        -- looks settled too. With curves the game decides, at full health only.
        if Idle.CanGate() then
            secret = true
        elseif not w:Settled("health") then
            return false, "health is still changing"
        end
    elseif h < hm then
        return false, "health isn't full"
    end
    local kind, token = UnitPowerType(unit)
    kind, token = Safe(kind), Safe(token)
    local name = token or "power"
    local p, pm = UnitPower(unit, kind), UnitPowerMax(unit, kind)
    if issecret(p) or issecret(pm) then
        if not w:Settled("power") then return false, name .. " is still changing" end
    elseif type(p) == "number" and type(pm) == "number" and pm > 0 then
        if Idle.EMPTY_AT_REST[token] then
            if p > 0 then return false, name .. " isn't empty" end
        elseif p < pm then
            return false, name .. " isn't full"
        end
    end
    if secret then return true, "health hidden by the game: faded only at full health", true end
    return true
end

------------------------------------------------------------------------------
-- Watchers
------------------------------------------------------------------------------

Idle.WatcherMethods = Idle.WatcherMethods or {}
local Watcher = Idle.WatcherMethods
Idle.WatcherMeta = Idle.WatcherMeta or { __index = Watcher }

local UNIT_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_POWER_UPDATE = "power",
    UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power", UNIT_FLAGS = false }
-- Not every client has them all (PLAYER_UNGHOSTED), so each is tried on its own.
local WORLD_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOSTED" }

function Idle.NewWatcher(opts)
    opts = opts or NONE
    local w = setmetatable({
        unit = opts.unit or "player",
        onUpdate = opts.onUpdate,
        enabled = opts.enabled,
        lastChange = { health = 0, power = 0 },
    }, Idle.WatcherMeta)
    if opts.events then w:Listen() end
    return w
end

function Watcher:Settled(kind)
    return GetTime() - (self.lastChange[kind] or 0) >= Idle.SETTLE
end

function Watcher:Update(kind)
    if self.onUpdate then self.onUpdate(kind) end
end

-- After a change: look again once things have been quiet long enough to settle.
function Watcher:Changed(kind)
    self.lastChange[kind] = GetTime()
    if self.recheck or (self.enabled and not self.enabled()) then return end
    self.recheck = true
    local function Check()
        local wait = math.max(self.lastChange.health, self.lastChange.power) + Idle.SETTLE - GetTime()
        if wait > 0 then
            C_Timer.After(wait + 0.05, Check)
        else
            self.recheck = nil
            self:Update(nil)
        end
    end
    C_Timer.After(Idle.SETTLE + 0.05, Check)
end

function Watcher:Evaluate(o)
    local ok, idle, why, secret = pcall(Evaluate, self, o or NONE)
    if not ok then return false, "couldn't tell", false end -- when in doubt, keep things shown
    return idle and true or false, why, secret and true or false
end

function Watcher:OnEvent(event)
    local kind = UNIT_EVENTS[event]
    if kind then
        self:Changed(kind)
        self:Update(kind)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Health and power start ticking back: wait for them to settle.
        self:Changed("health")
        self:Changed("power")
    end
    self:Update(nil)
end

function Watcher:Listen()
    if self.events then return end
    local ev = CreateFrame("Frame")
    self.events = ev
    for event in pairs(UNIT_EVENTS) do pcall(ev.RegisterUnitEvent, ev, event, self.unit) end
    for _, event in ipairs(WORLD_EVENTS) do pcall(ev.RegisterEvent, ev, event) end
    ev:SetScript("OnEvent", function(_, event) self:OnEvent(event) end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() self:OnEvent("EditMode.Enter") end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function() self:OnEvent("EditMode.Exit") end, self)
    end
end

------------------------------------------------------------------------------
-- Faders: one shared driver moves them all
------------------------------------------------------------------------------

Idle.FaderMethods = Idle.FaderMethods or {}
local Fader = Idle.FaderMethods
Idle.FaderMeta = Idle.FaderMeta or { __index = Fader }
Idle.fading = Idle.fading or {} -- [fader] = true while it's moving

function Idle.NewFader(frame, opts)
    opts = opts or NONE
    return setmetatable({ frame = frame, now = 1, target = 1,
        speedIn = opts.speedIn or 8, speedOut = opts.speedOut or 2 }, Idle.FaderMeta)
end

function Idle.Tick(elapsed)
    local any = false
    for f in pairs(Idle.fading) do
        if f.now < f.target then
            f.now = math.min(f.target, f.now + elapsed * f.speedIn)
        else
            f.now = math.max(f.target, f.now - elapsed * f.speedOut)
        end
        f:Write(f.now)
        if f.now == f.target then Idle.fading[f] = nil else any = true end
    end
    if not any then Idle.driver:Hide() end
end

Idle.driver = Idle.driver or CreateFrame("Frame")
Idle.driver:Hide()
Idle.driver:SetScript("OnUpdate", function(_, elapsed) Idle.Tick(elapsed) end)

local function Run(f)
    Idle.fading[f] = true
    Idle.driver:Show()
end

-- Onto the frame: plain, or through the gate (shown below full health). If the gate can't be
-- had, or the frame won't take it, shown.
function Fader:Write(alpha)
    local frame = self.frame
    if not frame then return end
    local value = alpha
    if self.gate and alpha < 1 then
        value = Idle.GateAlpha(self.gate, alpha)
        if not (issecret(value) or value ~= nil) then value = 1 end
    end
    if not pcall(frame.SetAlpha, frame, value) then pcall(frame.SetAlpha, frame, 1) end
end

function Fader:Set(want, how)
    if how == "now" then
        self.now, self.target = want, want
        Idle.fading[self] = nil
        self:Write(want)
        return
    end
    if how == "again" then
        local a = self.frame and self.frame:GetAlpha()
        -- Our own gated opacity reads back secret: start from shown then.
        if issecret(a) or type(a) ~= "number" then a = 1 end
        self.now = a
    elseif want == self.target then
        return
    end
    self.target = want
    Run(self)
end

function Fader:SetGate(unit)
    if unit == self.gate then return end
    local was = self.gate
    self.gate = unit
    if was then
        -- What was on screen can't be told (shown, below full health): carry on from shown, so
        -- coming back (combat, a target) doesn't flash it faded first.
        self.now = 1
        if self.target < 1 then Run(self) end
    end
    self:Write(self.now)
end

-- A health change under the gate: let the gate look again. Settled, the current opacity is just
-- written again (below full health the gate shows it at once; at full it stays faded, with no
-- flash back up). Only a fade still under way is played again from shown.
function Fader:Replay()
    if not self.gate or self.target >= 1 then return end
    if self.now == self.target then
        self:Write(self.now)
        return
    end
    self.now = 1
    Run(self)
end
