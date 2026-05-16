-- M2-S04 Plan B: extra_draw primitive + matched-discard turn extension.
-- Verifies the extra_draw primitive records an obligation on PlayerState
-- and that apply_all_pass holds the player's turn open until owed
-- discards are paid (per P8, MILESTONE-2-PLAN.md:417).
--
-- Drives the engine through engine.apply_action where possible so the
-- turn-state machine is exercised end-to-end; primitive-only tests use
-- a hand-built BoonContext.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local primitives = require("effects.boon_primitives")
local context    = require("effects.boon_context")
local registry   = require("effects.boon_registry")

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
         turn_extra_discards_owed = 0,
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

-- ── extra_draw primitive: increments turn_extra_discards_owed ─────────────

describe("boon_primitives.extra_draw", function()
   it("appends a wall tile to concealed AND increments turn_extra_discards_owed", function()
      local deal = make_deal({}, tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}}))
      local active = context.new_active("any", "starter" as AcquisitionPoint)
      local ctx = context.make(deal, active, 1)

      local before = deal.players[1].turn_extra_discards_owed
      local drawn = primitives.extra_draw(ctx)
      assert.are.equal("wan_1_a", drawn.tile_id as string)
      assert.are.equal(1, #deal.players[1].hand.concealed_tiles)
      assert.are.equal(before + 1, deal.players[1].turn_extra_discards_owed)
   end)

   it("stacks owed across repeated extra_draws", function()
      local deal = make_deal({}, tiles({
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
      }))
      local active = context.new_active("any", "starter" as AcquisitionPoint)
      local ctx = context.make(deal, active, 1)
      primitives.extra_draw(ctx)
      primitives.extra_draw(ctx)
      assert.are.equal(2, deal.players[1].turn_extra_discards_owed)
      assert.are.equal(2, #deal.players[1].hand.concealed_tiles)
   end)
end)

-- ── Engine integration: apply_all_pass honors owed > 0 ────────────────────

-- Helper: 14 concealed + N extra (post-extra_draw state). Need at least 1
-- non-pung tile to discard. Build 15-tile hand for 1 owed, 16 for 2 owed.
local function p1_hand_for_owed(extra: integer): {Tile}
   local hand = tiles({
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"tiao_9_a","tiao_9"},
      {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
   })
   local extras = {"wan_3","wan_4","wan_5"}
   for i = 1, extra do
      hand[#hand + 1] = tile("wan_" .. tostring(i + 2) .. "_x", extras[i])
   end
   return hand
end

describe("engine: owed extra-discard loop", function()
   it("after the player's first discard with owed=1, current_player stays at 1 and phase returns to awaiting_action", function()
      local deal = make_deal(p1_hand_for_owed(1), {})  -- 15 tiles, owed=1
      deal.players[1].turn_extra_discards_owed = 1

      local r1 = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(r1.ok, r1.error)
      -- All three opponents pass.
      local d = r1.deal
      for i = 2, 4 do
         local tr = engine.apply_action(d, engine.pass_reaction(i))
         assert.is_true(tr.ok, tr.error)
         d = tr.deal
      end
      -- After all passes, the player should still be on turn with awaiting_action
      -- and one fewer discard owed.
      assert.are.equal(1, d.current_player)
      assert.are.equal("awaiting_action", d.phase as string)
      assert.are.equal(0, d.players[1].turn_extra_discards_owed)
   end)

   it("after the bonus discard resolves, the turn passes normally to seat 2", function()
      local deal = make_deal(p1_hand_for_owed(1), {})
      deal.players[1].turn_extra_discards_owed = 1

      -- First discard (the originally-owed bonus discard).
      local r1 = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(r1.ok, r1.error)
      local d = r1.deal
      for i = 2, 4 do
         local tr = engine.apply_action(d, engine.pass_reaction(i))
         assert.is_true(tr.ok, tr.error)
         d = tr.deal
      end
      -- Second discard (the normal turn-ending discard). Hand has 14 tiles
      -- now (15 - 1 = 14). Discard one.
      assert.are.equal(14, #d.players[1].hand.concealed_tiles)
      local r2 = engine.apply_action(d, engine.discard(1, "wan_2_a" as TileId))
      assert.is_true(r2.ok, r2.error)
      d = r2.deal
      for i = 2, 4 do
         local tr = engine.apply_action(d, engine.pass_reaction(i))
         assert.is_true(tr.ok, tr.error)
         d = tr.deal
      end
      -- Now the turn should have advanced to seat 2.
      assert.are.equal(2, d.current_player)
      assert.are.equal("awaiting_draw", d.phase as string)
      assert.are.equal(0, d.players[1].turn_extra_discards_owed)
   end)

   it("two stacked extra_draws produce two owed discards before turn passes", function()
      local deal = make_deal(p1_hand_for_owed(2), {})  -- 16 tiles, owed=2
      deal.players[1].turn_extra_discards_owed = 2

      -- Discard 1 of 3 (1 owed + 1 normal). After this, owed should drop to 1.
      local d = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId)).deal
      for i = 2, 4 do d = engine.apply_action(d, engine.pass_reaction(i)).deal end
      assert.are.equal(1, d.current_player)
      assert.are.equal(1, d.players[1].turn_extra_discards_owed)

      -- Discard 2 of 3.
      d = engine.apply_action(d, engine.discard(1, "wan_2_a" as TileId)).deal
      for i = 2, 4 do d = engine.apply_action(d, engine.pass_reaction(i)).deal end
      assert.are.equal(1, d.current_player)
      assert.are.equal(0, d.players[1].turn_extra_discards_owed)

      -- Discard 3 of 3 (normal). Turn should now advance.
      d = engine.apply_action(d, engine.discard(1, "wan_3_x" as TileId)).deal
      for i = 2, 4 do d = engine.apply_action(d, engine.pass_reaction(i)).deal end
      assert.are.equal(2, d.current_player)
   end)
end)

-- ── Turn-start reset: stale owed does not persist across turns ────────────

describe("engine: turn_extra_discards_owed resets at turn start", function()
   it("handle_draw resets the counter when the player begins a new turn", function()
      -- Manually plant a stale owed on the player, then drive a fresh draw
      -- by setting phase = awaiting_draw and current = 1. handle_draw should
      -- reset the field before the draw fires.
      local deal = make_deal({}, tiles({{"wan_1_a","wan_1"}}))
      deal.phase = "awaiting_draw" as DealPhase
      deal.players[1].turn_extra_discards_owed = 5   -- stale

      local r = engine.apply_action(deal, engine.draw(1))
      assert.is_true(r.ok, r.error)
      assert.are.equal(0, r.deal.players[1].turn_extra_discards_owed)
   end)
end)
