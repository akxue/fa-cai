-- M2-S04 Hidden Strength + on_concealed_pung_formed engine emission tests.
-- Covers the boon's peek-3 effect (driven via direct registry.emit) and the
-- engine's end-of-turn detection path (driven via engine.apply_action). The
-- engine's per-kind-once guard lives on PlayerState.concealed_pung_kinds_seen
-- — a broken-and-reformed pung does NOT re-trigger.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
local engine   = require("game.deal_engine")
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
         hand                = { concealed_tiles = concealed, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
         concealed_pung_kinds_seen = {},
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

-- 14-tile hand: pung of east + 11 distinct tiao/bing/wan + 1 extra to discard.
-- Designed so a discard of the "extra" leaves a clean pung-of-east in hand.
local function p1_with_east_pung_plus_discard(): {Tile}
   return tiles({
      {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      {"wan_1_a","wan_1"},
      {"wan_9_a","wan_9"},   -- the "extra" discardable tile
   })
end

-- Helper: register a recording boon listening for on_concealed_pung_formed and
-- return (active, observed-kind-ids). The boon does no other work.
local function record_pung_events(): ActiveBoon, {string}
   local observed: {string} = {}
   local b: Boon = {
      id = "pung_watcher", cluster = "concealed", name = "watcher",
      description = "", eligible_milestones = {"starter"},
      effect_kind = "info", weight = 1.0,
      listens = {"on_concealed_pung_formed"},
      condition = function(_c: BoonContext, _e: EventData): boolean return true end,
      effect    = function(_c: BoonContext, ev: EventData)
         local cp = ev as ConcealedPungFormedEvent
         observed[#observed + 1] = cp.kind_id as string
      end,
   }
   registry.register(b)
   return context.new_active("pung_watcher", "starter" as AcquisitionPoint), observed
end

-- ── Boon-side: hidden_strength peeks 3 wall tiles on event ────────────────

describe("M2 boon: hidden_strength", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("peeks 3 wall tiles when on_concealed_pung_formed fires", function()
      local wall = tiles({
         {"bing_4_a","bing_4"}, {"bing_5_a","bing_5"}, {"bing_6_a","bing_6"},
         {"bing_7_a","bing_7"}, {"bing_8_a","bing_8"},
      })
      local deal = make_deal({}, wall)
      local active = context.new_active("hidden_strength", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: ConcealedPungFormedEvent = {
         event_name = "on_concealed_pung_formed",
         kind_id    = "east" as TileKindId,
         tiles      = tiles({{"east_a","east"}, {"east_b","east"}, {"east_c","east"}}),
      }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)

      assert.are.equal(3, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("bing_4_a", deal.players[1].known_wall_tile_ids[1] as string)
      assert.are.equal("bing_5_a", deal.players[1].known_wall_tile_ids[2] as string)
      assert.are.equal("bing_6_a", deal.players[1].known_wall_tile_ids[3] as string)
   end)
end)

-- ── Engine-side: emission, dedup, multi-kind, break-reform guard ──────────

describe("engine: on_concealed_pung_formed emission", function()
   before_each(function()
      registry.reset()
   end)

   it("fires once when the player's discard leaves a concealed pung in hand", function()
      local active, observed = record_pung_events()
      local deal = make_deal(p1_with_east_pung_plus_discard(), {})
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r.ok, r.error)
      assert.are.same({"east"}, observed)
      assert.are.equal(1, #r.deal.players[1].concealed_pung_kinds_seen)
   end)

   it("does not re-fire for the same kind on a later player discard", function()
      local active, observed = record_pung_events()
      local deal = make_deal(p1_with_east_pung_plus_discard(), {})
      deal.active_boons[#deal.active_boons + 1] = active

      local r1 = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r1.ok, r1.error)
      assert.are.same({"east"}, observed)

      -- Manually reset to another awaiting_action turn for p1 with the same
      -- pung still in hand plus a fresh non-pung tile to discard.
      local d2 = r1.deal
      d2.phase = "awaiting_action" as DealPhase
      d2.current_player = 1
      d2.has_pending_discard = false
      d2.reaction_passes = {}
      d2.pending_claims = {}
      d2.players[1].hand.concealed_tiles = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })

      local r2 = engine.apply_action(d2, engine.discard(1, "wan_2_a" as TileId))
      assert.is_true(r2.ok, r2.error)
      -- Still only the original "east" event observed.
      assert.are.same({"east"}, observed)
   end)

   it("does not re-fire after the pung is broken and later reformed", function()
      local active, observed = record_pung_events()
      local deal = make_deal(p1_with_east_pung_plus_discard(), {})
      deal.active_boons[#deal.active_boons + 1] = active

      -- Initial discard: pung in hand → event fires for east.
      local r1 = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r1.ok, r1.error)
      assert.are.same({"east"}, observed)

      -- Second discard: drop one east → pung broken.
      local d2 = r1.deal
      d2.phase = "awaiting_action" as DealPhase
      d2.current_player = 1
      d2.has_pending_discard = false
      d2.reaction_passes = {}
      d2.pending_claims = {}
      d2.players[1].hand.concealed_tiles = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })
      local r2 = engine.apply_action(d2, engine.discard(1, "east_c" as TileId))
      assert.is_true(r2.ok, r2.error)
      assert.are.same({"east"}, observed)

      -- Third discard: pung reformed (3 easts present again) — must NOT
      -- re-trigger.
      local d3 = r2.deal
      d3.phase = "awaiting_action" as DealPhase
      d3.current_player = 1
      d3.has_pending_discard = false
      d3.reaction_passes = {}
      d3.pending_claims = {}
      d3.players[1].hand.concealed_tiles = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_d","east"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })
      local r3 = engine.apply_action(d3, engine.discard(1, "wan_2_a" as TileId))
      assert.is_true(r3.ok, r3.error)
      assert.are.same({"east"}, observed)
   end)

   it("fires once per distinct kind when multiple pungs are present", function()
      local active, observed = record_pung_events()
      -- 14-tile hand with both an east pung AND a tiao_5 pung, plus a
      -- discardable extra.
      local p1 = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"tiao_5_a","tiao_5"}, {"tiao_5_b","tiao_5"}, {"tiao_5_c","tiao_5"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_1_a","wan_1"}, {"wan_9_a","wan_9"},
      })
      local deal = make_deal(p1, {})
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r.ok, r.error)
      assert.are.equal(2, #observed)
      -- Order is map-iteration-dependent; check membership.
      local saw_east, saw_tiao = false, false
      for _, k in ipairs(observed) do
         if k == "east"   then saw_east = true end
         if k == "tiao_5" then saw_tiao = true end
      end
      assert.is_true(saw_east)
      assert.is_true(saw_tiao)
   end)
end)
