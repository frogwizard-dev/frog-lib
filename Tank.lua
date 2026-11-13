-- FrogLib Tank: combat maths for melee and tanks, by the rules in Forever's own interface code
-- (Camelot/PaperDollFrameStats.lua and Camelot/SkillsFrame.lua), for StatSheet and FrogProt. Live
-- values the game keeps secret (in combat) raise "unreadable" through Tank.N: call in pcall. `over`:
-- an enemy's level above yours; `level`: yours (UnitLevel by default); what-if tables take made-up numbers.

local Tank = FrogLib:Module("Tank", 3) -- 3: Shares
if not Tank then return end

local issecret = FrogLib.issecret

-- The value, or raises "unreadable" when it's nil or secret.
local function N(value)
    if issecret(value) or value == nil then error("unreadable", 0) end
    return value
end
Tank.N = N

local SKILL_PER_LEVEL = 5
Tank.SKILL_PER_LEVEL = SKILL_PER_LEVEL
Tank.AP_PER_DPS = 14 -- each 14 attack power adds 1 damage per second to a weapon (Classic's rule)

local function Class() return select(2, UnitClass("player")) end
local function Level(level) return level or UnitLevel("player") end

-- Attack power from `stat` points of a stat, as the client works it out (GetAttackPowerForStat(1, 28) = 56).
function Tank.StatAP(statIndex, stat)
    if not GetAttackPowerForStat then return nil end
    local ok, value = pcall(GetAttackPowerForStat, statIndex, stat)
    if ok and type(value) == "number" and not issecret(value) then return value end
end

-- A number from one of Forever's stat functions, or nil if it's missing, fails or is secret.
function Tank.Call(Read, ...)
    if type(Read) ~= "function" then return nil end
    local ok, value = pcall(Read, ...)
    if ok and type(value) == "number" and not issecret(value) then return value end
end

-- Hands out shares of 100% in the game's order, none more than what's left: Take(share), Left().
function Tank.Shares()
    local left = 100
    local function Take(share)
        share = math.max(0, math.min(left, share))
        left = left - share
        return share
    end
    return Take, function() return left end
end

------------------------------------------------------------------------------
-- Skills
------------------------------------------------------------------------------

-- Weapon skills, the way Forever's sheet finds them (Camelot/PaperDollFrameStats.lua): the
-- weapon's subclass names a skill line, a druid in a form uses Feral Combat, and an empty main
-- hand is Unarmed.
local Subclass = Enum.ItemWeaponSubclass
local WEAPON_SKILL_ID = {
    [Subclass.Sword1H] = 43, [Subclass.Axe1H] = 44, [Subclass.Bows] = 45, [Subclass.Guns] = 46,
    [Subclass.Mace1H] = 54, [Subclass.Sword2H] = 55, [Subclass.Staff] = 136, [Subclass.Mace2H] = 160,
    [Subclass.Axe2H] = 172, [Subclass.Dagger] = 173, [Subclass.Thrown] = 176, [Subclass.Crossbow] = 226,
    [Subclass.Wand] = 228, [Subclass.Polearm] = 229, [Subclass.Unarmed] = 162,
}
local FERAL_SKILL, UNARMED_SKILL = 3014, 162

local function WeaponSkillID(slot)
    if Class() == "DRUID" and (GetShapeshiftForm() or 0) ~= 0 then return FERAL_SKILL end
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then
        return slot == (INVSLOT_MAINHAND or 16) and UNARMED_SKILL or nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= Enum.ItemClass.Weapon then return nil end
    return WEAPON_SKILL_ID[subclassID]
end

-- Your skill with the weapon in a slot (rank plus bonuses), its cap and its name.
function Tank.WeaponSkill(slot)
    local skillID = WeaponSkillID(slot)
    local get = skillID and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    if not get then return nil end
    local ok, info = pcall(get, skillID)
    if not ok or type(info) ~= "table" or type(info.rank) ~= "number" or issecret(info.rank) then return nil end
    return info.rank + (info.modifier or 0), info.maxRank, info.name
end

-- Defense skill (base plus bonuses) and its cap, your level x 5.
function Tank.DefenseSkill()
    if not UnitDefenseSkill then return nil end
    local base, bonus = UnitDefenseSkill("player")
    return math.max(0, N(base) + N(bonus)), UnitLevel("player") * SKILL_PER_LEVEL
end

function Tank.ArmorNow()
    local _, effective = UnitArmor("player")
    return N(effective)
end

function Tank.MeleeHit()
    return GetHitModifier and N(GetHitModifier() or 0) or 0
end

------------------------------------------------------------------------------
-- Taking hits
------------------------------------------------------------------------------

-- An enemy `over` levels up attacking you (Camelot/PaperDollFrameStats.lua): its weapon skill
-- is its level x 5, and each point of that over your defense moves 0.04% from its misses to its
-- crits; 15 or more points over, it can land crushing blows.
local function EnemyGap(over, defense, level)
    return (Level(level) + over) * SKILL_PER_LEVEL - defense
end

function Tank.EnemyMissChance(over, defense, level)
    return math.max(0, math.min(100, 5 - EnemyGap(over, defense, level) * 0.04))
end

function Tank.EnemyCritChance(over, defense, level)
    return math.max(0, math.min(100, 5 + EnemyGap(over, defense, level) * 0.04))
end

function Tank.EnemyCrushChance(over, defense, level)
    local gap = EnemyGap(over, math.min(defense, Level(level) * SKILL_PER_LEVEL), level)
    if gap < 15 then return 0 end
    return math.max(0, math.min(100, gap * 2 - 15))
end

-- The share of a physical hit armor takes off, against an enemy of your level (plus `over`).
-- Forever's client works it out (C_PaperDollInfo.GetArmorEffectiveness gave 24.20% for 372 armor
-- at level 9, as its own sheet says); Classic's rule, which it matches, is the fallback.
function Tank.ArmorReduction(armor, over, level)
    level = Level(level) + (over or 0)
    local api = C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness
    if api then
        local ok, reduction = pcall(api, armor, level)
        if ok and type(reduction) == "number" and not issecret(reduction) then return reduction end
    end
    local reduction = armor / (armor + 400 + 85 * level)
    return math.min(0.75, math.max(0, reduction))
