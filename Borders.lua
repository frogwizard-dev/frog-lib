-- FrogLib Borders: the border looks Frog Wizard's bars share (pixel edges, classic stone, our
-- Forever frame, Classic's carved bar frame), each crisp at any scale. Pixel sizes change with the
-- frame's scale: place them again when it changes.

local ADDON = ...
local Borders = FrogLib:Module("Borders", 5) -- 3: Show, Reach; 4: Carved; 5: NineSlice
if not Borders then return end

local Pixel, NoSnap = FrogLib.Pixel, FrogLib.NoSnap
-- Its art is in whichever copy won: one inside an addon (Libs\FrogLib), or FrogLib on its own.
local HOME = ADDON == "FrogLib" and "Interface\\AddOns\\FrogLib\\"
    or ("Interface\\AddOns\\" .. ADDON .. "\\Libs\\FrogLib\\")
Borders.FOREVER_FILE = HOME .. "Media\\ForeverFrame.tga"
Borders.STONE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"
local FRAME_OUT = 2
local FOREVER_ART = { size = 16, slice = 3 }
local FRAME_KEYS = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }
local CORNERS = { "tl", "tr", "bl", "br" }
local SIDES = { "top", "bottom", "left", "right" }

-- Eight textures (parts.tl, t, tr, l, r, bl, b, br) as a nine-slice of art ({ size, slice } in
-- texels) round region: corners `slice` texels square, `out` texels outside it, `unit` per texel.
function Borders.NineSlice(parts, region, art, out, unit)
    local corner, outside = art.slice * unit, out * unit
    local near, far = art.slice / art.size, (art.size - art.slice) / art.size
    parts.tl:SetTexCoord(0, near, 0, near)
    parts.t:SetTexCoord(near, far, 0, near)
    parts.tr:SetTexCoord(far, 1, 0, near)
    parts.l:SetTexCoord(0, near, near, far)
    parts.r:SetTexCoord(far, 1, near, far)
    parts.bl:SetTexCoord(0, near, far, 1)
    parts.b:SetTexCoord(near, far, far, 1)
    parts.br:SetTexCoord(far, 1, far, 1)
    for _, texture in pairs(parts) do texture:ClearAllPoints() end
    parts.tl:SetPoint("TOPLEFT", region, "TOPLEFT", -outside, outside)
    parts.tr:SetPoint("TOPRIGHT", region, "TOPRIGHT", outside, outside)
    parts.bl:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -outside, -outside)
    parts.br:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", outside, -outside)
    for _, key in ipairs(CORNERS) do parts[key]:SetSize(corner, corner) end
    parts.t:SetPoint("TOPLEFT", parts.tl, "TOPRIGHT")
    parts.t:SetPoint("BOTTOMRIGHT", parts.tr, "BOTTOMLEFT")
    parts.b:SetPoint("TOPLEFT", parts.bl, "TOPRIGHT")
    parts.b:SetPoint("BOTTOMRIGHT", parts.br, "BOTTOMLEFT")
    parts.l:SetPoint("TOPLEFT", parts.tl, "BOTTOMLEFT")
    parts.l:SetPoint("BOTTOMRIGHT", parts.bl, "TOPRIGHT")
    parts.r:SetPoint("TOPLEFT", parts.tr, "BOTTOMLEFT")
    parts.r:SetPoint("BOTTOMRIGHT", parts.br, "TOPRIGHT")
end

------------------------------------------------------------------------------
-- Pixel edges
------------------------------------------------------------------------------

Borders.EdgesMethods = Borders.EdgesMethods or {}
local Edges = Borders.EdgesMethods
Borders.EdgesMeta = Borders.EdgesMeta or { __index = Edges }

-- Four textures, made on `frame`, round `bar`.
function Borders.Edges(frame, bar, layer, sublevel)
    local edges = { frame = frame, bar = bar or frame }
    for _, key in ipairs(SIDES) do
        local texture = frame:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
        NoSnap(texture)
        edges[key] = texture
    end
    return setmetatable(edges, Borders.EdgesMeta)
end

