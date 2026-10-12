-- FrogLib StatList: the character sheet's stats as one long list, Classic-style: every stat the
-- game can show, grouped (general, attributes, melee, ranged, spell, defense, resistances), not
-- just the handful Forever's own pane picks (FrogUI's stats pane, StatSheet's List tab).
-- Each line is filled by the game's own stat function (PAPERDOLL_STATINFO), so the numbers and
-- tooltips are exactly the character sheet's; a few it doesn't have are worked out from its numbers.
--
--   FrogLib.StatList.CATEGORIES = { { name, { entry, ... } }, ... }
--       entry: { stat = "PAPERDOLL_STATINFO key" } or { own = "MELEE_DPS" ... }; hideAt (leave it out
--       at this value, an off-hand that isn't there), slot (a weapon skill's slot), ranged (only
--       with a ranged weapon), icon (a resistance's icon: its row in RESIST_ICONS).
--   FrogLib.StatList.PET_CATEGORIES: the same for your pet (the game's own pet stats, its damage,
--       a hunter's pet's happiness, loyalty, training points, experience and food, resistances).
--   FrogLib.StatList.Fill(row, entry, unit) -> whether to show it. unit: "player" (the default)
--       or "pet". row needs .Label and .Value FontStrings and Show/Hide; it's left as the game's
--       stat functions leave it (tooltip, tooltip2, tooltip3, onEnterFunc, numericValue), for
--       PaperDollStatTooltip(row).
--   FrogLib.StatList.Read(entry, unit) -> label, value, tooltip lines (a table), or nil when it
--       doesn't apply: through a hidden row of its own. Label and value may be secret.
--   FrogLib.StatList.RESIST_ICONS, RESIST_STEP: the five resistance icons in one texture.

local StatList = FrogLib:Module("StatList", 3) -- 2: your pet's list, Fill and Read for a unit; 3: Forever's C_PetInfo
if not StatList then return end

local issecret = FrogLib.issecret

StatList.CATEGORIES = {
    { STAT_CATEGORY_GENERAL or "General", {
        { stat = "HEALTH" }, { stat = "POWER" }, { stat = "ALTERNATEMANA" }, { stat = "ITEMLEVEL" },
        { stat = "MOVESPEED" },
    } },
    { STAT_CATEGORY_ATTRIBUTES or STAT_CATEGORY_PRIMARY_ATTRIBUTES or "Attributes", {
        { stat = "STRENGTH" }, { stat = "AGILITY" }, { stat = "STAMINA" }, { stat = "INTELLECT" }, { stat = "SPIRIT" },
    } },
    { PLAYERSTAT_MELEE_COMBAT or MELEE or "Melee", {
        { stat = "MAINHAND_DAMAGE" }, { stat = "OFFHAND_DAMAGE", hideAt = 0 }, { own = "MELEE_DPS" },
        { stat = "ATTACK_AP" }, { stat = "ATTACK_ATTACKSPEED" }, { stat = "HITCHANCE_MELEE" }, { own = "MELEE_CRIT" },
        { stat = "EXPERTISE", hideAt = 0 }, { stat = "ARMORPEN", hideAt = 0 }, { stat = "ENERGY_REGEN" },
        { stat = "WEAPON_SKILL", slot = "MAINHANDSLOT" }, { stat = "WEAPON_SKILL", slot = "SECONDARYHANDSLOT" },
    } },
    { PLAYERSTAT_RANGED_COMBAT or RANGED or "Ranged", {
        { stat = "RANGED_DAMAGE", hideAt = 0 }, { own = "RANGED_DPS" }, { own = "RANGED_SPEED" },
        { stat = "RANGED_ATTACK_AP", hideAt = 0 }, { stat = "HITCHANCE_RANGED", ranged = true },
        { own = "RANGED_CRIT" }, { stat = "WEAPON_SKILL", slot = "RANGEDSLOT" },
    } },
    { PLAYERSTAT_SPELL_COMBAT or "Spell", {
        { stat = "SPELLPOWER" }, { stat = "SPELLHEALING" }, { stat = "HITCHANCE_SPELL" }, { own = "SPELL_CRIT" },
        { stat = "HASTE", hideAt = 0 }, { stat = "MANAREGEN" }, { stat = "SPELLPENETRATION", hideAt = 0 },
    } },
    { PLAYERSTAT_DEFENSES or DEFENSE or "Defense", {
        { stat = "ARMOR" }, { stat = "DEFENSE" }, { stat = "DODGE" }, { stat = "PARRY" }, { stat = "BLOCK" },
    } },
    { RESISTANCE_LABEL or "Resistances", {
        { stat = "ARCANE_RESIST", icon = 2 }, { stat = "FIRE_RESIST", icon = 0 }, { stat = "FROST_RESIST", icon = 3 },
        { stat = "NATURE_RESIST", icon = 1 }, { stat = "SHADOW_RESIST", icon = 4 },
    } },
}

local RESISTANCES = {
    { stat = "ARCANE_RESIST", icon = 2 }, { stat = "FIRE_RESIST", icon = 0 }, { stat = "FROST_RESIST", icon = 3 },
    { stat = "NATURE_RESIST", icon = 1 }, { stat = "SHADOW_RESIST", icon = 4 },
}

-- Your pet: the game's own pet stats (Forever's pet pane), plus its damage per second and speed,
-- its attributes where it has them, a hunter's pet's happiness and the rest, and resistances.
StatList.PET_CATEGORIES = {
    { STAT_CATEGORY_GENERAL or "General", {
        { stat = "HEALTH" }, { stat = "POWER" }, { stat = "ARMOR" }, { stat = "MAINHAND_DAMAGE" },
        { own = "PET_DPS" }, { own = "PET_SPEED" }, { stat = "ATTACK_AP", hideAt = 0 },
        { stat = "SPELLPOWER", hideAt = 0 }, { stat = "HITCHANCE", hideAt = 0 }, { stat = "CRITCHANCE", hideAt = 0 },
        { stat = "HASTE", hideAt = 0 }, { stat = "MOVESPEED" },
    } },
    { STAT_CATEGORY_ATTRIBUTES or STAT_CATEGORY_PRIMARY_ATTRIBUTES or "Attributes", {
        { stat = "STRENGTH", hideAt = 0 }, { stat = "AGILITY", hideAt = 0 }, { stat = "STAMINA", hideAt = 0 },
        { stat = "INTELLECT", hideAt = 0 }, { stat = "SPIRIT", hideAt = 0 },
    } },
    -- A hunter's pet's needs and progress.
    { "Care", {
        { own = "PET_HAPPINESS" }, { own = "PET_LOYALTY" }, { own = "PET_TRAINING" }, { own = "PET_XP" },
        { own = "PET_FOOD" },
    } },
    { RESISTANCE_LABEL or "Resistances", RESISTANCES },
}

