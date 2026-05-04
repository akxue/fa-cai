-- S01: wall, tile generation, RNG, and notation tests.

require("core.types")
local tiles_mod  = require("game.tiles")
local rng_mod    = require("core.rng")
local wall_mod   = require("game.wall")
local notation   = require("support.hand_notation")

describe("tiles", function()
   it("generates exactly 136 physical tiles", function()
      local tiles = tiles_mod.make_full_tile_set()
      assert.are.equal(136, #tiles)
   end)

   it("all tile_ids are unique", function()
      local tiles = tiles_mod.make_full_tile_set()
      local seen: {string:boolean} = {}
      for _, t in ipairs(tiles) do
         assert.is_nil(seen[t.tile_id as string])
         seen[t.tile_id as string] = true
      end
   end)

   it("each kind appears exactly 4 times", function()
      local tiles = tiles_mod.make_full_tile_set()
      local counts: {string:integer} = {}
      for _, t in ipairs(tiles) do
         local k = t.kind_id as string
         counts[k] = (counts[k] or 0) + 1
      end
      for _, k in ipairs(tiles_mod.all_kinds()) do
         assert.are.equal(4, counts[k.kind_id as string])
      end
   end)

   it("generates exactly 34 tile kinds", function()
      assert.are.equal(34, #tiles_mod.all_kinds())
   end)

   it("honor tiles have is_honor = true", function()
      for _, k in ipairs(tiles_mod.all_kinds()) do
         if k.suit == "honor" then
            assert.is_true(k.is_honor)
         else
            assert.is_false(k.is_honor)
         end
      end
   end)
end)

describe("rng", function()
   it("from_seed(0) produces non-zero state", function()
      local r = rng_mod.from_seed(0)
      assert.are_not_equal(0, r.state)
   end)

   it("same seed produces same sequence", function()
      local r1 = rng_mod.from_seed(42)
      local r2 = rng_mod.from_seed(42)
      local a = rng_mod.next_u32(r1)
      local b = rng_mod.next_u32(r2)
      assert.are.equal(a.value, b.value)
   end)

   it("next_int stays within range", function()
      local r = rng_mod.from_seed(12345)
      for _ = 1, 100 do
         local res = rng_mod.next_int(r, 1, 6)
         assert.is_true(res.value >= 1)
         assert.is_true(res.value <= 6)
         r = res.rng
      end
   end)

   it("shuffle_tiles returns all tiles and advances rng", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(99)
      local result = rng_mod.shuffle_tiles(r, all)
      assert.are.equal(136, #result.tiles)
      assert.are_not_equal(r.state, result.rng.state)
   end)

   it("shuffle is deterministic by seed", function()
      local all = tiles_mod.make_full_tile_set()
      local r1 = rng_mod.from_seed(7)
      local r2 = rng_mod.from_seed(7)
      local s1 = rng_mod.shuffle_tiles(r1, all)
      local s2 = rng_mod.shuffle_tiles(r2, all)
      assert.are.equal(s1.tiles[1].tile_id as string, s2.tiles[1].tile_id as string)
      assert.are.equal(s1.tiles[136].tile_id as string, s2.tiles[136].tile_id as string)
   end)

   it("does not mutate input tiles", function()
      local all = tiles_mod.make_full_tile_set()
      local first_id = all[1].tile_id
      local r = rng_mod.from_seed(1)
      rng_mod.shuffle_tiles(r, all)
      assert.are.equal(first_id as string, all[1].tile_id as string)
   end)
end)

describe("wall", function()
   it("make_wall produces a wall with 136 tiles", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local result = wall_mod.make_wall(all, r)
      assert.are.equal(136, wall_mod.remaining(result.wall))
   end)

   it("draw_front removes from the front", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local mw = wall_mod.make_wall(all, r)
      local first_id = mw.wall.tiles[1].tile_id
      local result = wall_mod.draw_front(mw.wall)
      assert.are.equal(first_id as string, result.tile.tile_id as string)
      assert.are.equal(135, wall_mod.remaining(result.wall))
   end)

   it("draw_back removes from the back", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local mw = wall_mod.make_wall(all, r)
      local last_id = mw.wall.tiles[136].tile_id
      local result = wall_mod.draw_back(mw.wall)
      assert.are.equal(last_id as string, result.tile.tile_id as string)
      assert.are.equal(135, wall_mod.remaining(result.wall))
   end)

   it("peek_front does not remove tiles", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local mw = wall_mod.make_wall(all, r)
      local peeked = wall_mod.peek_front(mw.wall, 5)
      assert.are.equal(5, #peeked)
      assert.are.equal(136, wall_mod.remaining(mw.wall))
   end)

   it("peek_front with count larger than wall returns all remaining", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local mw = wall_mod.make_wall(all, r)
      local peeked = wall_mod.peek_front(mw.wall, 200)
      assert.are.equal(136, #peeked)
   end)

   it("return_and_reshuffle increases wall size", function()
      local all = tiles_mod.make_full_tile_set()
      local r = rng_mod.from_seed(1)
      local mw = wall_mod.make_wall(all, r)
      -- Draw 3 tiles from front
      local d1 = wall_mod.draw_front(mw.wall)
      local d2 = wall_mod.draw_front(d1.wall)
      local d3 = wall_mod.draw_front(d2.wall)
      assert.are.equal(133, wall_mod.remaining(d3.wall))
      -- Return the 3 drawn tiles
      local returned: {Tile} = {d1.tile, d2.tile, d3.tile}
      local rr = wall_mod.return_and_reshuffle(d3.wall, returned, mw.rng)
      assert.are.equal(136, wall_mod.remaining(rr.wall))
   end)
end)

describe("hand notation", function()
   it("parses a suited sequence", function()
      local r = notation.parse("123t")
      assert.is_true(r.ok)
      assert.are.equal(3, #r.tiles)
      assert.are.equal("tiao_1_a", r.tiles[1].tile_id as string)
      assert.are.equal("tiao_2_a", r.tiles[2].tile_id as string)
      assert.are.equal("tiao_3_a", r.tiles[3].tile_id as string)
   end)

   it("parses a pair", function()
      local r = notation.parse("55t")
      assert.is_true(r.ok)
      assert.are.equal(2, #r.tiles)
      assert.are.equal("tiao_5_a", r.tiles[1].tile_id as string)
      assert.are.equal("tiao_5_b", r.tiles[2].tile_id as string)
   end)

   it("parses honor tiles", function()
      local r = notation.parse("F H B")
      assert.is_true(r.ok)
      assert.are.equal(3, #r.tiles)
      assert.are.equal("fa_cai_a",    r.tiles[1].tile_id as string)
      assert.are.equal("hong_zhong_a", r.tiles[2].tile_id as string)
      assert.are.equal("bai_ban_a",   r.tiles[3].tile_id as string)
   end)

   it("parses count-prefixed honors", function()
      local r = notation.parse("3F")
      assert.is_true(r.ok)
      assert.are.equal(3, #r.tiles)
      assert.are.equal("fa_cai_a", r.tiles[1].tile_id as string)
      assert.are.equal("fa_cai_b", r.tiles[2].tile_id as string)
      assert.are.equal("fa_cai_c", r.tiles[3].tile_id as string)
   end)

   it("parses a mixed hand", function()
      local r = notation.parse("123t 456w 789b 11t")
      assert.is_true(r.ok)
      assert.are.equal(11, #r.tiles)
   end)

   it("rejects more than 4 copies of a kind", function()
      local r = notation.parse("5F")
      assert.is_false(r.ok)
   end)

   it("rejects unknown tokens", function()
      local r = notation.parse("123x")
      assert.is_false(r.ok)
   end)
end)