-- `size` screen pixels thick, starting `out` pixels outside the bar.
function Edges:Place(size, out, color)
    local pixel = Pixel(self.frame)
    local thick, outside = pixel * (size or 1), pixel * (out or 0)
    local bar = self.bar
    self.top:ClearAllPoints()
    self.top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -(outside + thick), outside)
    self.top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", outside + thick, outside)
    self.top:SetHeight(thick)
    self.bottom:ClearAllPoints()
    self.bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -(outside + thick), -outside)
    self.bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", outside + thick, -outside)
    self.bottom:SetHeight(thick)
    self.left:ClearAllPoints()
    self.left:SetPoint("TOPRIGHT", bar, "TOPLEFT", -outside, outside)
    self.left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -outside, -outside)
    self.left:SetWidth(thick)
    self.right:ClearAllPoints()
    self.right:SetPoint("TOPLEFT", bar, "TOPRIGHT", outside, outside)
    self.right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", outside, -outside)
    self.right:SetWidth(thick)
    if color then self:SetColor(color) end
end

function Edges:SetColor(color)
    for _, key in ipairs(SIDES) do self[key]:SetColorTexture(color.r, color.g, color.b, color.a or 1) end
end

function Edges:SetShown(shown)
    for _, key in ipairs(SIDES) do self[key]:SetShown(shown and true or false) end
end

------------------------------------------------------------------------------
-- Classic stone
------------------------------------------------------------------------------

-- The grey stone border old frames and tooltips use, 3 units outside the bar (its line then meets
-- the fill): a BackdropTemplate frame.
function Borders.Stone(bar, levelAbove)
    local stone = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    stone:SetFrameLevel(bar:GetFrameLevel() + (levelAbove or 1))
    stone:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
    stone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
    stone:SetBackdrop({ edgeFile = Borders.STONE_FILE, edgeSize = 12 })
    stone:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
    return stone
end

function Borders.ColorStone(stone, color)
    color = color or { r = 0.75, g = 0.75, b = 0.75 }
    stone:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
end

------------------------------------------------------------------------------
-- The Forever frame
------------------------------------------------------------------------------

Borders.ForeverMethods = Borders.ForeverMethods or {}
local Forever = Borders.ForeverMethods
Borders.ForeverMeta = Borders.ForeverMeta or { __index = Forever }

-- Media\ForeverFrame.tga, 16x16: a dark outline, a light metallic rim brighter along the top and a
-- dark inner line, each a texel wide, corners cut; 2 texels out, its inner line over the fill's edge.
function Borders.Forever(bar, layer, sublevel)
    local border = { bar = bar, parts = {} }
    for _, key in ipairs(FRAME_KEYS) do
        local texture = bar:CreateTexture(nil, layer or "OVERLAY", nil, sublevel or 5)
        texture:SetTexture(Borders.FOREVER_FILE, nil, nil, "NEAREST")
        NoSnap(texture)
        border.parts[key] = texture
    end
    return setmetatable(border, Borders.ForeverMeta)
end

-- Nine-sliced at a whole number (1 to 3) of screen pixels per texel, so only its straight edges stretch.
function Forever:Place(thickness)
    Borders.NineSlice(self.parts, self.bar, FOREVER_ART, FRAME_OUT, (thickness or 1) * Pixel(self.bar))
end

function Forever:SetShown(shown)
    for _, texture in pairs(self.parts) do texture:SetShown(shown and true or false) end
end

-- Its textures, for code that needs to tell them apart from the game's (PRT hides the rest).
function Forever:Textures()
    return self.parts
end

------------------------------------------------------------------------------
-- Classic's carved bar frame
------------------------------------------------------------------------------

Borders.CARVED_FILE = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"
-- One button well of the old bar, its frame included (texels of the 256 x 256 file): the frame is
-- 4 texels on each side, the corners 7 (their rivets).
local WELL_LEFT, WELL_RIGHT, WELL_TOP, WELL_BOTTOM = 41, 88, 149, 192
local CARVED_EDGE, CARVED_CORNER = 4, 7

Borders.CarvedMethods = Borders.CarvedMethods or {}
local Carved = Borders.CarvedMethods
Borders.CarvedMeta = Borders.CarvedMeta or { __index = Carved }

