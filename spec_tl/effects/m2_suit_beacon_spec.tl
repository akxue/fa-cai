-- M2-S04 suit_beacon: every dominant-suit chi the player completes
-- grants a free extra draw via Plan B's matched-discard machinery.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
local registry = require("effects.boon_registry")
local context  = require("effects.boon_context")
local m2_boons = require("content.m2_boons")

local function tile(tile_id: string, kind_id: string): Tile
   return { tile_id = tile_id as TileId, kind_id = kind_id as TileKindId }
end

local function tiles(specs: {{string}}): {Tile}
   local out: {Tile} = {}
   for _, s in ipairs(specs) do
      out[#out + 1] = tile(s[1], s[2])
   end
   return out
end

local function make_deal(p1_concealed: {Tile}, p1_sets: {TileSet}, wall_tiles: {Tile}): DealState
   local function mk(concealed: {Tile}, sets: {TileSet}, sw: string, human: boolean): PlayerState
      return {
         hand                       = { concealed_tiles = concealed, sets = sets, discards = {} },
         opening_trim               = {},
         seat_wind                  = sw as Wind,
         is_human                   = human,
         known_wall_tile_ids        = {},
         concealed_pung_kinds_seen  = {},
         turn_extra_discards_owed   = 0,
      }
   end
   return {
      players = {
         mk(p1_concealed, p1_sets, "east",  true),
         mk({}, {}, "south", false),
         mk({}, {}, "west",  false),
         mk({}, {}, "north", false),
      },
      wall                     = { tiles = wall_tiles },
      phase                    = "awaiting_action" as DealPhase,
      current_player           = 1,
      dealer                   = 1,
      round_wind               = "east" as Wind,
      pending_discard          = { tile = tile("", ""), discarder = 0 },
      has_pending_discard      = false,
      pending_added_kong       = { tile_id = "" as TileId, tile = tile("", ""), declarer = 0 },
      has_pending_kong         = false,
      rng                      = rng_mod.from_seed(1),
      deal_result              = {
         winner_player_index = 0, won_by_zi_mo = false,
         score_result = {
            win_shape_kind = "" as WinShapeKind, reasons = {}, total_fan = 0,
            is_limit = false, rating = "" as Rating, valid_hu = false,
         },
         has_score_result = false,
      },
      has_deal_result          = false,
      reaction_passes          = {},
      pending_claims           = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = "" as TileId,
      has_last_drawn           = false,
      effect_states            = {},
      active_boons             = {},
      set_count_high_water     = 0,
      reached_ting             = false,
      declined_boons_this_deal = {},
      pending_forks            = {},
      pending_offer            = {},
      pending_offer_milestone  = "" as MilestoneId,
   }
end

local function fire_chi(deal: DealState, actives: {ActiveBoon}, kind_prefix: string, ranks: {integer})
   -- Build a chi tile_set on the given suit + ranks (e.g. "tiao", {1,2,3}).
   local set_tiles: {Tile} = {}
   for _, r in ipairs(ranks) do
      local k = kind_prefix .. "_" .. tostring(r)
      set_tiles[#set_tiles + 1] = tile(k .. "_a", k)
   end
   local tile_set: TileSet = {
      kind        = "chi" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = set_tiles,
      called_from = 4,
   }
   local ev: CallEvent = {
      event_name    = "on_chi",
      tile_set      = tile_set,
      source_player = 4,
      kong_kind     = "",
   }
   -- Reflect the chi on the deal so dominant_suit_of_hand sees it.
   deal.players[1].hand.sets[#deal.players[1].hand.sets + 1] = tile_set
   registry.emit(deal, actives, 1, ev as EventData)
end

-- A tiao-heavy hand: 9 tiao + 3 wan + 1 bing = 13 tiles, post-discard.
local function tiao_heavy_hand(): {Tile}
   return tiles({
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"tiao_9_a","tiao_9"},
      {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
      {"bing_1_a","bing_1"},
   })
end

describe("M2 boon: suit_beacon", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("takes an extra wall tile when the player completes a dominant-suit chi", function()
      local wall = tiles({{"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}})
      local deal = make_deal(tiao_heavy_hand(), {}, wall)
      local active = context.new_active("suit_beacon", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_chi(deal, deal.active_boons, "tiao", {1, 2, 3})
      assert.are.equal(1, #deal.wall.tiles)
      assert.are.equal(1, deal.players[1].turn_extra_discards_owed)
   end)

   it("does NOT trigger on a non-dominant-suit chi", function()
      local wall = tiles({{"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}})
      local deal = make_deal(tiao_heavy_hand(), {}, wall)
      local active = context.new_active("suit_beacon", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      -- Player is tiao-dominant; the wan chi is off-suit.
      fire_chi(deal, deal.active_boons, "wan", {1, 2, 3})
      assert.are.equal(2, #deal.wall.tiles)
      assert.are.equal(0, deal.players[1].turn_extra_discards_owed)
   end)

   it("re-triggers on every dominant chi (no cap)", function()
      local wall = tiles({
         {"bing_5_a","bing_5"}, {"bing_6_a","bing_6"},
         {"bing_7_a","bing_7"}, {"bing_8_a","bing_8"},
      })
      local deal = make_deal(tiao_heavy_hand(), {}, wall)
      local active = context.new_active("suit_beacon", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_chi(deal, deal.active_boons, "tiao", {1, 2, 3})
      fire_chi(deal, deal.active_boons, "tiao", {4, 5, 6})
      assert.are.equal(2, #deal.wall.tiles)
      assert.are.equal(2, deal.players[1].turn_extra_discards_owed)
   end)

   it("does not crash when wall is empty (no extra draw attempted)", function()
      local deal = make_deal(tiao_heavy_hand(), {}, {})
      local active = context.new_active("suit_beacon", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_chi(deal, deal.active_boons, "tiao", {1, 2, 3})
      assert.are.equal(0, deal.players[1].turn_extra_discards_owed)
   end)
end)
