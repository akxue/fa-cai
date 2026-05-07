-- Pure presentation helpers for tile labels, set strings, and a
-- mahjong-friendly display ordering. The formatting half is usable from
-- contexts that don't render. The drawing half (M.draw_tile and the
-- back-compat shims) requires love.graphics and the assets module.

require("core.types")
require("game.deal_types")
local assets = require("app.assets")

local M = {}

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
-- orientation: south=player, north=top opponent (180°), east=right
-- opponent (-90°), west=left opponent (+90°). For face-down tiles
-- only the band placement is affected; the back is symmetric.

global record TileRenderOpts
   orientation: string         -- "south" | "north" | "east" | "west"; defaults to "south"
   face_down:   boolean        -- true → render the green back instead of symbol
   accent_r:    number         -- border tint (defaults to a warm parchment edge)
   accent_g:    number
   accent_b:    number
   face_r:      number         -- face fill (defaults to cream parchment)
   face_g:      number
   face_b:      number
end

local THICK <const>: number = 4   -- thickness-band depth in px
local SHADOW_OFF <const>: number = 3

-- One lookup per draw_tile call replaces three separate string-compare
-- chains in band/rotation/symbol helpers. Called ~150 times/frame.
local record OrientationInfo
   rotation:         number
   band_edge:        string   -- "s" | "n" | "e" | "w"
   sym_axes_swapped: boolean  -- true for east/west (90° rotation)
end

local ORIENTATION: {string: OrientationInfo} = {
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

-- Default opts when caller passes nil.
local DEFAULT_ORIENTATION <const>: string = "south"
local DEFAULT_ACCENT_R <const>: number = 0.55
local DEFAULT_ACCENT_G <const>: number = 0.50
local DEFAULT_ACCENT_B <const>: number = 0.40

function M.draw_tile(t: Tile, x: number, y: number, w: number, h: number, opts: TileRenderOpts)
   local orientation = (opts ~= nil and opts.orientation ~= nil and opts.orientation ~= "") and opts.orientation or DEFAULT_ORIENTATION
   local face_down = opts ~= nil and opts.face_down or false
   local accent_r = (opts ~= nil and opts.accent_r ~= nil) and opts.accent_r or DEFAULT_ACCENT_R
   local accent_g = (opts ~= nil and opts.accent_g ~= nil) and opts.accent_g or DEFAULT_ACCENT_G
   local accent_b = (opts ~= nil and opts.accent_b ~= nil) and opts.accent_b or DEFAULT_ACCENT_B
   local face_r = (opts ~= nil and opts.face_r ~= nil) and opts.face_r or 0.96
   local face_g = (opts ~= nil and opts.face_g ~= nil) and opts.face_g or 0.94
   local face_b = (opts ~= nil and opts.face_b ~= nil) and opts.face_b or 0.86
   local info = ORIENTATION[orientation] or ORIENTATION.south

   draw_shadow(x, y, w, h)

   -- Band sits a touch darker than the accent so it reads as the
   -- tile's "side" rather than a frame.
   local fx, fy, fw, fh = draw_thickness_band(x, y, w, h, info,
      accent_r * 0.6, accent_g * 0.6, accent_b * 0.6)

   if face_down then
      draw_back_pattern(fx, fy, fw, fh)
   else
      draw_tile_face(fx, fy, fw, fh, face_r, face_g, face_b)
      local img = (t ~= nil) and assets.tile_symbol(t.kind_id as string) or nil
      if img ~= nil then
         draw_symbol(img, fx, fy, fw, fh, info)
      else
         draw_text_label(t, fx, fy, fw, fh)
      end
   end

   love.graphics.setColor(accent_r, accent_g, accent_b, 1.0)
   love.graphics.rectangle("line", fx, fy, fw, fh)
end

return M
