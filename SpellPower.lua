-- FrogLib SpellPower: a spell's average damage or healing with your spell power in, read from the game's
-- own tooltip (which has the rank's and your level's numbers) by a pattern and coefficients that each
-- addon carries (made by _tools\make_spell_power.py from Forever's spell tables: FrogUI's every damage
-- and healing spell, StatSheet's heals). A data row: { school mask, tooltip pattern, the capture
-- holding $d (0: none), its level if under 20 (else 0), then per amount: capture, "d" damage or "h"
-- heal, coefficient, tick period in ms (0: at once) }. For FrogUI and StatSheet.

local SpellPower = FrogLib:Module("SpellPower", 1)
if not SpellPower then return end

local issecret = FrogLib.issecret

-- A spell learned below level 20 gets less from spell power, as in 1.x: 3.75% less for each level under 20.
local PENALTY_UNDER, PENALTY_PER_LEVEL = 20, 0.0375

-- "13 to 17" -> 15; "1,234" -> 1234.
function SpellPower.Middle(text)
    local sum, count = 0, 0
    for number in text:gmatch("%d[%d,]*%.?%d*") do
        local value = tonumber((number:gsub(",", "")))
        if value then sum, count = sum + value, count + 1 end
    end
    if count > 0 then return sum / count end
end

-- "12 sec" -> 12; "1.5 min" -> 90.
function SpellPower.Seconds(text)
    local number, unit = (text or ""):match("(%d+%.?%d*)%s*(%a)")
    number = tonumber(number)
    if not number then return end
    return unit == "m" and number * 60 or number
end

-- What a spell's tooltip says, by its data row: { first = "d"/"h", mask, seconds, parts = { { kind, base,
-- coefficient x penalty x ticks, tick period (0: at once) } } }; false when it holds nothing to count; nil when the tooltip
-- can't be read now (try again later). Reading tooltips is the costly part: keep the answer until your
-- spells, talents, gear or level change.
function SpellPower.Parse(spellID, info)
    local description = C_Spell.GetSpellDescription(spellID)
    if not description or issecret(description) or description == "" then return nil end
    local captures = { description:match(info[2]) }
    if #captures == 0 then return false end
    local seconds = info[3] > 0 and SpellPower.Seconds(captures[info[3]]) or nil
    local scale = info[4] > 0 and math.max(0, 1 - (PENALTY_UNDER - info[4]) * PENALTY_PER_LEVEL) or 1
    local parts, first = {}, nil
    for i = 5, #info, 4 do
        local capture, kind, coefficient, period = info[i], info[i + 1], info[i + 2], info[i + 3]
        local base = captures[capture] and SpellPower.Middle(captures[capture])
        if base then
            local ticks = 1
            if period > 0 then ticks = seconds and math.floor(seconds * 1000 / period + 0.5) or 0 end
            parts[#parts + 1] = { kind, base, coefficient * scale * ticks, period }
            first = first or kind
        end
    end
    if not first then return false end
    return { first = first, mask = info[1], seconds = seconds, parts = parts }
end

-- A parsed spell's totals with `healing` bonus healing and `damage` spell damage (for its school):
-- healing, damage, and the healing that comes over time (part of the first).
function SpellPower.Sum(entry, healing, damage)
    local healed, dealt, overTime = 0, 0, 0
    for _, part in ipairs(entry.parts) do
        if part[1] == "h" then
            local amount = part[2] + part[3] * healing
            healed = healed + amount
            if part[4] > 0 then overTime = overTime + amount end
        else
            dealt = dealt + part[2] + part[3] * damage
        end
    end
    return healed, dealt, overTime
end
