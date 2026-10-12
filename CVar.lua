-- FrogLib CVar: game settings (cvars) several addons want changed, in layers, with your own put
-- back once none of them wants a change any more (FrogInteract's interact key settings all the
-- time, FrogFish's on top while a fishing pole's on). For each setting the highest layer that
-- wants it wins; the setting as it was before any of them is kept, and saved in each addon's
-- saved variables, so it comes back even after a crash or a logout mid-change.
--
--   FrogLib.CVar.Register(owner, store): once, when the addon's saved variables are loaded. store:
--       a table in them (kept up to date with the originals); what a last session left changed is
--       put back first.
--   FrogLib.CVar.Want(owner, layer, values): this owner's wanted settings ({ [cvar] = value }),
--       replacing its last; nil values: none any more. Higher layers win. Applied at once, or
--       once combat ends.
--   FrogLib.CVar.Wanted(name) -> the value winning now, and its owner (nil: yours)
-- Owners are any strings ("FrogFish:pole"); several can share one store's addon.

local CVar = FrogLib:Module("CVar", 1)
if not CVar then return end

CVar.wants = CVar.wants or {}       -- [owner] = { layer =, values = { [name] = value } }
CVar.original = CVar.original or {} -- [name] = the setting before any of ours
CVar.stores = CVar.stores or {}     -- [store] = true

local function Saved(name, value)
    for store in pairs(CVar.stores) do store[name] = value end
end

function CVar.Wanted(name)
    local best, bestLayer, who
    for owner, w in pairs(CVar.wants) do
        local v = w.values[name]
        if v ~= nil and (not bestLayer or w.layer > bestLayer) then best, bestLayer, who = v, w.layer, owner end
    end
    return best, who
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
    for _, w in pairs(CVar.wants) do
        for name in pairs(w.values) do names[name] = true end
    end
    for name in pairs(CVar.original) do names[name] = true end
    for name in pairs(names) do
        local now = GetCVar(name)
        if now ~= nil then -- a setting this client hasn't got is left out
            local want = CVar.Wanted(name)
            if want ~= nil then
                if CVar.original[name] == nil then
                    CVar.original[name] = now
                    Saved(name, now)
                end
                if now ~= tostring(want) then pcall(SetCVar, name, want) end
            elseif CVar.original[name] ~= nil then
                pcall(SetCVar, name, CVar.original[name])
                CVar.original[name] = nil
                Saved(name, nil)
            end
        end
    end
end

function CVar.Register(owner, store)
    -- Left changed by a last session: put back (unless this session has already changed it).
    for name, value in pairs(store) do
        if CVar.original[name] == nil then pcall(SetCVar, name, value) end
    end
    wipe(store)
    for name, value in pairs(CVar.original) do store[name] = value end
    CVar.stores[store] = true
end

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
