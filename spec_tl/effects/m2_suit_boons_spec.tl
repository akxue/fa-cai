-- M2-S04 suit-cluster boon tests: pure_path (auto-pick dominant + opp
-- count reveal) and pure_vision (live wall dominant-suit count).
-- Both compute dominant suit independently from the player's current
-- hand at trigger time (S04 simplification — see plan §476 note).

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

local function make_deal(
   p1_concealed: {Tile}, p2_concealed: {Tile},
   p3_concealed: {Tile}, p4_concealed: {Tile},
   wall_tiles:   {Tile}
): DealState
   local function mk(concealed: {Tile}, sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = concealed, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
      }
   end
   return {
      players = {
         mk(p1_concealed, "east",  true),
         mk(p2_concealed, "south", false),
         mk(p3_concealed, "west",  false),
         mk(p4_concealed, "north", false),
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

-- Suit-string-to-counter-index encoding used by both boons. Tests
-- mirror the m2_boons.tl mapping (tiao=1, wan=2, bing=3).
local SUIT_IDX = {tiao = 1, wan = 2, bing = 3}

-- ── pure_path ─────────────────────────────────────────────────────────────

describe("M2 boon: pure_path", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("auto-picks the most-numerous suit in the player's starting hand", function()
      -- Player has 6 tiao + 4 wan + 3 bing → tiao dominant.
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"}, {"wan_4_a","wan_4"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      })
      local deal = make_deal(p1, {}, {}, {}, {})
      local active = context.new_active("pure_path", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(SUIT_IDX.tiao, active.counters["dominant_suit_idx"])
   end)

   it("breaks ties canonically (tiao > wan > bing)", function()
      -- 4 of each suit → tiao wins by canonical tiebreak.
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"}, {"tiao_4_a","tiao_4"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"}, {"wan_4_a","wan_4"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"}, {"bing_4_a","bing_4"},
         {"east_a","east"},
      })
      local deal = make_deal(p1, {}, {}, {}, {})
      local active = context.new_active("pure_path", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(SUIT_IDX.tiao, active.counters["dominant_suit_idx"])
   end)

   it("records dominant-suit counts for each opponent's starting hand", function()
      -- Player tiao-dominant; opponents have varying tiao counts.
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })
      local p2 = tiles({
         {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"wan_3_a","wan_3"},
      })
      local p3 = tiles({{"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}})
      local p4 = tiles({
         {"tiao_9_a","tiao_9"}, {"tiao_1_b","tiao_1"}, {"tiao_2_b","tiao_2"}, {"tiao_3_b","tiao_3"},
      })
      local deal = make_deal(p1, p2, p3, p4, {})
      local active = context.new_active("pure_path", "starter" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_deal_start(deal, deal.active_boons)
      assert.are.equal(2, active.counters["opp_2_count"])
      assert.are.equal(0, active.counters["opp_3_count"])
      assert.are.equal(4, active.counters["opp_4_count"])
   end)
end)

-- ── pure_vision ───────────────────────────────────────────────────────────

describe("M2 boon: pure_vision", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("records the live count of the player's dominant suit in the wall", function()
      -- Player wan-dominant. Wall has 3 wan + 1 tiao + 1 bing.
      local p1 = tiles({
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"wan_4_a","wan_4"}, {"wan_5_a","wan_5"}, {"wan_6_a","wan_6"},
         {"tiao_5_a","tiao_5"}, {"bing_5_a","bing_5"},
      })
      local wall = tiles({
         {"wan_7_a","wan_7"}, {"wan_8_a","wan_8"}, {"wan_9_a","wan_9"},
         {"tiao_6_a","tiao_6"}, {"bing_6_a","bing_6"},
      })
      local deal = make_deal(p1, {}, {}, {}, wall)
      local active = context.new_active("pure_vision", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_player_draw(deal, deal.active_boons, "wan_5")
      assert.are.equal(SUIT_IDX.wan, active.counters["dominant_suit_idx"])
      assert.are.equal(3, active.counters["wall_dominant_count"])
   end)

   it("recomputes when the wall shrinks between draws", function()
      local p1 = tiles({
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"bing_4_a","bing_4"}, {"bing_5_a","bing_5"},
      })
      local wall = tiles({
         {"bing_6_a","bing_6"}, {"bing_7_a","bing_7"}, {"tiao_1_a","tiao_1"},
      })
      local deal = make_deal(p1, {}, {}, {}, wall)
      local active = context.new_active("pure_vision", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(2, active.counters["wall_dominant_count"])

      -- Simulate a draw consuming the front bing_6 from the wall.
      table.remove(deal.wall.tiles, 1)
      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(1, active.counters["wall_dominant_count"])
   end)

   it("adapts dominant suit if the player's hand composition shifts", function()
      -- S04 simplification (plan §476 note): dominant is computed from
      -- the player's CURRENT hand each time, not latched at acquisition.
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })
      local wall = tiles({{"tiao_9_a","tiao_9"}, {"wan_9_a","wan_9"}})
      local deal = make_deal(p1, {}, {}, {}, wall)
      local active = context.new_active("pure_vision", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(SUIT_IDX.tiao, active.counters["dominant_suit_idx"])

      -- Mutate p1's hand to be wan-heavy; the next draw should re-pick.
      deal.players[1].hand.concealed_tiles = tiles({
         {"wan_1_b","wan_1"}, {"wan_2_b","wan_2"}, {"wan_3_b","wan_3"},
         {"wan_4_b","wan_4"}, {"wan_5_b","wan_5"},
         {"tiao_1_b","tiao_1"},
      })
      fire_player_draw(deal, deal.active_boons, "any")
      assert.are.equal(SUIT_IDX.wan, active.counters["dominant_suit_idx"])
   end)
end)
