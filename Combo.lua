-- FrogLib Combo: your combo points, for the addons that draw them (Personal Resource Tweaks,
-- FrogFrames), from the numbers Blizzard's target frame uses (Forever has no class resource bar).
-- The count may be secret, so it's never compared: each pip is a status bar from i - 1 to i handed
-- the count, which the game fills or leaves empty; the colour at max is a second bar the same way.

local Combo = FrogLib:Module("Combo", 2) -- 2: Lit
if not Combo then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local POINTS = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local MAX_PIPS = 10

local function Class()
    local _, class = UnitClass("player")
    return Safe(class)
end

-- Whether this character has combo points at all.
function Combo.Has()
    local class = Class()
    return class == "ROGUE" or class == "DRUID"
end

-- Whether they're in use now: rogues always, druids in cat form.
function Combo.Active()
    local class = Class()
    if class == "ROGUE" then return true end
    if class ~= "DRUID" then return false end
    local _, token = UnitPowerType("player")
    return Safe(token) == "ENERGY"
end

-- How many you can have: 5 unless the game says otherwise, 10 at most.
function Combo.Max()
    local max = UnitPowerMax("player", POINTS)
    if issecret(max) or not max or max <= 0 then return 5 end
    return math.min(max, MAX_PIPS)
end

-- Your points on your target. May be secret: widgets only.
function Combo.Points()
    if GetComboPoints then return GetComboPoints("player", "target") end
    return UnitPower("player", POINTS)
end

------------------------------------------------------------------------------
-- A row of pips
------------------------------------------------------------------------------

Combo.RowMethods = Combo.RowMethods or {}
local Row = Combo.RowMethods
Combo.RowMeta = Combo.RowMeta or { __index = Row }

-- make(i, holder) -> pip, bar: a pip of the addon's own look on `holder`, and its StatusBar. The
-- row's holder is for the addon to place; Layout sizes it.
function Combo.NewRow(parent, make)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    return setmetatable({ holder = holder, make = make, pips = {}, count = 0 }, Combo.RowMeta)
end

-- How many pips (the max), and whether the row shows (combo points in use, or a sample while
-- unlocked). Returns whether it shows.
function Row:Refresh(sample)
    local shown = (sample or Combo.Active()) and true or false
    self.holder:SetShown(shown)
    if not shown then return false end
    self.count = Combo.Max()
    for i = 1, self.count do
        local slot = self.pips[i]
        if not slot then
            local pip, bar = self.make(i, self.holder)
            slot = { pip = pip, bar = bar }
            self.pips[i] = slot
        end
        slot.bar:SetMinMaxValues(i - 1, i)
        slot.bar:Show()
    end
    for i = self.count + 1, #self.pips do self.pips[i].bar:Hide() end
    return true
end

-- The pips across `width`, `gap` apart, whole units each (the leftover to the first ones);
-- size(pip, width, height) sizes each.
function Row:Layout(width, height, gap, size)
    local count = math.max(1, self.count)
    local room = math.max(count, math.floor(width - (count - 1) * gap))
    local each = math.floor(room / count)
    local extra = room - each * count
    self.holder:SetSize(width, height)
    local x = 0
    for i = 1, self.count do
        local slot, pipWidth = self.pips[i], each + (i <= extra and 1 or 0)
        size(slot.pip, pipWidth, height)
        slot.bar:ClearAllPoints()
        slot.bar:SetPoint("TOPLEFT", self.holder, "TOPLEFT", x, 0)
        x = x + pipWidth + gap
    end
end

-- 1 when you have at least i of your max points, else 0: one point's opacity, for points drawn as
-- art. Secret when the count is, then worked out by the game through a curve on your combo points.
function Combo.Lit(points, i, max)
    if not issecret(points) then return (type(points) == "number" and points >= i) and 1 or 0 end
    local Curve = FrogLib.Curve
    local alpha = Curve and Curve.Power("player", Curve.Below((i - 0.5) / max, 0, 1), POINTS)
    if issecret(alpha) or alpha ~= nil then return alpha end
    return 0
end

-- 1 with points, 0 without; secret when the count is. Shown when it can't be told.
local function Opacity(points)
    if not issecret(points) then return (type(points) == "number" and points > 0) and 1 or 0 end
    local Curve = FrogLib.Curve
    local alpha = Curve and Curve.Power("player", Curve.Empty(), POINTS)
    if issecret(alpha) or alpha ~= nil then return alpha end
    return 1
end

-- The count into every pip (3 for a sample; may be secret). hideEmpty: the row is see-through while
-- you have none, the game deciding through a curve on your combo points.
function Row:Update(sample, hideEmpty)
    if not self.holder:IsShown() then return end
    local points = sample and 3 or Combo.Points()
    for i = 1, self.count do self.pips[i].bar:SetValue(points) end
    local alpha = 1
    if hideEmpty and not sample then alpha = Opacity(points) end
    if not pcall(self.holder.SetAlpha, self.holder, alpha) then self.holder:SetAlpha(1) end
end

local POINT_EVENTS = { PLAYER_TARGET_CHANGED = true, UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true }

-- onPoints() when the count may have changed (power, a new target); onChange() when whether they
-- show or how many may have (a form, the max, the world).
function Combo.Watch(onPoints, onChange)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        events:RegisterUnitEvent(event, "player")
    end
    events:SetScript("OnEvent", function(_, event)
        if POINT_EVENTS[event] then onPoints() else onChange() end
    end)
    return events
end
