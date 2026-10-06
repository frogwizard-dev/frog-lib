-- FrogLib Combo: your combo points, for the addons that draw them (Personal Resource Tweaks,
-- FrogFrames). Forever has no class resource bar of its own, so they come from the numbers
-- Blizzard's target frame uses: GetComboPoints("player", "target") out of UnitPowerMax's combo
-- points. Rogues always; druids in cat form.
--
-- The count may be a secret value, so it's never compared: draw each pip as a status bar from
-- i - 1 to i and hand it the count as its value; the game fills it (count >= i) or leaves it
-- empty. The colour at max works the same way: a second bar from max - 1 to max.
--
--   FrogLib.Combo.Has()     -> whether this character has combo points at all (rogue, druid)
--   FrogLib.Combo.Active()  -> whether they're in use now: rogues always, druids in cat form
--   FrogLib.Combo.Max()     -> how many you can have (5 unless the game says otherwise; 10 at most)
--   FrogLib.Combo.Points()  -> your points on your target. May be secret: widgets only.
--   FrogLib.Combo.Watch(onPoints, onChange): events; onPoints() when the count may have changed
--       (power, a new target), onChange() when whether they show or how many may have (a form,
--       the max, the world).

local Combo = FrogLib:Module("Combo", 1)
if not Combo then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local POINTS = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local MAX_PIPS = 10

local function Class()
    local _, class = UnitClass("player")
    return Safe(class)
end

function Combo.Has()
    local class = Class()
    return class == "ROGUE" or class == "DRUID"
end

function Combo.Active()
    local class = Class()
    if class == "ROGUE" then return true end
    if class ~= "DRUID" then return false end
    local _, token = UnitPowerType("player")
    return Safe(token) == "ENERGY"
end

function Combo.Max()
    local max = UnitPowerMax("player", POINTS)
    if issecret(max) or not max or max <= 0 then return 5 end
    return math.min(max, MAX_PIPS)
end

function Combo.Points()
    if GetComboPoints then return GetComboPoints("player", "target") end
    return UnitPower("player", POINTS)
end

------------------------------------------------------------------------------
-- A row of pips
--   local row = FrogLib.Combo.NewRow(parent, make)
--       make(i, holder) -> pip, bar: a pip of the addon's own look on `holder`, and its
--       StatusBar (set from i - 1 to i here, and handed the count).
--   row.holder: the row's frame, for the addon to place (its size is set by Layout).
--   row:Refresh(sample): how many pips (the max), and whether the row shows (combo points in
--       use, or `sample`: a sample while unlocked). Returns whether it shows.
--   row:Layout(width, height, gap, size(pip, w, h)): the pips across `width`, `gap` apart,
--       whole numbers of units each (the leftover going to the first ones).
--   row:Update(sample, hideEmpty): the count into every pip (3 for a sample). May be secret.
--       hideEmpty: the row is see-through while you have none (the game decides when it hides
--       the count: through a curve on your combo points, as an opacity).
------------------------------------------------------------------------------

Combo.RowMethods = Combo.RowMethods or {}
local Row = Combo.RowMethods
Combo.RowMeta = Combo.RowMeta or { __index = Row }

function Combo.NewRow(parent, make)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    return setmetatable({ holder = holder, make = make, pips = {}, count = 0 }, Combo.RowMeta)
end

function Row:Refresh(sample)
    local shown = (sample or Combo.Active()) and true or false
    self.holder:SetShown(shown)
    if not shown then return false end
    self.count = Combo.Max()
    for i = 1, self.count do
        local p = self.pips[i]
        if not p then
            local pip, bar = self.make(i, self.holder)
            p = { pip = pip, bar = bar }
            self.pips[i] = p
        end
        p.bar:SetMinMaxValues(i - 1, i)
        p.bar:Show()
    end
    for i = self.count + 1, #self.pips do self.pips[i].bar:Hide() end
    return true
end

function Row:Layout(width, height, gap, size)
    local n = math.max(1, self.count)
    local room = math.max(n, math.floor(width - (n - 1) * gap))
    local each = math.floor(room / n)
    local extra = room - each * n
    self.holder:SetSize(width, height)
    local x = 0
    for i = 1, self.count do
        local p, w = self.pips[i], each + (i <= extra and 1 or 0)
        size(p.pip, w, height)
        p.bar:ClearAllPoints()
        p.bar:SetPoint("TOPLEFT", self.holder, "TOPLEFT", x, 0)
        x = x + w + gap
    end
end

-- 1 with points, 0 without; secret when the count is. Shown when it can't be told.
local function Opacity(points)
    if not issecret(points) then return (type(points) == "number" and points > 0) and 1 or 0 end
    local Curve = FrogLib.Curve
    local alpha = Curve and Curve.Power("player", Curve.Empty(), POINTS)
    if issecret(alpha) or alpha ~= nil then return alpha end
    return 1
end

function Row:Update(sample, hideEmpty)
    if not self.holder:IsShown() then return end
    local points = sample and 3 or Combo.Points()
    for i = 1, self.count do self.pips[i].bar:SetValue(points) end
    local alpha = 1
    if hideEmpty and not sample then alpha = Opacity(points) end
    if not pcall(self.holder.SetAlpha, self.holder, alpha) then self.holder:SetAlpha(1) end
end

local POINT_EVENTS ={ PLAYER_TARGET_CHANGED = true, UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true }

function Combo.Watch(onPoints, onChange)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        ev:RegisterUnitEvent(e, "player")
    end
    ev:SetScript("OnEvent", function(_, event)
        if POINT_EVENTS[event] then onPoints() else onChange() end
    end)
    return ev
end