end

-- Health over the share of a hit that gets through armor, health, and that share; whatIf = { hp,
-- armor, level }.
function Tank.EffectiveHealth(whatIf, over)
    whatIf = whatIf or {}
    local health = whatIf.hp or N(UnitHealthMax("player"))
    local reduction = Tank.ArmorReduction(whatIf.armor or Tank.ArmorNow(), over, whatIf.level)
    return health / (1 - reduction), health, reduction
end

-- What happens to an enemy's swing at you, as percentages: misses, your dodges, parries and blocks
-- (each level up takes 0.2% off those), its crits and crushing blows, and plain hits.
-- whatIf = { defense, dodge, parry, block, level }.
function Tank.IncomingTable(over, whatIf)
    whatIf = whatIf or {}
    local level = Level(whatIf.level)
    local defense = whatIf.defense or Tank.DefenseSkill() or level * SKILL_PER_LEVEL
    local drop = over * SKILL_PER_LEVEL * 0.04
    local Take, Left = Tank.Shares()
    local parry = whatIf.parry or N(GetParryChance())
    local block = whatIf.block or N(GetBlockChance())
    local dodge = whatIf.dodge or N(GetDodgeChance())
    local incoming = {}
    incoming.miss = Take(Tank.EnemyMissChance(over, defense, level))
    incoming.dodge = Take(dodge - drop)
    incoming.parry = Take(parry > 0 and parry - drop or 0)
    incoming.block = Take(block > 0 and block - drop or 0)
    incoming.crit = Take(Tank.EnemyCritChance(over, defense, level))
    incoming.crush = Take(Tank.EnemyCrushChance(over, defense, level))
    incoming.hit = Left()
    return incoming
end

-- The defense that stops an enemy `over` levels up critting you: each point takes 0.04% off its
-- crits, 5% plus its skill over your defense.
function Tank.CritCapNeed(over, level)
    return (Level(level) + over) * SKILL_PER_LEVEL + 125
end