-- The carved stone round each button well of the old bar (Blizzard's UI-MainMenuBar-Dwarf), its
-- riveted joints in the corners, 4 texels out from the bar.
function Borders.Carved(bar, layer, sublevel)
    local border = { bar = bar, parts = {} }
    for _, key in ipairs(FRAME_KEYS) do
        local texture = bar:CreateTexture(nil, layer or "OVERLAY", nil, sublevel or 5)
        texture:SetTexture(Borders.CARVED_FILE, nil, nil, "NEAREST")
        NoSnap(texture)
        border.parts[key] = texture
    end
    return setmetatable(border, Borders.CarvedMeta)
end

local function Cut(texture, left, right, top, bottom)
    texture:SetTexCoord(left / 256, right / 256, top / 256, bottom / 256)
end

-- Nine-sliced at a whole number (1 to 3) of screen pixels per texel.
function Carved:Place(thickness)
    local parts, bar = self.parts, self.bar
    local pixel = (thickness or 1) * Pixel(bar)
    local cornerSize, edgeSize = CARVED_CORNER * pixel, CARVED_EDGE * pixel
    local left, right, top, bottom = WELL_LEFT, WELL_RIGHT, WELL_TOP, WELL_BOTTOM
    local corner, edge = CARVED_CORNER, CARVED_EDGE
    Cut(parts.tl, left, left + corner, top, top + corner)
    Cut(parts.tr, right - corner, right, top, top + corner)
    Cut(parts.bl, left, left + corner, bottom - corner, bottom)
    Cut(parts.br, right - corner, right, bottom - corner, bottom)
    Cut(parts.t, left + corner, right - corner, top, top + edge)
    Cut(parts.b, left + corner, right - corner, bottom - edge, bottom)
    Cut(parts.l, left, left + edge, top + corner, bottom - corner)
    Cut(parts.r, right - edge, right, top + corner, bottom - corner)
    for _, texture in pairs(parts) do texture:ClearAllPoints() end
    parts.tl:SetPoint("TOPLEFT", bar, "TOPLEFT", -edgeSize, edgeSize)
    parts.tr:SetPoint("TOPRIGHT", bar, "TOPRIGHT", edgeSize, edgeSize)
    parts.bl:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -edgeSize, -edgeSize)
    parts.br:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", edgeSize, -edgeSize)
    for _, key in ipairs(CORNERS) do parts[key]:SetSize(cornerSize, cornerSize) end
    parts.t:SetPoint("TOPLEFT", parts.tl, "TOPRIGHT")
    parts.t:SetPoint("TOPRIGHT", parts.tr, "TOPLEFT")
    parts.t:SetHeight(edgeSize)
    parts.b:SetPoint("BOTTOMLEFT", parts.bl, "BOTTOMRIGHT")
    parts.b:SetPoint("BOTTOMRIGHT", parts.br, "BOTTOMLEFT")
    parts.b:SetHeight(edgeSize)
    parts.l:SetPoint("TOPLEFT", parts.tl, "BOTTOMLEFT")
    parts.l:SetPoint("BOTTOMLEFT", parts.bl, "TOPLEFT")
    parts.l:SetWidth(edgeSize)
    parts.r:SetPoint("TOPRIGHT", parts.tr, "BOTTOMRIGHT")
    parts.r:SetPoint("BOTTOMRIGHT", parts.br, "TOPRIGHT")
    parts.r:SetWidth(edgeSize)
end

function Carved:SetShown(shown)
    for _, texture in pairs(self.parts) do texture:SetShown(shown and true or false) end
end

function Carved:Textures()
    return self.parts
end

------------------------------------------------------------------------------
-- One of them
------------------------------------------------------------------------------

-- One of a bar's borders shown, the others hidden. parts = { edges, stone, forever, carved } (any may
-- be missing); style "pixel", "classic", "forever" or "carved".
function Borders.Show(parts, style, opts)
    opts = opts or {}
    local size = opts.size or 1 -- the edges', in screen pixels; 0 hides them
    if parts.edges then
        if style == "pixel" and size > 0 then parts.edges:Place(size, 0, opts.color) end
        parts.edges:SetShown(style == "pixel" and size > 0)
    end
    if parts.stone then
        if style == "classic" and opts.stoneColor then Borders.ColorStone(parts.stone, opts.stoneColor) end
        parts.stone:SetShown(style == "classic")
    end
    if parts.forever then
        if style == "forever" then parts.forever:Place(opts.thickness) end
        parts.forever:SetShown(style == "forever")
    end
    if parts.carved then
        if style == "carved" then parts.carved:Place(opts.thickness) end
        parts.carved:SetShown(style == "carved")
    end
end

-- How far that border reaches outside the bar, in screen pixels (pixel: one screen pixel in the bar's
-- units, for the stone's 3 units).
function Borders.Reach(style, opts, pixel)
    opts = opts or {}
    if style == "forever" then return FRAME_OUT * (opts.thickness or 1) end
    if style == "carved" then return CARVED_EDGE * (opts.thickness or 1) end
    if style == "classic" then return math.ceil(3 / pixel) end
    return math.max(0, opts.size or 1)
end
