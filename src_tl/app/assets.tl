-- Image cache + tile-symbol lookup. Paths resolve relative to the
-- LÖVE source root (project root; see main.lua and `make run`).
--
-- Tile symbol images are 128x128 ink-on-transparent stamps. Tile
-- chrome (face shape, shadow, thickness band, orientation) is drawn
-- in code by ui/tile_render.tl — see docs/DECISIONS.md D011.

local M = {}

local images: {string: Image} = {}
local tile_images: {string: Image} = {}

-- Engine kind_id → asset path. Engine vocabulary ("tiao"/"bing") and
-- asset folder names ("bamboo"/"circle") differ; dragons map by colour.
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
      tile_images[kind_id] = love.graphics.newImage(path)
   end
end

function M.bg_table(): Image
   return images.bg_table
end

-- Returns nil if no symbol asset exists for this kind_id; caller falls
-- back to a text label.
function M.tile_symbol(kind_id: string): Image
   return tile_images[kind_id]
end

-- Cover-fit cache. Window size rarely changes, image is immutable.
local bg_iw: number = 0
local bg_ih: number = 0
local bg_cache_sw: number = -1
local bg_cache_sh: number = -1
local bg_scale: number = 1.0
local bg_off_x: number = 0
local bg_off_y: number = 0

local function update_bg_cover_cache(sw: number, sh: number)
   if sw == bg_cache_sw and sh == bg_cache_sh then return end
   if bg_iw == 0 then
      bg_iw = images.bg_table:getWidth()
      bg_ih = images.bg_table:getHeight()
   end
   bg_scale = math.max(sw / bg_iw, sh / bg_ih)
   bg_off_x = (sw - bg_iw * bg_scale) / 2
   bg_off_y = (sh - bg_ih * bg_scale) / 2
   bg_cache_sw = sw
   bg_cache_sh = sh
end

function M.draw_bg_cover()
   local bg = images.bg_table
   if bg == nil then return end
   local sw = love.graphics.getWidth()
   local sh = love.graphics.getHeight()
   update_bg_cover_cache(sw, sh)
   love.graphics.setColor(1, 1, 1, 1)
   love.graphics.draw(bg, bg_off_x, bg_off_y, 0, bg_scale, bg_scale, 0, 0)
end

-- Cover-fit + dark overlay. Used by non-table scenes so their UI text
-- reads against the busy garden background.
local MENU_BG_ALPHA <const>: number = 0.55

function M.draw_bg_dimmed(overlay_alpha: number)
   M.draw_bg_cover()
   love.graphics.setColor(0.05, 0.06, 0.08, overlay_alpha)
   love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end

function M.draw_menu_bg()
   M.draw_bg_dimmed(MENU_BG_ALPHA)
end

-- Green-felt rect of the bg_table image, in image-pixel coordinates.
-- Tuned by eye against the 1672x941 source. The felt's bottom edge sits
-- past the visible green so the player's hand rests on the wood frame
-- rather than floating above it.
local FELT_LEFT_PX   <const>: number = 280
local FELT_RIGHT_PX  <const>: number = 1380
local FELT_TOP_PX    <const>: number = 95
local FELT_BOTTOM_PX <const>: number = 760
local BG_IMG_W       <const>: number = 1672
local BG_IMG_H       <const>: number = 941

-- Returns (x, y, w, h) of the felt area within a window of (sw, sh)
-- after the same cover-fit scaling that draw_bg_cover applies.
function M.felt_area_in_window(sw: number, sh: number): number, number, number, number
   local scale = math.max(sw / BG_IMG_W, sh / BG_IMG_H)
   local off_x = (sw - BG_IMG_W * scale) / 2
   local off_y = (sh - BG_IMG_H * scale) / 2
   local x = off_x + FELT_LEFT_PX * scale
   local y = off_y + FELT_TOP_PX  * scale
   local w = (FELT_RIGHT_PX  - FELT_LEFT_PX) * scale
   local h = (FELT_BOTTOM_PX - FELT_TOP_PX)  * scale
   return x, y, w, h
end

return M