-- That minus your defense (positive: short of it).
function Tank.CritCapGap(over, defense, level)
    defense = defense or Tank.DefenseSkill() or 0
    return Tank.CritCapNeed(over, level) - defense
end

------------------------------------------------------------------------------
-- Hitting
------------------------------------------------------------------------------

-- Forever's table for an enemy 0-3 levels up, for a capped weapon skill: your chance to miss it.
local MELEE_MISS = { [0] = 5.0, 5.2, 5.4, 9.0 }
Tank.MELEE_MISS = MELEE_MISS

local function SkillShort(skill, level)
    return math.max(0, Level(level) * SKILL_PER_LEVEL - skill)
end
Tank.SkillShort = SkillShort

-- The hit chance that means never missing an enemy `over` levels up. whatIf = { skill, dualWield, level }.
function Tank.HitNeeded(over, whatIf)
    whatIf = whatIf or {}
    local level = Level(whatIf.level)
    local skill = whatIf.skill or Tank.WeaponSkill(INVSLOT_MAINHAND or 16) or level * SKILL_PER_LEVEL
    local dualWield = whatIf.dualWield
    if dualWield == nil then dualWield = select(2, UnitAttackSpeed("player")) and true or false end
    return MELEE_MISS[over] + SkillShort(skill, level) * 0.04 + (dualWield and 19 or 0)
end

------------------------------------------------------------------------------
-- Threat: your multiplier from stance or form, talents and Salvation
------------------------------------------------------------------------------

-- Any of these spells known (a talent's ranks, or a spell's).
local function KnowsRank(spellIDs)
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return 0 end
    local best = 0
    for rank, spellID in ipairs(spellIDs) do
        if known(spellID) then best = rank end
    end
    return best
end

-- The active stance or form's spell.
local function FormSpell()
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if form == 0 or not GetShapeshiftFormInfo then return nil end
    local _, _, _, spellID = GetShapeshiftFormInfo(form)
    return spellID
end

local function HasBuff(...)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return false end
    for _, spellID in ipairs({ ... }) do
        local ok, aura = pcall(get, spellID)
        if ok and aura ~= nil and not issecret(aura) then return true end
    end
    return false
end

local WARRIOR_STANCES = { [71] = { 1.3, "Defensive Stance" }, [2457] = { 0.8, "Battle Stance" }, [2458] = { 0.8, "Berserker Stance" } }
local BEAR = { [5487] = true, [9634] = true }
local DEFIANCE = { 12303, 12788, 12789, 12791, 12792 }
local FERAL_INSTINCT = { 16947, 16948, 16949, 16950, 16951 }
local IMPROVED_FURY = { 20468, 20469, 20470 }
Tank.DEFIANCE = DEFIANCE
Tank.KnowsRank, Tank.HasBuff = KnowsRank, HasBuff

