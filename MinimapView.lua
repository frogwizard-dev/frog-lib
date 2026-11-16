-- FrogLib MinimapView: where a place in the world falls on the minimap, for anything drawn over it
-- (Lines' routes, FrogTotems' totem areas). Places are in UnitPosition's order: yards north and west.

local View = FrogLib:Module("MinimapView", 1)
if not View then return end

local issecret = FrogLib.issecret

-- The minimap's width in yards at each zoom level (0-5), outdoors and indoors (as HereBeDragons has
-- them), for a client without C_Minimap.GetViewRadius.
local YARDS = {
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}

-- The minimap as it is now: pixels per yard, its radius in pixels, whether it turns, your facing
-- (0 when it doesn't turn), whether it's square.
function View.Read()
    local width = Minimap:GetWidth()
    local across
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if radius and not issecret(radius) and radius > 0 then
        across = radius * 2
    else
        local zoom = Minimap:GetZoom() or 0
        across = (IsIndoors and IsIndoors() and YARDS.indoor or YARDS.outdoor)[zoom + 1] or 400
    end
    local rotating = GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotating then
        local playerFacing = GetPlayerFacing()
        facing = (playerFacing and not issecret(playerFacing)) and playerFacing or 0
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    return width / across, width / 2, rotating, facing, square
end

-- A place `north` and `west` yards of you -> pixels from the minimap's centre (x right, y up),
-- turned with the minimap when it turns (from View.Read).
function View.Offset(north, west, scale, rotating, facing)
    local x, y = -west * scale, north * scale
    if rotating then
        local cos, sin = math.cos(facing), math.sin(facing)
        x, y = x * cos + y * sin, -x * sin + y * cos
    end
    return x, y
end

-- Your place (north, west, instance), or nil where the game keeps it to itself (instances).
function View.Player()
    local north, west, _, instance = UnitPosition("player")
    if not north or issecret(north) or issecret(west) then return end
    return north, west, instance
end
