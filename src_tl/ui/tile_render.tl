-- Pure presentation helpers for tile labels, set strings, and a
-- mahjong-friendly display ordering. The formatting half is usable from
-- contexts that don't render. The drawing half (M.draw_tile and the
-- back-compat shims) requires love.graphics and the assets module.

require("core.types")
require("game.deal_types")
local assets = require("app.assets")

global enum SeatOrientation
   "south"
   "north"
   "east"
   "west"
end

global record Color
   r: number
   g: number
   b: number
end

local record TileRenderModule
   tile_label:       function(Tile): string
   format_set:       function(TileSet): string
   tile_order_key:   function(Tile): integer
   sorted_indices:   function({Tile}): {integer}
   draw_tile:        function(Tile, number, number, number, number, SeatOrientation, Color, Color)
   draw_tile_back:   function(number, number, number, number, SeatOrientation, Color)
   CREAM_FACE:       Color
   PARCHMENT_ACCENT: Color
   FACE_DOWN_ACCENT: Color
   SET_ACCENT:       Color
end

local M: TileRenderModule = {} as TileRenderModule

local KIND_LABEL: {string:string} = {
   east = "E", south = "S", west = "W", north = "N",
   fa_cai = "F", hong_zhong = "H", bai_ban = "B",
}

-- One- or two-character display label for a tile, e.g. "5T", "E", "F".
function M.tile_label(t: Tile): string
   if t == nil then return "??" end
   local k = t.kind_id as string
   local short = KIND_LABEL[k]
   if short ~= nil then return short end
   local suit, rank = k:match("^([a-z]+)_(%d+)$")
   if suit == nil then return k end
   local letter = "?"
   if suit == "tiao" then letter = "T"
   elseif suit == "wan" then letter = "W"
   elseif suit == "bing" then letter = "B" end
   return rank .. letter
end

