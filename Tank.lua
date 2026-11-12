-- FrogLib Tank: combat maths for melee and tanks, by the rules in Forever's own interface code
-- (Camelot/PaperDollFrameStats.lua and Camelot/SkillsFrame.lua). StatSheet's and FrogProt's.
-- Live values that are secret (combat) raise "unreadable" through Tank.N: call in pcall.
--
-- Stats and skills
--   Tank.N(v)                       -> v, or raises "unreadable" when nil or secret
--   Tank.Call(fn, ...)              -> a number from a stat function, or nil (missing, failed, secret)
--   Tank.StatAP(i, stat)            -> attack power from `stat` points of stat i (client's sum) or nil
--   Tank.WeaponSkill(slot)          -> skill (rank plus bonuses), its cap, its name
--   Tank.DefenseSkill()             -> defense (base plus bonuses), its cap (level x 5)
--   Tank.ArmorNow(), Tank.MeleeHit()
-- Taking hits (`over`: the enemy's level above yours; `level`: yours, default UnitLevel)
--   Tank.ArmorReduction(armor, over, level) -> share of a physical hit armor takes off
--   Tank.EffectiveHealth(s, over)   -> health / (1 - armor reduction), health, reduction;
--                                      s = { hp =, armor =, level = } (each optional: what-ifs)
--   Tank.EnemyMissChance / EnemyCritChance / EnemyCrushChance(over, defense, level) -> percent
--   Tank.IncomingTable(over, s)     -> { miss, dodge, parry, block, crit, crush, hit } percent;
--                                      s = { defense =, dodge =, parry =, block =, level = }
--   Tank.CritCapNeed(over, level)   -> defense that stops an enemy `over` levels up critting you
--   Tank.CritCapGap(over, defense, level) -> that minus your defense (positive: short of it)
-- Hitting
--   Tank.HitNeeded(over, s)         -> hit chance that means never missing; s = { skill =,
--                                      dualWield =, level = }
--   Tank.Threat()                   -> your threat multiplier, and its parts ({ label, factor })
-- Items
--   Tank.SLOTS                      equip location -> inventory slots
--   Tank.ItemStats(link, full)      -> { str, agi, sta, ..., dps } from C_Item.GetItemStats; `full`
--                                      also reads defense, dodge, parry, block, block value, hit and
--                                      crit, from the tooltip when GetItemStats lacks them
--   Tank.TargetSlots(equipLoc)      -> slot it goes in, { slots it empties }
--   Tank.Replaced(link)             -> slot, { [slot] = link } it replaces, { names }
--   Tank.ReplacedEach(link)         -> { { slot =, old =, names = } }: both rings or trinkets when
--                                      both are worn, else what Tank.Replaced picks
--   Tank.Diff(newLink, old, slot, full) -> d (new minus old for each stat; d.dps is the weapon DPS
--                                      change, main hand whole and off hand at half), main-hand DPS
--                                      change, off-hand DPS change

local Tank = FrogLib:Module("Tank", 2)
if not Tank then return end

local issecret = FrogLib.issecret

local function N(v)
    if issecret(v) or v == nil then error("unreadable", 0) end
    return v
end
Tank.N = N

local SKILL_PER_LEVEL = 5
Tank.SKILL_PER_LEVEL = SKILL_PER_LEVEL
Tank.AP_PER_DPS = 14 -- each 14 attack power adds 1 damage per second to a weapon (Classic's rule)

local function Class() return select(2, UnitClass("player")) end
local function Level(level) return level or UnitLevel("player") end

-- Attack power from a stat, as the client works it out (GetAttackPowerForStat(1, 28) = 56).
function Tank.StatAP(i, stat)
    if not GetAttackPowerForStat then return nil end
    local ok, v = pcall(GetAttackPowerForStat, i, stat)
    if ok and type(v) == "number" and not issecret(v) then return v end
end

-- A number from one of Forever's stat functions, or nil if it's missing, fails or is secret.
function Tank.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "number" and not issecret(v) then return v end
end

------------------------------------------------------------------------------
-- Skills
------------------------------------------------------------------------------

-- Weapon skills, the way Forever's sheet finds them (Camelot/PaperDollFrameStats.lua): the
-- weapon's subclass names a skill line, a druid in a form uses Feral Combat, and an empty main
-- hand is Unarmed.
local S = Enum.ItemWeaponSubclass
local WEAPON_SKILL_ID = {
    [S.Sword1H] = 43, [S.Axe1H] = 44, [S.Bows] = 45, [S.Guns] = 46, [S.Mace1H] = 54,
    [S.Sword2H] = 55, [S.Staff] = 136, [S.Mace2H] = 160, [S.Axe2H] = 172, [S.Dagger] = 173,
    [S.Thrown] = 176, [S.Crossbow] = 226, [S.Wand] = 228, [S.Polearm] = 229, [S.Unarmed] = 162,
}
local FERAL_SKILL, UNARMED_SKILL = 3014, 162

local function WeaponSkillID(slot)
    if Class() == "DRUID" and (GetShapeshiftForm() or 0) ~= 0 then return FERAL_SKILL end
    local id = GetInventoryItemID("player", slot)
    if not id then
        return slot == (INVSLOT_MAINHAND or 16) and UNARMED_SKILL or nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
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
    local base, mod = UnitDefenseSkill("player")
    return math.max(0, N(base) + N(mod)), UnitLevel("player") * SKILL_PER_LEVEL
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
        local ok, r = pcall(api, armor, level)
        if ok and type(r) == "number" and not issecret(r) then return r end
    end
    local r = armor / (armor + 400 + 85 * level)
    return math.min(0.75, math.max(0, r))
end

-- Health over the share of a hit that gets through armor.
function Tank.EffectiveHealth(s, over)
    s = s or {}
    local hp = s.hp or N(UnitHealthMax("player"))
    local r = Tank.ArmorReduction(s.armor or Tank.ArmorNow(), over, s.level)
    return hp / (1 - r), hp, r
end

-- What happens to an enemy's swing at you, `over` levels up: misses, your dodges, parries and
-- blocks (each level up takes 0.2% off those), its crits and crushing blows, and plain hits.
function Tank.IncomingTable(over, s)
    s = s or {}
    local level = Level(s.level)
    local def = s.defense or Tank.DefenseSkill() or level * SKILL_PER_LEVEL
    local drop = over * SKILL_PER_LEVEL * 0.04
    local left = 100
    local function take(v)
        v = math.max(0, math.min(left, v))
        left = left - v
        return v
    end
    local parry = s.parry or N(GetParryChance())
    local block = s.block or N(GetBlockChance())
    local dodge = s.dodge or N(GetDodgeChance())
    local t = {}
    t.miss = take(Tank.EnemyMissChance(over, def, level))
    t.dodge = take(dodge - drop)
    t.parry = take(parry > 0 and parry - drop or 0)
    t.block = take(block > 0 and block - drop or 0)
    t.crit = take(Tank.EnemyCritChance(over, def, level))
    t.crush = take(Tank.EnemyCrushChance(over, def, level))
    t.hit = left
    return t
end

-- Each point of defense takes 0.04% off an enemy's crits: 5%, plus its skill over your defense.
function Tank.CritCapNeed(over, level)
    return (Level(level) + over) * SKILL_PER_LEVEL + 125
end

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

-- The hit chance that means never missing an enemy `over` levels up.
function Tank.HitNeeded(over, s)
    s = s or {}
    local level = Level(s.level)
    local skill = s.skill or Tank.WeaponSkill(INVSLOT_MAINHAND or 16) or level * SKILL_PER_LEVEL
    local dual = s.dualWield
    if dual == nil then dual = select(2, UnitAttackSpeed("player")) and true or false end
    return MELEE_MISS[over] + SkillShort(skill, level) * 0.04 + (dual and 19 or 0)
end

------------------------------------------------------------------------------
-- Threat: your multiplier from stance or form, talents and Salvation
------------------------------------------------------------------------------

-- Any of these spells known (a talent's ranks, or a spell's).
local function KnowsRank(ids)
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return 0 end
    local best = 0
    for rank, id in ipairs(ids) do
        if known(id) then best = rank end
    end
    return best
end

-- The active stance or form's spell.
local function FormSpell()
    local i = GetShapeshiftForm and GetShapeshiftForm() or 0
    if i == 0 or not GetShapeshiftFormInfo then return nil end
    local _, active, _, spellID = GetShapeshiftFormInfo(i)
    return spellID
end

local function HasBuff(...)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return false end
    for _, id in ipairs({ ... }) do
        local ok, aura = pcall(get, id)
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
    local class, parts, mult = Class(), {}, 1
    local function add(label, factor)
        parts[#parts + 1] = { label, factor }
        mult = mult * factor
    end
    if class == "WARRIOR" then
        local stance = WARRIOR_STANCES[FormSpell() or 0]
        if stance then add(stance[2], stance[1]) end
        local rank = KnowsRank(DEFIANCE)
        if rank > 0 and stance and stance[1] > 1 then add("Defiance", 1 + 0.03 * rank) end
    elseif class == "DRUID" then
        if BEAR[FormSpell() or 0] then
            add("Bear Form", 1.3)
            local rank = KnowsRank(FERAL_INSTINCT)
            if rank > 0 then add("Feral Instinct", 1 + 0.03 * rank) end
        end
    elseif class == "ROGUE" then
        add("Rogues", 0.71)
    elseif class == "PALADIN" then
        if HasBuff(25780) then
            local rank = KnowsRank(IMPROVED_FURY)
            -- Improved Righteous Fury adds a sixth more of the bonus per rank (x1.7, x1.8, x1.9).
            add("Righteous Fury (holy spells)", 1 + 0.6 * (1 + rank / 6))
        end
    end
    if HasBuff(1038, 25895) then add("Blessing of Salvation", 0.7) end
    return mult, parts
end

------------------------------------------------------------------------------
-- Items: what one would change if it replaced what's in its slot
------------------------------------------------------------------------------

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
    local out = {}
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not issecret(text) then out[#out + 1] = text end
    end
    return out
end

local function FromLines(lines, pattern)
    if not lines then return 0 end
    local total = 0
    for _, text in ipairs(lines) do
        local v = text:match(pattern)
        if v then total = total + (tonumber(v) or 0) end
    end
    return total
end

function Tank.ItemStats(link, full)
    local out = {}
    local stats = link and C_Item.GetItemStats(link) or {}
    for k, key in pairs(KEYS) do out[k] = tonumber(stats[key]) or 0 end
    out.sp = math.max(out.sp, out.spdmg)
    out.mp5 = out.mp5 + out.mp5b
    if full then
        local lines
        local function tip()
            if lines == nil then lines = link and TooltipLines(link) or false end
            return lines or nil
        end
        for k, pair in pairs(TANK_KEYS) do
            out[k] = tonumber(stats[pair[1]]) or 0
        end
        -- One key may stand for both a shield's own block and "Equip: block value": the tooltip
        -- tells them apart when it can.
        if link then
            local own = FromLines(tip(), TANK_KEYS.shieldBlock[2])
            local equip = FromLines(tip(), TANK_KEYS.blockValue[2])
            if own + equip > 0 then out.blockValue = own + equip end
        end
        out.shieldBlock = nil
        for _, k in ipairs({ "defense", "dodge", "parry", "blockChance" }) do
            if out[k] == 0 and link then out[k] = FromLines(tip(), TANK_KEYS[k][2]) end
        end
        for k, pattern in pairs(TIP_ONLY) do
            if out[k] == 0 and link then out[k] = FromLines(tip(), pattern) end
        end
    end
    return out
end

local MAIN, OFF = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
Tank.MAIN, Tank.OFF = MAIN, OFF

local function Equipped(slot) return GetInventoryItemLink("player", slot) end

local function ItemLevel(link)
    local lvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    return tonumber(lvl) or 0
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
            local lvl = ItemLevel(Equipped(slot))
            if not bestLevel or lvl < bestLevel then best, bestLevel = slot, lvl end
        end
    end
    return best, { best }
end

-- The slot, the { [slot] = link } it replaces and their names; nil when it doesn't go anywhere.
function Tank.Replaced(link)
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slot, replaced = Tank.TargetSlots(equipLoc)
    if not slot then return nil end
    local old, names = {}, {}
    for _, s in ipairs(replaced) do
        local l = Equipped(s)
        if l then
            old[s] = l
            names[#names + 1] = C_Item.GetItemInfo(l) or l:match("%[(.-)%]")
        end
    end
    return slot, old, names
end

-- Every way it could go in: for a ring or trinket with both slots filled, one entry for each
-- (slot order); otherwise just what Tank.Replaced picks. Each entry is { slot =, old =, names = }.
function Tank.ReplacedEach(link)
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slots = SLOTS[equipLoc]
    if slots and (equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET")
        and Equipped(slots[1]) and Equipped(slots[2]) then
        local out = {}
        for _, s in ipairs(slots) do
            local l = Equipped(s)
            out[#out + 1] = { slot = s, old = { [s] = l }, names = { C_Item.GetItemInfo(l) or l:match("%[(.-)%]") } }
        end
        return out
    end
    local slot, old, names = Tank.Replaced(link)
    if not slot then return {} end
    return { { slot = slot, old = old, names = names } }
end

-- New minus old for every stat. `old` is one link or { [slot] = link } for everything it replaces.
-- d.dps is the weapon DPS change, per hand: the off hand hits for half (as the game's own numbers do).
function Tank.Diff(newLink, old, slot, full)
    if type(old) ~= "table" then old = { [slot] = old } end
    local new = Tank.ItemStats(newLink, full)
    local d = {}
    for k in pairs(new) do d[k] = new[k] end
    local oldDPS = { main = 0, off = 0 }
    for oslot, link in pairs(old) do
        local st = Tank.ItemStats(link, full)
        for k in pairs(d) do d[k] = d[k] - (st[k] or 0) end
        d.dps = d.dps + st.dps -- weapon DPS is settled per hand below
        if oslot == MAIN then oldDPS.main = st.dps elseif oslot == OFF then oldDPS.off = st.dps end
    end
    local dMain, dOff = -oldDPS.main, -oldDPS.off
    if slot == MAIN then dMain = dMain + new.dps elseif slot == OFF then dOff = dOff + new.dps end
    d.dps = dMain + dOff * 0.5
    return d, dMain, dOff, new
end