-- Your threat multiplier on what you do, and the parts it's made of ({ label, factor }).
function Tank.Threat()
    local class, parts, multiplier = Class(), {}, 1
    local function Add(label, factor)
        parts[#parts + 1] = { label, factor }
        multiplier = multiplier * factor
    end
    if class == "WARRIOR" then
        local stance = WARRIOR_STANCES[FormSpell() or 0]
        if stance then Add(stance[2], stance[1]) end
        local rank = KnowsRank(DEFIANCE)
        if rank > 0 and stance and stance[1] > 1 then Add("Defiance", 1 + 0.03 * rank) end
    elseif class == "DRUID" then
        if BEAR[FormSpell() or 0] then
            Add("Bear Form", 1.3)
            local rank = KnowsRank(FERAL_INSTINCT)
            if rank > 0 then Add("Feral Instinct", 1 + 0.03 * rank) end
        end
    elseif class == "ROGUE" then
        Add("Rogues", 0.71)
    elseif class == "PALADIN" then
        if HasBuff(25780) then
            local rank = KnowsRank(IMPROVED_FURY)
            -- Improved Righteous Fury adds a sixth more of the bonus per rank (x1.7, x1.8, x1.9).
            Add("Righteous Fury (holy spells)", 1 + 0.6 * (1 + rank / 6))
        end
    end
    if HasBuff(1038, 25895) then Add("Blessing of Salvation", 0.7) end
    return multiplier, parts
end

------------------------------------------------------------------------------
-- Items: what one would change if it replaced what's in its slot
------------------------------------------------------------------------------

-- Equip location -> inventory slots.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Tank.SLOTS = SLOTS

local KEYS = {
    str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
    int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
    sp = "ITEM_MOD_SPELL_POWER_SHORT", spdmg = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", armor = "RESISTANCE0_NAME",
    dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", mp5 = "ITEM_MOD_POWER_REGEN0_SHORT",
    mp5b = "ITEM_MOD_MANA_REGENERATION_SHORT", crit = "ITEM_MOD_CRIT_RATING_SHORT", hit = "ITEM_MOD_HIT_RATING_SHORT",
}

-- The tank stats, for `full` reads: GetItemStats' key, then the tooltip line (Classic's wording)
-- for when it hasn't got one. Dodge, parry, block, hit and crit are percent.
local TANK_KEYS = {
    defense = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "Increased Defense %+(%d+)" },
    dodge = { "ITEM_MOD_DODGE_RATING_SHORT", "chance to dodge an attack by (%d+)%%" },
    parry = { "ITEM_MOD_PARRY_RATING_SHORT", "chance to parry an attack by (%d+)%%" },
    blockChance = { "ITEM_MOD_BLOCK_RATING_SHORT", "chance to block attacks with a shield by (%d+)%%" },
    blockValue = { "ITEM_MOD_BLOCK_VALUE_SHORT", "block value of your shield by (%d+)" },
    shieldBlock = { "ITEM_MOD_BLOCK_VALUE_SHORT", "^(%d+) Block$" },
}
local TIP_ONLY = {
    hit = "chance to hit by (%d+)%%",
    crit = "chance to get a critical strike by (%d+)%%",
}

