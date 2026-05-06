-- Pure presentation helpers for tile labels, set strings, and a
-- mahjong-friendly display ordering. No LÖVE imports — these helpers
-- format strings and compute index arrays so they can be reused by any
-- scene (table, reward, debug inspector). Geometric drawing helpers that
-- need love.graphics live in this module too, but the formatting half is
-- usable from contexts that don't render.

require("core.types")
require("game.deal_types")

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

-- A single tile rectangle with its label centered. The tile rectangle's
-- left edge sits at `x` and its top edge at `y`; size is `w` x `h`. The
-- color triplets are RGB (0..1); alpha is 1.
function M.draw_tile_box(t: Tile, x: number, y: number, w: number, h: number, fill_r: number, fill_g: number, fill_b: number, border_r: number, border_g: number, border_b: number)
   love.graphics.setColor(fill_r, fill_g, fill_b, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(border_r, border_g, border_b, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
   love.graphics.setColor(0.10, 0.10, 0.12, 1.0)
   local label = M.tile_label(t)
   local font = love.graphics.getFont()
   local fw = font:getWidth(label)
   local fh = font:getHeight()
   love.graphics.print(label, x + (w - fw) / 2, y + (h - fh) / 2)
end

-- A face-down tile rectangle (used for opponents' concealed tiles).
function M.draw_facedown_box(x: number, y: number, w: number, h: number)
   love.graphics.setColor(0.30, 0.32, 0.40, 1.0)
   love.graphics.rectangle("fill", x, y, w, h)
   love.graphics.setColor(0.50, 0.50, 0.60, 1.0)
   love.graphics.rectangle("line", x, y, w, h)
end

return M
