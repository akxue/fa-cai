-- M2-S04 boon effect tests. One describe block per boon as effect logic
-- is converted from noop_effect. Run boons through the real engine
-- (engine.new_deal_with_run + engine.apply_action) so emission, dispatch,
-- and primitive interaction are all exercised end-to-end.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
local engine   = require("game.deal_engine")
local registry = require("effects.boon_registry")
local context  = require("effects.boon_context")
local m2_boons = require("content.m2_boons")
local run_state = require("game.run_state")

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

-- A 4-player deal scaffold with a controllable wall. Player 1's hand is
-- pre-loaded; phase = awaiting_draw so the first apply_action(draw, 1)
-- pulls deterministically from the front.
local function make_deal_with_wall(p1_hand: {Tile}, wall_tiles: {Tile}): DealState
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
         mk(p1_hand, "east",  true),
         mk({},      "south", false),
         mk({},      "west",  false),
         mk({},      "north", false),
      },
      wall                     = { tiles = wall_tiles },
      phase                    = "awaiting_draw" as DealPhase,
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

describe("M2 boon: honors_eye", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("appends the next wall tile to known_wall on an honor draw", function()
      -- Wall front: honor first (will be drawn), then a tiao to peek.
      local wall = tiles({{"east_a","east"}, {"tiao_5_a","tiao_5"}})
      local deal = make_deal_with_wall({}, wall)
      deal.active_boons[#deal.active_boons + 1] = context.new_active("honors_eye", "set_1" as AcquisitionPoint)

      local tr = engine.apply_action(deal, engine.draw(1))
      assert.is_true(tr.ok, tr.error)
      -- Drawn tile is now in the hand; peeked tile is the new wall front.
      assert.are.equal(1, #tr.deal.players[1].known_wall_tile_ids)
      assert.are.equal("tiao_5_a", tr.deal.players[1].known_wall_tile_ids[1] as string)
   end)

   it("does not append when the drawn tile is not an honor", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"wan_3_a","wan_3"}})
      local deal = make_deal_with_wall({}, wall)
      deal.active_boons[#deal.active_boons + 1] = context.new_active("honors_eye", "set_1" as AcquisitionPoint)

      local tr = engine.apply_action(deal, engine.draw(1))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal(0, #tr.deal.players[1].known_wall_tile_ids)
   end)

   it("does not duplicate peeked ids on repeated honor draws of the same wall front", function()
      -- Simulate two honor draws firing the boon back-to-back against the
      -- same wall front (no wall consumption between the two events).
      -- The boon must dedupe so the known-wall view doesn't fill with
      -- copies of the same tile id.
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"wan_3_a","wan_3"}})
      local deal = make_deal_with_wall({}, wall)
      local active = context.new_active("honors_eye", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: TilePropertyEvent = { event_name = "on_honor_drawn", tile = tile("east_a","east") }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)
      registry.emit(deal, deal.active_boons, 1, ev as EventData)

      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("tiao_5_a", deal.players[1].known_wall_tile_ids[1] as string)
   end)
end)

describe("M2 boon: hidden_path", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 mulligan + 1 peek token at deal start when held as run-scoped", function()
      local rs = run_state.new_run(rng_mod.from_seed(42))
      rs.active_boons[#rs.active_boons + 1] = context.new_active("hidden_path", "starter" as AcquisitionPoint)

      local deal = engine.new_deal_with_run(rng_mod.from_seed(42), rs)
      local active = deal.active_boons[1]
      assert.are.equal("hidden_path", active.boon_id)
      assert.are.equal(1, active.tokens["mulligan"])
      assert.are.equal(1, active.tokens["peek"])
   end)

   it("grants tokens exactly once per deal_start fire", function()
      -- Manually emit on_deal_start twice; expect tokens to accumulate
      -- (the boon does not gate on first-fire). This documents the
      -- "fires every time on_deal_start emits" contract.
      local rs = run_state.new_run(rng_mod.from_seed(99))
      rs.active_boons[#rs.active_boons + 1] = context.new_active("hidden_path", "starter" as AcquisitionPoint)
      local deal = engine.new_deal_with_run(rng_mod.from_seed(99), rs)

      local ev_start: DealLifecycleEvent = { event_name = "on_deal_start" }
      registry.emit(deal, deal.active_boons, 1, ev_start as EventData)

      local active = deal.active_boons[1]
      assert.are.equal(2, active.tokens["mulligan"])
      assert.are.equal(2, active.tokens["peek"])
   end)
end)