local function TooltipLines(link)
    local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    if not get then return nil end
    local ok, data = pcall(get, link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local lines = {}
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not issecret(text) then lines[#lines + 1] = text end
    end
    return lines
end

local function FromLines(lines, pattern)
    if not lines then return 0 end
    local total = 0
    for _, text in ipairs(lines) do
        local number = text:match(pattern)
        if number then total = total + (tonumber(number) or 0) end
    end
    return total
end

-- { str, agi, sta, ..., dps } from C_Item.GetItemStats; `full` also reads defense, dodge, parry,
-- block, block value, hit and crit, from the tooltip when GetItemStats lacks them.
function Tank.ItemStats(link, full)
    local stats = {}
    local itemStats = link and C_Item.GetItemStats(link) or {}
    for name, key in pairs(KEYS) do stats[name] = tonumber(itemStats[key]) or 0 end
    stats.sp = math.max(stats.sp, stats.spdmg)
    stats.mp5 = stats.mp5 + stats.mp5b
    if full then
        local lines
        local function Lines()
            if lines == nil then lines = link and TooltipLines(link) or false end
            return lines or nil
        end
        for name, pair in pairs(TANK_KEYS) do
            stats[name] = tonumber(itemStats[pair[1]]) or 0
        end
        -- One key may stand for both a shield's own block and "Equip: block value": the tooltip
        -- tells them apart when it can.
        if link then
            local own = FromLines(Lines(), TANK_KEYS.shieldBlock[2])
            local equip = FromLines(Lines(), TANK_KEYS.blockValue[2])
            if own + equip > 0 then stats.blockValue = own + equip end
        end
        stats.shieldBlock = nil
        for _, name in ipairs({ "defense", "dodge", "parry", "blockChance" }) do
            if stats[name] == 0 and link then stats[name] = FromLines(Lines(), TANK_KEYS[name][2]) end
        end
        for name, pattern in pairs(TIP_ONLY) do
            if stats[name] == 0 and link then stats[name] = FromLines(Lines(), pattern) end
        end
    end
    return stats
end

local MAIN, OFF = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
Tank.MAIN, Tank.OFF = MAIN, OFF

local function Equipped(slot) return GetInventoryItemLink("player", slot) end

local function ItemLevel(link)
    local itemLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    return tonumber(itemLevel) or 0
end

local function MainIsTwoHand()
    local link = Equipped(MAIN)
    return link and select(4, C_Item.GetItemInfoInstant(link)) == "INVTYPE_2HWEAPON"
end

-- The slot it would go in and the slots it would empty: an empty one if there is one; for
-- rings and trinkets the weaker (lower item level) of the two; a two-hander replaces both hands.
function Tank.TargetSlots(equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    if equipLoc == "INVTYPE_2HWEAPON" then return MAIN, { MAIN, OFF } end
    -- With a two-hander in hand, anything for either hand goes in the main hand and replaces it.
    if slots[1] == MAIN and #slots > 1 and MainIsTwoHand() then return MAIN, { MAIN } end
    if (slots[1] == OFF) and MainIsTwoHand() then return OFF, { MAIN } end
    -- A weapon for either hand goes against the off hand only while that holds a weapon too
    -- (dual wielding): never against a shield or an off-hand item, which it doesn't replace.
    if slots[1] == MAIN and #slots > 1 then
        local off = Equipped(OFF)
        local offWeapon = off and select(6, C_Item.GetItemInfoInstant(off)) == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
        if not offWeapon then return MAIN, { MAIN } end
    end
    for _, slot in ipairs(slots) do
        if not Equipped(slot) then return slot, { slot } end
    end
    local best, bestLevel = slots[1], nil
    if #slots > 1 then
        for _, slot in ipairs(slots) do
            local itemLevel = ItemLevel(Equipped(slot))
            if not bestLevel or itemLevel < bestLevel then best, bestLevel = slot, itemLevel end
        end
    end
    return best, { best }
end

local function ItemName(link)
    return C_Item.GetItemInfo(link) or link:match("%[(.-)%]")
end

-- The slot, the { [slot] = link } it replaces and their names; nil when it doesn't go anywhere.
function Tank.Replaced(link)
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slot, replaced = Tank.TargetSlots(equipLoc)
    if not slot then return nil end
    local old, names = {}, {}
    for _, replacedSlot in ipairs(replaced) do
        local oldLink = Equipped(replacedSlot)
        if oldLink then
            old[replacedSlot] = oldLink
            names[#names + 1] = ItemName(oldLink)
        end
    end
    return slot, old, names
end

-- Every way it could go in: for a ring or trinket with both slots filled, one entry for each
-- (slot order); otherwise what Tank.Replaced picks. Each entry is { slot =, old =, names = }.
function Tank.ReplacedEach(link)
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slots = SLOTS[equipLoc]
    if slots and (equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET")
        and Equipped(slots[1]) and Equipped(slots[2]) then
        local ways = {}
        for _, slot in ipairs(slots) do
            local oldLink = Equipped(slot)
            ways[#ways + 1] = { slot = slot, old = { [slot] = oldLink }, names = { ItemName(oldLink) } }
        end
        return ways
    end
    local slot, old, names = Tank.Replaced(link)
    if not slot then return {} end
    return { { slot = slot, old = old, names = names } }
end

-- New minus old for every stat, and the main and off hand DPS changes. `old` is one link or
-- { [slot] = link } for all it replaces; diff.dps counts the off hand at half, as the game does.
function Tank.Diff(newLink, old, slot, full)
    if type(old) ~= "table" then old = { [slot] = old } end
    local new = Tank.ItemStats(newLink, full)
    local diff = {}
    for name in pairs(new) do diff[name] = new[name] end
    local oldDPS = { main = 0, off = 0 }
    for oldSlot, link in pairs(old) do
        local oldStats = Tank.ItemStats(link, full)
        for name in pairs(diff) do diff[name] = diff[name] - (oldStats[name] or 0) end
        diff.dps = diff.dps + oldStats.dps -- weapon DPS is settled per hand below
        if oldSlot == MAIN then oldDPS.main = oldStats.dps elseif oldSlot == OFF then oldDPS.off = oldStats.dps end
    end
    local mainChange, offChange = -oldDPS.main, -oldDPS.off
    if slot == MAIN then mainChange = mainChange + new.dps elseif slot == OFF then offChange = offChange + new.dps end
    diff.dps = mainChange + offChange * 0.5
    return diff, mainChange, offChange, new
end
