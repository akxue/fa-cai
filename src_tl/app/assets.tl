-- Asset loader. LÖVE images are loaded once at startup and cached here
-- so the render path can call assets.bg_table() without paying I/O cost
-- per frame. Paths resolve relative to the LÖVE source root, which is
-- the project root (see main.lua at the repository root and `make run`).

local M = {}

local images: {string: Image} = {}

function M.load_all()
   images.bg_table = love.graphics.newImage("assets/backgrounds/garden_table_concept_match_v1.png")
end

function M.bg_table(): Image
   return images.bg_table
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
   love.graphics.draw(bg, off_x, off_y, 0, scale, scale)
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
