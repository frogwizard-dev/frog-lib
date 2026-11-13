-- FrogLib CVar: game settings several addons want changed, in layers, with yours put back once none
-- wants a change (FrogInteract's interact key settings all the time, FrogFish's on top while a pole
-- is on). The highest layer wanting a setting wins. Your own setting is kept in each addon's saved
-- variables, so it comes back even after a crash or a logout mid-change.

local CVar = FrogLib:Module("CVar", 1)
if not CVar then return end

CVar.wants = CVar.wants or {}       -- [owner] = { layer =, values = { [name] = value } }
CVar.original = CVar.original or {} -- [name] = the setting before any of ours
CVar.stores = CVar.stores or {}     -- [store] = true

local function Saved(name, value)
    for store in pairs(CVar.stores) do store[name] = value end
end

-- The value winning now, and its owner (nil: yours).
function CVar.Wanted(name)
    local winner, winnerLayer, winnerOwner
    for owner, want in pairs(CVar.wants) do
        local value = want.values[name]
        if value ~= nil and (not winnerLayer or want.layer > winnerLayer) then
            winner, winnerLayer, winnerOwner = value, want.layer, owner
        end
    end
    return winner, winnerOwner
end

local pending
local waiter

local function Apply()
    if InCombatLockdown() then
        pending = true
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            waiter:SetScript("OnEvent", function()
                if pending then
                    pending = nil
                    Apply()
                end
            end)
        end
        return
    end
    local names = {}
    for _, want in pairs(CVar.wants) do
        for name in pairs(want.values) do names[name] = true end
    end
    for name in pairs(CVar.original) do names[name] = true end
    for name in pairs(names) do
        local now = GetCVar(name)
        if now ~= nil then -- a setting this client hasn't got is left out
            local wanted = CVar.Wanted(name)
            if wanted ~= nil then
                if CVar.original[name] == nil then
                    CVar.original[name] = now
                    Saved(name, now)
                end
                if now ~= tostring(wanted) then pcall(SetCVar, name, wanted) end
            elseif CVar.original[name] ~= nil then
                pcall(SetCVar, name, CVar.original[name])
                CVar.original[name] = nil
                Saved(name, nil)
            end
        end
    end
end

-- Once, when the addon's saved variables are loaded. store: a table in them, kept up to date with
-- your own settings; what a last session left changed is put back first.
function CVar.Register(owner, store)
    for name, value in pairs(store) do
        if CVar.original[name] == nil then pcall(SetCVar, name, value) end -- unless this session changed it
    end
    wipe(store)
    for name, value in pairs(CVar.original) do store[name] = value end
    CVar.stores[store] = true
end

-- An owner's wanted settings ({ [cvar] = value }; owners are any strings, "FrogFish:pole"), replacing
-- its last; nil: none any more. Applied at once, or once combat ends.
function CVar.Want(owner, layer, values)
    if values and next(values) then
        CVar.wants[owner] = { layer = layer or 0, values = values }
    else
        CVar.wants[owner] = nil
    end
    Apply()
end

-- Logging out: every setting back as it was, so nothing's left changed in the game's own files.
CVar.logout = CVar.logout or CreateFrame("Frame")
CVar.logout:RegisterEvent("PLAYER_LOGOUT")
CVar.logout:SetScript("OnEvent", function()
    for name, value in pairs(CVar.original) do pcall(SetCVar, name, value) end
end)
