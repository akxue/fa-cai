require("core.types")
require("game.deal_types")
local notation = require("support.hand_notation")
local calls    = require("game.calls")

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok)
   return r.tiles
end

local function tile(kind_id: string): Tile
   return { tile_id = (kind_id .. "_a") as TileId, kind_id = kind_id as TileKindId }
end

local function tile_b(kind_id: string): Tile
   return { tile_id = (kind_id .. "_b") as TileId, kind_id = kind_id as TileKindId }
end

describe("calls", function()

   describe("is_next_player", function()
      it("player 2 is next after player 1 in 4-player game", function()
         assert.is_true(calls.is_next_player(1, 2, 4))
      end)
      it("player 1 is next after player 4 (wrap)", function()
         assert.is_true(calls.is_next_player(4, 1, 4))
      end)
      it("player 3 is not next after player 1", function()
         assert.is_false(calls.is_next_player(1, 3, 4))
      end)
   end)

   describe("can_chi", function()

      it("allows valid chi by next player", function()
         local discarded = tile("tiao_2")
         local hand = parse("13t")
         -- hand[1] = tiao_1, hand[2] = tiao_3
         assert.is_true(calls.can_chi(discarded, hand, 1, 2, 4))
      end)

      it("rejects chi by non-next player", function()
         local discarded = tile("tiao_2")
         local hand = parse("13t")
         assert.is_false(calls.can_chi(discarded, hand, 1, 3, 4))
      end)

      it("rejects chi on honor tiles", function()
         local discarded = tile("east")
         local hand = parse("S N")
         assert.is_false(calls.can_chi(discarded, hand, 1, 2, 4))
      end)

      it("rejects chi with non-consecutive tiles", function()
         local discarded = tile("tiao_2")
         local hand = parse("4t 6t")
         assert.is_false(calls.can_chi(discarded, hand, 1, 2, 4))
      end)

      it("rejects chi with mixed suits", function()
         local discarded = tile("tiao_2")
         local hand = parse("1t 3w")   -- different suits
         assert.is_false(calls.can_chi(discarded, hand, 1, 2, 4))
      end)

   end)

   describe("can_peng", function()

      it("allows peng when 2 matching tiles in hand", function()
         local discarded = tile("east")
         local hand = parse("E E")
         assert.is_true(calls.can_peng(discarded, hand, 1, 2, 4))
      end)

      it("rejects peng when only 1 matching tile", function()
         local discarded = tile("east")
         local hand = parse("E S")
         assert.is_false(calls.can_peng(discarded, hand, 1, 2, 4))
      end)

      it("rejects peng by the discarder themselves", function()
         local discarded = tile("east")
         local hand = parse("E E")
         assert.is_false(calls.can_peng(discarded, hand, 1, 1, 4))
      end)

   end)

   describe("can_open_kong", function()

      it("allows open kong when 3 matching tiles in hand", function()
         local discarded = tile("fa_cai")
         local hand = parse("3F")
         assert.is_true(calls.can_open_kong(discarded, hand, 1, 3, 4))
      end)

      it("rejects open kong with only 2 matching", function()
         local discarded = tile("fa_cai")
         local hand = parse("2F")
         assert.is_false(calls.can_open_kong(discarded, hand, 1, 3, 4))
      end)

   end)

   describe("can_concealed_kong", function()

      it("allows concealed kong with 4 matching tiles", function()
         local hand = parse("4F")
         assert.is_true(calls.can_concealed_kong("fa_cai" as TileKindId, hand))
      end)

      it("rejects concealed kong with only 3 matching", function()
         local hand = parse("3F")
         assert.is_false(calls.can_concealed_kong("fa_cai" as TileKindId, hand))
      end)

   end)

   describe("can_added_kong", function()

      it("allows added kong when open peng exists and fourth tile in hand", function()
         local t = tile("east")
         local open_peng: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = { tile("east"), tile_b("east"), { tile_id = "east_c" as TileId, kind_id = "east" as TileKindId } } as {Tile},
               called_from = 2,
            }
         }
         local hand: {Tile} = { t }
         assert.is_true(calls.can_added_kong(t, hand, open_peng))
      end)

      it("rejects if no matching open peng", function()
         local t = tile("east")
         local open_peng: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = { tile("south"), tile_b("south"), { tile_id = "south_c" as TileId, kind_id = "south" as TileKindId } } as {Tile},
               called_from = 2,
            }
         }
         local hand: {Tile} = { t }
         assert.is_false(calls.can_added_kong(t, hand, open_peng))
      end)

   end)

   describe("chi_combinations", function()

      it("returns valid chi combinations from hand", function()
         local discarded = tile("tiao_5")
         local hand = parse("46t 34t")
         -- hand has: tiao_4, tiao_6, tiao_3, tiao_4 (duplicate)
         -- combinations: (3,4,5), (4,5,6)
         local combos = calls.chi_combinations(discarded, hand)
         assert.is_true(#combos > 0)
      end)

      it("returns empty for honor discard", function()
         local discarded = tile("east")
         local hand = parse("S N")
         local combos = calls.chi_combinations(discarded, hand)
         assert.are.equal(0, #combos)
      end)

      it("returns empty when no suitable tiles in hand", function()
         local discarded = tile("tiao_5")
         local hand = parse("1t 9t")   -- too far apart
         local combos = calls.chi_combinations(discarded, hand)
         assert.are.equal(0, #combos)
      end)

   end)

end)
