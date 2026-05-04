-- Wall operations. Pure — returns new state, never mutates input.
-- No imports from love, ui, scenes, or app.

require("core.types")
local rng_mod = require("core.rng")

local M = {}

global record WallState
   tiles: {Tile}
end

global record WallDrawResult
   tile: Tile
   wall: WallState
end

global record MakeWallResult
   wall: WallState
   rng:  RngState
end

global record ReturnReshuffleResult
   wall: WallState
   rng:  RngState
end

-- Returns a shuffled WallState and updated RNG from the given tile set.
function M.make_wall(tiles: {Tile}, rng: RngState): MakeWallResult
   local result = rng_mod.shuffle_tiles(rng, tiles)
   return { wall = { tiles = result.tiles }, rng = result.rng }
end

-- Draws from the front of the wall (normal draw). Errors on empty wall.
function M.draw_front(wall: WallState): WallDrawResult
   assert(#wall.tiles > 0, "wall is empty")
   local tile = wall.tiles[1]
   local remaining: {Tile} = {}
   for i = 2, #wall.tiles do
      remaining[i - 1] = wall.tiles[i]
   end
   return { tile = tile, wall = { tiles = remaining } }
end

-- Draws from the back of the wall (Kong supplement draw). Errors on empty wall.
function M.draw_back(wall: WallState): WallDrawResult
   assert(#wall.tiles > 0, "wall is empty")
   local n = #wall.tiles
   local tile = wall.tiles[n]
   local remaining: {Tile} = {}
   for i = 1, n - 1 do
      remaining[i] = wall.tiles[i]
   end
   return { tile = tile, wall = { tiles = remaining } }
end

-- Returns up to count tiles from the front without removing them.
function M.peek_front(wall: WallState, count: integer): {Tile}
   local out: {Tile} = {}
   local limit = math.min(count, #wall.tiles)
   for i = 1, limit do
      out[i] = wall.tiles[i]
   end
   return out
end

-- Returns the number of tiles remaining in the wall.
function M.remaining(wall: WallState): integer
   return #wall.tiles
end

-- Returns a new wall containing the current wall tiles plus returned tiles, reshuffled.
-- Used by Fresh Start. The caller is responsible for tile conservation.
function M.return_and_reshuffle(wall: WallState, returned: {Tile}, rng: RngState): ReturnReshuffleResult
   local combined: {Tile} = {}
   for _, t in ipairs(wall.tiles) do
      combined[#combined + 1] = t
   end
   for _, t in ipairs(returned) do
      combined[#combined + 1] = t
   end
   local result = rng_mod.shuffle_tiles(rng, combined)
   return { wall = { tiles = result.tiles }, rng = result.rng }
end

return M