-- The game's resistance icons, five stacked in one texture (fire, nature, arcane, frost, shadow).
StatList.RESIST_ICONS = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"
StatList.RESIST_STEP = 0.11328125

-- Weapon type -> its skill line, for "Swords 300/300" lines (the game's own skill IDs).
local SKILL_BY_SUBCLASS = {
    [0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55,
    [10] = 136, [13] = 162, [15] = 173, [16] = 176, [18] = 226, [19] = 228,
}

local function WeaponSkill(slotName)
    local slot = GetInventorySlotInfo(slotName)
    local itemID = slot and GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local classID, subclassID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= Enum.ItemClass.Weapon then return nil end
    return SKILL_BY_SUBCLASS[subclassID]
end

local function HasRanged()
    local slot = GetInventorySlotInfo("RANGEDSLOT")
    return slot and GetInventoryItemID("player", slot) ~= nil
end

-- Lines the game's sheet doesn't have, worked out from its own numbers: each returns label, text
-- and a tooltip line (or nil when it doesn't apply).
local OWN = {}
OWN.MELEE_DPS = function()
    local low, high = UnitDamage("player")
    local speed = UnitAttackSpeed("player")
    if not (low and speed and speed > 0) then return nil end
    return DAMAGE_PER_SECOND or "DPS", ("%.1f"):format((low + high) / 2 / speed),
        "Your main hand's average hit divided by its speed."
end
OWN.RANGED_DPS = function()
    if not HasRanged() then return nil end
    local speed, low, high = UnitRangedDamage("player")
    if not (speed and speed > 0 and low) then return nil end
    return DAMAGE_PER_SECOND or "DPS", ("%.1f"):format((low + high) / 2 / speed),
        "Your ranged weapon's average hit divided by its speed."
end
OWN.RANGED_SPEED = function()
    if not HasRanged() then return nil end
    local speed = UnitRangedDamage("player")
    if not (speed and speed > 0) then return nil end
    return WEAPON_SPEED or "Speed", ("%.2f"):format(speed), "Seconds between ranged shots."
end
OWN.MELEE_CRIT = function()
    return MELEE_CRIT_CHANCE or "Crit Chance", ("%.2f%%"):format(GetCritChance()), "Chance to crit with melee attacks."
end
OWN.RANGED_CRIT = function()
    if not HasRanged() then return nil end
    return RANGED_CRIT_CHANCE or "Crit Chance", ("%.2f%%"):format(GetRangedCritChance()),
        "Chance to crit with ranged attacks."
end
-- Your pet's.
OWN.PET_DPS = function(unit)
    local low, high = UnitDamage(unit)
    local speed = UnitAttackSpeed(unit)
    if not (low and speed and speed > 0) then return nil end
    return DAMAGE_PER_SECOND or "DPS", ("%.1f"):format((low + high) / 2 / speed),
        "Its average hit divided by its attack speed."
end
OWN.PET_SPEED = function(unit)
    local speed = UnitAttackSpeed(unit)
    if not (speed and speed > 0) then return nil end
    return ATTACK_SPEED or "Attack Speed", ("%.2f"):format(speed), "Seconds between its attacks."
end
-- A hunter's pet's care (FrogLib.Unit: Forever's C_PetInfo).
local HAPPINESS = { PET_HAPPINESS1 or "Unhappy", PET_HAPPINESS2 or "Content", PET_HAPPINESS3 or "Happy" }
local HAPPINESS_COLOR = { "|cffff4040", "|cffffd040", "|cff40ff40" }
OWN.PET_HAPPINESS = function()
    local happiness, damage = FrogLib.Unit.PetHappiness()
    if not happiness then return nil end
    return "Happiness", HAPPINESS_COLOR[happiness] .. HAPPINESS[happiness] .. "|r",
        string.format("Deals %d%% damage. Happy: 125%%, content: 100%%, unhappy: 75%%; unhappy for too long, "
            .. "it runs away. Feed it food it likes.", damage or 100)
end
OWN.PET_LOYALTY = function()
    local loyalty = FrogLib.Unit.PetLoyalty()
    if not loyalty then return nil end
    return "Loyalty", loyalty, "Rises while it's kept happy; it won't run away once it's loyal enough."
end
OWN.PET_TRAINING = function()
    local total, used = FrogLib.Unit.PetTraining()
    if not total then return nil end
    return "Training Points", ("%d free of %d"):format(total - used, total),
        "Spent at a pet trainer on its abilities; more come with its level and loyalty."
end
OWN.PET_XP = function()
    if not GetPetExperience then return nil end
    local cur, max = GetPetExperience()
    if not (cur and max and max > 0) then return nil end
    return XP or "Experience", ("%d / %d (%d%%)"):format(cur, max, cur / max * 100),
        "It levels up to your level, from the kills you share."
end
OWN.PET_FOOD = function()
    local foods = FrogLib.Unit.PetFood()
    if not foods then return nil end
    return "Eats", table.concat(foods, ", "), "The kinds of food it likes."
end

OWN.SPELL_CRIT = function()
    -- The best of the spell schools (holy to arcane), as the sheet's spell crit is.
    local best = 0
    for school = 2, 7 do best = math.max(best, GetSpellCritChance(school) or 0) end
    return SPELL_CRIT_CHANCE or "Crit Chance", ("%.2f%%"):format(best), "Chance to crit with spells."
end

function StatList.Fill(row, entry, unit)
    unit = unit or "player"
    row.onEnterFunc, row.UpdateTooltip, row.tooltip, row.tooltip2, row.tooltip3 = nil, nil, nil, nil, nil
    row.numericValue = nil
    row.Label:SetText("")
    row.Value:SetText("")
    row:Show()
    if entry.own then
        local ok, label, text, tip = pcall(OWN[entry.own], unit)
        if not (ok and label) then return false end
        row.Label:SetText((STAT_FORMAT or "%s:"):format(label))
        row.Value:SetText(text)
        row.tooltip = (HIGHLIGHT_FONT_COLOR_CODE or "|cffffffff") .. label .. " " .. text .. (FONT_COLOR_CODE_CLOSE or "|r")
        row.tooltip2 = tip
        return true
    end
    if (entry.ranged or entry.slot) and unit ~= "player" then return false end
    if entry.ranged and not HasRanged() then return false end
    local info = PAPERDOLL_STATINFO and PAPERDOLL_STATINFO[entry.stat]
    if not info then return false end
    local extra
    if entry.slot then
        extra = WeaponSkill(entry.slot)
        if not extra then return false end
    end
    local ok = pcall(info.updateFunc, row, unit, extra)
    if not ok or not row:IsShown() then return false end
    -- Blizzard's stat functions can leave secret values here (in combat or restricted content):
    -- those can't be compared, so a secret label or value just keeps the row.
    local label = row.Label:GetText()
    if not issecret(label) and (label == nil or label == "") then return false end
    local value = row.numericValue
    if entry.hideAt ~= nil and not issecret(value) and value == entry.hideAt then return false end
    return true
end

-- A row of its own, out of sight, for reading one stat at a time.
local function Scratch()
    local r = StatList.scratch
    if r then return r end
    r = CreateFrame("Frame", nil, FrogLib.Hider and FrogLib.Hider.Parent and FrogLib.Hider.Parent() or UIParent)
    r:SetSize(200, 15)
    r:Hide()
    r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.Value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    StatList.scratch = r
    return r
end

function StatList.Read(entry, unit)
    local r = Scratch()
    local shown = StatList.Fill(r, entry, unit)
    r:Hide()
    if not shown then return nil end
    local tips = {}
    for _, key in ipairs({ "tooltip", "tooltip2", "tooltip3" }) do
        local t = r[key]
        if issecret(t) or (type(t) == "string" and t ~= "") then tips[#tips + 1] = t end
    end
    return r.Label:GetText(), r.Value:GetText(), tips
end
