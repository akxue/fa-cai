-- M2-S04 honors_gift: auto-picks the player's most-numerous honor at
-- deal start, then recomputes the wall's live count of that marked
-- honor on every on_player_draw. Mirrors the pure_path / pure_vision
-- pattern in the suit cluster.

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

local function make_deal(p1_concealed: {Tile}, wall_tiles: {Tile}): DealState
   local function mk(concealed: {Tile}, sw: string, human: boolean): PlayerState
      return {
         hand                       = { concealed_tiles = concealed, sets = {}, discards = {} },
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
         mk(p1_concealed, "east",  true),
         mk({},           "south", false),
         mk({},           "west",  false),
         mk({},           "north", false),
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

local function fire_deal_start(deal: DealState, actives: {ActiveBoon})
   local ev: DealLifecycleEvent = { event_name = "on_deal_start" }
   registry.emit(deal, actives, 1, ev as EventData)
end

local function fire_player_draw(deal: DealState, actives: {ActiveBoon}, kind: string)
   local ev: PlayerDrawEvent = {
      event_name = "on_player_draw",
      tile       = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

-- Canonical honor order (mirrors m2_boons.tl HONOR_ORDER for assertions).
local HONOR_IDX = {
   east = 1, south = 2, west = 3, north = 4,
   fa_cai = 5, hong_zhong = 6, bai_ban = 7,
}

describe("M2 boon: honors_gift", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("auto-picks the most-numerous honor in the starting hand", function()
      -- 3 fa_cai + 2 east + 1 south = fa_cai dominant.
      local p1 = tiles({
         {"fa_cai_a","fa_cai"}, {"fa_cai_b","fa_cai"}, {"fa_cai_c","fa_cai"},
         {"east_a","east"}, {"east_b","east"}, {"south_a","south"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_5_a","wan_5"},
      })
      local deal = make_deal(p1, {})
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(HONOR_IDX.fa_cai, active.counters["marked_honor_idx"])
   end)

   it("breaks ties canonically (east > south > west > north > dragons)", function()
      -- One copy of every honor → 7 1-counts. Canonical winner: east.
      local p1 = tiles({
         {"east_a","east"}, {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      })
      local deal = make_deal(p1, {})
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(HONOR_IDX.east, active.counters["marked_honor_idx"])
   end)

   it("stores 0 when the starting hand has no honors", function()
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"bing_4_a","bing_4"},
      })
      local deal = make_deal(p1, {})
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(0, active.counters["marked_honor_idx"])
   end)

   it("snapshots initial wall count of marked honor at deal_start", function()
      -- Player has 1 east → marked east. Wall has 3 east tiles.
      local p1 = tiles({
         {"east_a","east"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      })
      local wall = tiles({
         {"east_b","east"}, {"east_c","east"}, {"east_d","east"},
         {"south_a","south"}, {"tiao_9_a","tiao_9"},
      })
      local deal = make_deal(p1, wall)
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(HONOR_IDX.east, active.counters["marked_honor_idx"])
      assert.are.equal(3, active.counters["wall_marked_count"])
   end)

   it("recomputes wall_marked_count on every on_player_draw", function()
      local p1 = tiles({
         {"south_a","south"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      })
      local wall = tiles({
         {"south_b","south"}, {"south_c","south"},
         {"north_a","north"},
      })
      local deal = make_deal(p1, wall)
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(2, active.counters["wall_marked_count"])

      -- Simulate the wall consuming the front south.
      table.remove(deal.wall.tiles, 1)
      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(1, active.counters["wall_marked_count"])

      -- And consuming the second south.
      table.remove(deal.wall.tiles, 1)
      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(0, active.counters["wall_marked_count"])
   end)

   it("no-ops on on_player_draw when marked honor index is 0", function()
      -- All-suit starting hand → marked_honor_idx == 0. Subsequent draws
      -- must NOT pick up a kind from the draw event tile (the boon is
      -- latched at deal_start).
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"bing_4_a","bing_4"},
      })
      local wall = tiles({{"east_a","east"}, {"east_b","east"}})
      local deal = make_deal(p1, wall)
      local active = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      fire_player_draw(deal, deal.active_boons, "east")
      assert.are.equal(0, active.counters["marked_honor_idx"])
      -- wall_marked_count was never set (no marked honor to count).
      assert.is_nil(active.counters["wall_marked_count"])
   end)
end)