function M.format_set(s: TileSet): string
   local parts: {string} = {}
   for _, t in ipairs(s.tiles) do parts[#parts + 1] = M.tile_label(t) end
   local body = table.concat(parts, " ")
   local kind_short = (s.kind as string):upper()
   if (s.visibility as string) == "concealed" then
      return "[" .. kind_short .. "* " .. body .. "]"
   end
   return "[" .. kind_short .. " " .. body .. "]"
end

-- Mahjong-friendly tile order for display: tiao 1-9 → wan 1-9 → bing 1-9 →
-- E S W N → F H B. Rules state stays in original (draw) order; this only
-- sorts what the human sees so pairs and runs are visually adjacent.
local KIND_ORDER: {string: integer} = {}
do
   local i = 1
   for _, suit in ipairs({"tiao", "wan", "bing"}) do
      for r = 1, 9 do
         KIND_ORDER[suit .. "_" .. tostring(r)] = i
         i = i + 1
      end
   end
   for _, h in ipairs({"east", "south", "west", "north", "fa_cai", "hong_zhong", "bai_ban"}) do
      KIND_ORDER[h] = i
      i = i + 1
   end
end

function M.tile_order_key(t: Tile): integer
   return KIND_ORDER[t.kind_id as string] or 999
end

-- Returns indices into `tiles` sorted by KIND_ORDER, with tile_id as a
-- deterministic tiebreaker. Indices are preserved so callers can still
-- reference the original slot (used for opening-action keybinds).
function M.sorted_indices(tiles: {Tile}): {integer}
   local idxs: {integer} = {}
   for i = 1, #tiles do idxs[i] = i end
   table.sort(idxs, function(a: integer, b: integer): boolean
      local ka = M.tile_order_key(tiles[a])
      local kb = M.tile_order_key(tiles[b])
      if ka ~= kb then return ka < kb end
      return (tiles[a].tile_id as string) < (tiles[b].tile_id as string)
   end)
   return idxs
end

-- ── Drawing helpers (require love.graphics) ──────────────────────────────

-- Layered render: shadow → thickness band on the table-side edge →
-- face (cream rect + bevel) → symbol image (rotated to the seat) or
-- text fallback. The band fakes 3D so the tile reads as a slab on the
-- felt rather than a flat sticker.
--
-- Orientation: south=player, north=top opponent (180°), east=right
-- (-90°), west=left (+90°). For face-down backs only the band placement
-- matters; the back pattern is rotationally symmetric.

-- Shared accent / face constants. Callers reference these instead of
-- building a fresh Color per tile, which would allocate ~9000 records
-- per second at 150 tiles/frame × 60 fps.
local CREAM_FACE      : Color = { r = 0.96, g = 0.94, b = 0.86 }
local PARCHMENT_ACCENT: Color = { r = 0.55, g = 0.50, b = 0.40 }
local FACE_DOWN_ACCENT: Color = { r = 0.30, g = 0.32, b = 0.40 }
local SET_ACCENT      : Color = { r = 0.40, g = 0.55, b = 0.45 }

local THICK <const>: number = 4   -- thickness-band depth in px
local SHADOW_OFF <const>: number = 3

-- One lookup per draw_tile call replaces string-compare chains in
-- band/rotation/symbol helpers. Called ~150 times/frame.
local record OrientationInfo
   rotation:         number
   band_edge:        string   -- "s" | "n" | "e" | "w"
   sym_axes_swapped: boolean  -- east/west (90° rotation)
end

local ORIENTATION: {SeatOrientation: OrientationInfo} = {
   south = { rotation = 0,            band_edge = "s", sym_axes_swapped = false },
   north = { rotation = math.pi,      band_edge = "n", sym_axes_swapped = false },
   east  = { rotation = -math.pi / 2, band_edge = "e", sym_axes_swapped = true  },
   west  = { rotation =  math.pi / 2, band_edge = "w", sym_axes_swapped = true  },
}

local function draw_shadow(x: number, y: number, w: number, h: number)
   love.graphics.setColor(0.0, 0.0, 0.0, 0.30)
   love.graphics.rectangle("fill", x + SHADOW_OFF, y + SHADOW_OFF, w, h)
end

-- Draw the thickness band on whichever edge is "down" for the seat.
-- Returns the inset face rect for the main face draw.
local function draw_thickness_band(x: number, y: number, w: number, h: number, info: OrientationInfo,
                                   r: number, g: number, b: number): number, number, number, number
   love.graphics.setColor(r, g, b, 1.0)
   local edge = info.band_edge
   if edge == "n" then
      love.graphics.rectangle("fill", x, y, w, THICK)
      return x, y + THICK, w, h - THICK
   elseif edge == "e" then
      love.graphics.rectangle("fill", x + w - THICK, y, THICK, h)
      return x, y, w - THICK, h
   elseif edge == "w" then
      love.graphics.rectangle("fill", x, y, THICK, h)
      return x + THICK, y, w - THICK, h
   else
      love.graphics.rectangle("fill", x, y + h - THICK, w, THICK)
      return x, y, w, h - THICK
   end
end

local function draw_tile_face(fx: number, fy: number, fw: number, fh: number, fill_r: number, fill_g: number, fill_b: number)
   love.graphics.setColor(fill_r, fill_g, fill_b, 1.0)
   love.graphics.rectangle("fill", fx, fy, fw, fh)
   love.graphics.setColor(1.0, 1.0, 1.0, 0.35)
   love.graphics.rectangle("fill", fx, fy, fw, 1)
   love.graphics.rectangle("fill", fx, fy, 1, fh)
end

-- Composite the symbol image at the centre of the face. Symbol is
-- 128×128 and inset 12% so it breathes; for 90/270° rotations the
-- target dimensions are swapped so the symbol still fills the face.
local function draw_symbol(img: Image, fx: number, fy: number, fw: number, fh: number, info: OrientationInfo)
   local pad_w = fw * 0.12
   local pad_h = fh * 0.12
   local target_w = fw - pad_w * 2
   local target_h = fh - pad_h * 2
   local iw = img:getWidth()
   local ih = img:getHeight()
   local sx, sy: number, number
   if info.sym_axes_swapped then
      sx = target_h / iw
      sy = target_w / ih
   else
      sx = target_w / iw
      sy = target_h / ih
   end
   love.graphics.setColor(1, 1, 1, 1)
   love.graphics.draw(img, fx + fw / 2, fy + fh / 2, info.rotation, sx, sy, iw / 2, ih / 2)
end

local function draw_text_label(t: Tile, fx: number, fy: number, fw: number, fh: number)
   love.graphics.setColor(0.10, 0.10, 0.12, 1.0)
   local label = M.tile_label(t)
   local font = love.graphics.getFont()
   local tw = font:getWidth(label)
   local th = font:getHeight()
   love.graphics.print(label, fx + (fw - tw) / 2, fy + (fh - th) / 2)
end

local function draw_back_pattern(fx: number, fy: number, fw: number, fh: number)
   love.graphics.setColor(0.20, 0.42, 0.30, 1.0)
   love.graphics.rectangle("fill", fx, fy, fw, fh)
   -- A simple inset rectangle in a slightly lighter green reads as a
   -- mahjong tile back without needing an asset.
   love.graphics.setColor(0.30, 0.55, 0.40, 1.0)
   local inset = math.min(fw, fh) * 0.18
   love.graphics.rectangle("fill", fx + inset, fy + inset, fw - 2 * inset, fh - 2 * inset)
   love.graphics.setColor(0.15, 0.32, 0.22, 1.0)
   love.graphics.rectangle("line", fx + inset, fy + inset, fw - 2 * inset, fh - 2 * inset)
end

function M.draw_tile(t: Tile, x: number, y: number, w: number, h: number,
                     orientation: SeatOrientation, accent: Color, face: Color)
   local info = ORIENTATION[orientation] or ORIENTATION.south
   draw_shadow(x, y, w, h)
   local fx, fy, fw, fh = draw_thickness_band(x, y, w, h, info,
      accent.r * 0.6, accent.g * 0.6, accent.b * 0.6)
   draw_tile_face(fx, fy, fw, fh, face.r, face.g, face.b)
   local img = assets.tile_symbol(t.kind_id as string)
   if img ~= nil then
      draw_symbol(img, fx, fy, fw, fh, info)
   else
      draw_text_label(t, fx, fy, fw, fh)
   end
   love.graphics.setColor(accent.r, accent.g, accent.b, 1.0)
   love.graphics.rectangle("line", fx, fy, fw, fh)
end

-- Face-down tile back. No Tile arg (identity not shown); orientation
-- only affects band placement since the back pattern is symmetric.
function M.draw_tile_back(x: number, y: number, w: number, h: number,
                          orientation: SeatOrientation, accent: Color)
   local info = ORIENTATION[orientation] or ORIENTATION.south
   draw_shadow(x, y, w, h)
   local fx, fy, fw, fh = draw_thickness_band(x, y, w, h, info,
      accent.r * 0.6, accent.g * 0.6, accent.b * 0.6)
   draw_back_pattern(fx, fy, fw, fh)
   love.graphics.setColor(accent.r, accent.g, accent.b, 1.0)
   love.graphics.rectangle("line", fx, fy, fw, fh)
end

M.CREAM_FACE       = CREAM_FACE
M.PARCHMENT_ACCENT = PARCHMENT_ACCENT
M.FACE_DOWN_ACCENT = FACE_DOWN_ACCENT
M.SET_ACCENT       = SET_ACCENT

return M
