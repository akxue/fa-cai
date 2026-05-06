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

return M
