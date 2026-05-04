-- Deterministic xorshift32 RNG. Pure — no input is mutated.
-- All game randomness must go through this module, never math.random or love.math.

require("core.types")

local M = {}

global record RngState
   state: integer   -- xorshift32 internal state; must be non-zero
end

global record RngIntResult
   value: integer
   rng:   RngState
end

global record RngShuffleTilesResult
   tiles: {Tile}
   rng:   RngState
end

-- Seed must be non-zero; any zero seed is replaced with a fallback.
function M.from_seed(seed: integer): RngState
   if seed == 0 then seed = 2463534242 end
   return { state = seed }
end

-- Returns next u32 and advanced state. Does not mutate input.
function M.next_u32(rng: RngState): RngIntResult
   local s = rng.state
   s = s ~ (s << 13)
   s = s ~ (s >> 17)
   s = s ~ (s << 5)
   s = s & 0xffffffff
   if s == 0 then s = 1 end
   return { value = s, rng = { state = s } }
end

-- Returns integer in [min_value, max_value] inclusive.
function M.next_int(rng: RngState, min_value: integer, max_value: integer): RngIntResult
   local r = M.next_u32(rng)
   local range = max_value - min_value + 1
   local value = (r.value % range) + min_value
   return { value = value, rng = r.rng }
end

-- Returns a shuffled copy of tiles using Fisher-Yates. Input is not mutated.
function M.shuffle_tiles(rng: RngState, tiles: {Tile}): RngShuffleTilesResult
   local out: {Tile} = {}
   for i = 1, #tiles do
      out[i] = tiles[i]
   end
   local cur_rng = rng
   for i = #out, 2, -1 do
      local r = M.next_int(cur_rng, 1, i)
      local j = r.value
      cur_rng = r.rng
      out[i], out[j] = out[j], out[i]
   end
   return { tiles = out, rng = cur_rng }
end

return M
