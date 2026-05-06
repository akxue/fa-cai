-- Asset loader. LÖVE images are loaded once at startup and cached here
-- so the render path can call assets.bg_table() without paying I/O cost
-- per frame. Paths resolve relative to the LÖVE source root, which is
-- the project root (see main.lua at the repository root and `make run`).
--
-- Tile symbol images are 128x128 ink-on-transparent stamps (numerals,
-- wind characters, dragons). The tile chrome — face shape, drop shadow,
-- thickness band, per-seat orientation — is drawn in code by ui/tile_render.tl.
-- See docs/DECISIONS.md for the rationale (one symbol asset = N tile
-- variants without re-rendering when chrome style changes).

local M = {}

local images: {string: Image} = {}

-- Mapping engine kind_id → asset path. Engine uses "tiao"/"bing", asset
-- folders use "bamboo"/"circle"; dragons map by colour. Unmapped kinds
-- (e.g. flowers, seasons — none in M1) fall back to text in tile_render.
local TILE_SYMBOL_PATH: {string: string} = {}
do
   for r = 1, 9 do
      TILE_SYMBOL_PATH["tiao_" .. tostring(r)] = "assets/symbols/bamboo/bamboo_" .. tostring(r) .. ".png"
      TILE_SYMBOL_PATH["wan_"  .. tostring(r)] = "assets/symbols/wan/wan_"        .. tostring(r) .. ".png"
      TILE_SYMBOL_PATH["bing_" .. tostring(r)] = "assets/symbols/circle/circle_"  .. tostring(r) .. ".png"
   end
   TILE_SYMBOL_PATH.east       = "assets/symbols/wind/wind_east.png"
   TILE_SYMBOL_PATH.south      = "assets/symbols/wind/wind_south.png"
   TILE_SYMBOL_PATH.west       = "assets/symbols/wind/wind_west.png"
   TILE_SYMBOL_PATH.north      = "assets/symbols/wind/wind_north.png"
   TILE_SYMBOL_PATH.fa_cai     = "assets/symbols/dragon/dragon_green.png"
   TILE_SYMBOL_PATH.hong_zhong = "assets/symbols/dragon/dragon_red.png"
   TILE_SYMBOL_PATH.bai_ban    = "assets/symbols/dragon/dragon_white.png"
end

function M.load_all()
   images.bg_table = love.graphics.newImage("assets/backgrounds/garden_table_concept_match_v1.png")
   for kind_id, path in pairs(TILE_SYMBOL_PATH) do
      images["tile_" .. kind_id] = love.graphics.newImage(path)
   end
end

function M.bg_table(): Image
   return images.bg_table
end

-- Returns nil if no symbol asset exists for this kind_id (caller should
-- fall back to a text label).
function M.tile_symbol(kind_id: string): Image
   return images["tile_" .. kind_id]
end

-- Cover-fit the background image to the current window. The image's
-- aspect ratio (1672x941, ~1.78:1) doesn't match the default window
-- (1280x800, 1.6:1), so this scales by max(sx, sy) and crops the
-- overflow symmetrically.
function M.draw_bg_cover()
   local bg = images.bg_table
   if bg == nil then return end
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()
   local iw = bg:getWidth()
   local ih = bg:getHeight()
   local scale = math.max(sw / iw, sh / ih)
   local off_x = (sw - iw * scale) / 2
   local off_y = (sh - ih * scale) / 2
   love.graphics.setColor(1, 1, 1, 1)
   love.graphics.draw(bg, off_x, off_y, 0, scale, scale, 0, 0)
end

-- draw_bg_cover then a dark semi-transparent overlay. Non-table scenes
-- (start, boon select, reward, result) use this so their UI text reads
-- clearly against the busy garden background.
function M.draw_bg_dimmed(overlay_alpha: number)
   M.draw_bg_cover()
   love.graphics.setColor(0.05, 0.06, 0.08, overlay_alpha)
   love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end

return M
