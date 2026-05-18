-- M2-S02-T04 fork-offer flow tests: milestone events materialize an offer
-- on DealState; PickBoonOfferAction resolves it; queued forks chain
-- automatically; the player's draw is gated while an offer is pending.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
local engine   = require("game.deal_engine")
local registry = require("effects.boon_registry")
local context  = require("effects.boon_context")
local m2_boons = require("content.m2_boons")
local notation = require("support.hand_notation")

-- ── Helpers ────────────────────────────────────────────────────────────────

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

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok, "notation error: " .. r.error)
   return r.tiles
end

local function peng(kind_id: string, called_from: integer): TileSet
   return {
      kind        = "peng" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {
         tile(kind_id .. "_a", kind_id),
         tile(kind_id .. "_b", kind_id),
         tile(kind_id .. "_c", kind_id),
      },
      called_from = called_from,
   }
end

-- Construct a DealState with player 1 pre-loaded and the M2 catalog
-- registered. Wall left empty by default.
local function make_deal(
   p1_concealed: {Tile},
   p1_sets:      {TileSet},
   wall_tiles:   {Tile}
): DealState
   local function mk(concealed: {Tile}, sets: {TileSet}, sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = concealed, sets = sets, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
         concealed_pung_kinds_seen = {},
         turn_extra_discards_owed = 0,
         last_drawn_tile_id = "" as TileId,
      }
   end
   return {
      players = {
         mk(p1_concealed, p1_sets, "east",  true),
         mk({},           {},      "south", false),
         mk({},           {},      "west",  false),
         mk({},           {},      "north", false),
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
      rng                      = rng_mod.from_seed(42),
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

-- ── Tests ──────────────────────────────────────────────────────────────────

describe("fork offer materialization", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("materializes a set_1 offer after the player crosses the first set milestone", function()
      -- Player concealed: east-pung + 11 fillers + 1 discard target.
      -- After discarding wan_1, set_count_high_water crosses 0 → 1, fires
      -- on_set_formed (set_index=1), queues "set_1", and materializes an
      -- offer of 3 set_1-eligible boons.
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      local deal = make_deal(concealed, {}, {})

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal("set_1", tr.deal.pending_offer_milestone as string)
      assert.are.equal(3, #tr.deal.pending_offer)
      -- The offer pool is set_1-eligible boons from the M2 catalog. As
      -- more boons land we just verify each offered id is genuinely
      -- set_1-eligible rather than asserting a fixed id list.
      for _, id in ipairs(tr.deal.pending_offer) do
         local boon = m2_boons.find(id)
         assert.is_not_nil(boon)
         local set_1_eligible = false
         for _, m in ipairs(boon.eligible_milestones) do
            if (m as string) == "set_1" then set_1_eligible = true; break end
         end
         assert.is_true(set_1_eligible, id .. " was offered at set_1 but is not set_1-eligible")
      end
   end)

   it("does not materialize an offer when no milestone fires", function()
      -- Concealed has no decomposable set. Discard one tile → set_count
      -- stays at 0 → no fork queued.
      local concealed = tiles({
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
         {"tiao_3_a","tiao_3"}, {"bing_7_a","bing_7"},
      })
      local deal = make_deal(concealed, {}, {})

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal(0, #tr.deal.pending_offer)
      assert.are.equal(0, #tr.deal.pending_forks)
   end)
end)

describe("pick_boon_offer action", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("adds the picked boon to active_boons and clears the pending offer", function()
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      local deal = make_deal(concealed, {}, {})

      local tr_disc = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr_disc.ok, tr_disc.error)
      local pick_id = tr_disc.deal.pending_offer[1]

      local tr_pick = engine.apply_action(tr_disc.deal, engine.pick_boon_offer(1, pick_id))
      assert.is_true(tr_pick.ok, tr_pick.error)
      assert.are.equal(0, #tr_pick.deal.pending_offer)
      assert.are.equal("", tr_pick.deal.pending_offer_milestone as string)

      -- Picked boon now active; the other two are declined.
      assert.are.equal(1, #tr_pick.deal.active_boons)
      assert.are.equal(pick_id, tr_pick.deal.active_boons[1].boon_id)
      assert.are.equal("set_1", tr_pick.deal.active_boons[1].acquired_at as string)
      assert.are.equal(2, #tr_pick.deal.declined_boons_this_deal)
   end)

   it("rejects pick when boon_id is not in the current offer", function()
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      local deal = make_deal(concealed, {}, {})

      local tr_disc = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr_disc.ok, tr_disc.error)

      local tr_pick = engine.apply_action(tr_disc.deal, engine.pick_boon_offer(1, "not_in_offer"))
      assert.is_false(tr_pick.ok)
   end)

   it("rejects pick when no offer is pending", function()
      local deal = make_deal({}, {}, {})
      local tr = engine.apply_action(deal, engine.pick_boon_offer(1, "honors_eye"))
      assert.is_false(tr.ok)
   end)
end)

describe("queue chaining (set_3 + ting on same turn)", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("queues set_1+2+3+ting and chains picks until the queue drains", function()
      -- Pair-wait ting: 3 open pengs + concealed [fa_cai×3, north, X].
      -- After discarding X, set_count crosses 0→3 and ting reaches → fires
      -- set_1, set_2, set_3, then ting. pending_forks queued in that order.
      local concealed = tiles({
         {"fa_cai_a","fa_cai"}, {"fa_cai_b","fa_cai"}, {"fa_cai_c","fa_cai"},
         {"north_a","north"},
         {"wan_1_a","wan_1"},
      })
      local deal = make_deal(
         concealed,
         { peng("east", 2), peng("south", 3), peng("west", 4) },
         {}
      )

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      -- set_1 is the head offer; set_2, set_3, ting are queued behind it.
      assert.are.equal("set_1", tr.deal.pending_offer_milestone as string)
      assert.are.equal(3, #tr.deal.pending_forks)
      assert.are.equal("set_2", tr.deal.pending_forks[1] as string)
      assert.are.equal("set_3", tr.deal.pending_forks[2] as string)
      assert.are.equal("ting",  tr.deal.pending_forks[3] as string)

      -- Chain picks until the queue drains. Each pick:
      --   - resolves the current offer (one boon → active, rest → declined)
      --   - materializes the next non-empty offer (or drains the queue)
      -- Capped at 16 iterations so a regression that loops infinitely
      -- fails the test rather than hanging busted.
      local d = tr.deal
      local picks = 0
      while #d.pending_offer > 0 and picks < 16 do
         local pick_id = d.pending_offer[1]
         local tr_p = engine.apply_action(d, engine.pick_boon_offer(1, pick_id))
         assert.is_true(tr_p.ok, tr_p.error)
         d = tr_p.deal
         picks = picks + 1
      end

      -- Queue fully drained, no loose ends. Active + declined sum is the
      -- total count of catalog entries touched by the milestone forks.
      assert.are.equal(0, #d.pending_offer)
      assert.are.equal(0, #d.pending_forks)
      assert.are.equal("", d.pending_offer_milestone as string)
      assert.is_true(#d.active_boons >= 1, "at least one boon should have been picked")
      assert.is_true(picks <= 4, "no more picks than queued forks (set_1+2+3+ting)")
   end)
end)

describe("draw gating when an offer is pending", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("rejects player 1's draw while pending_offer is non-empty", function()
      local deal = make_deal({}, {}, parse("123t 456t"))
      deal.pending_offer = {"honors_eye", "cleanse", "silent_march"}
      deal.pending_offer_milestone = "set_1" as MilestoneId
      deal.phase = "awaiting_draw" as DealPhase
      deal.current_player = 1

      local tr = engine.apply_action(deal, engine.draw(1))
      assert.is_false(tr.ok)
      assert.is_truthy(tr.error:find("pending boon offer"))
   end)

   it("allows opponent draws while a player offer is pending", function()
      -- Plan §357 mandatory-pick applies to the boon owner only. Opponents
      -- continue their own turns while the player has a fork to resolve.
      local deal = make_deal({}, {}, parse("123t 456t"))
      deal.pending_offer = {"honors_eye", "cleanse", "silent_march"}
      deal.pending_offer_milestone = "set_1" as MilestoneId
      deal.phase = "awaiting_draw" as DealPhase
      deal.current_player = 2

      local tr = engine.apply_action(deal, engine.draw(2))
      assert.is_true(tr.ok, tr.error)
   end)

   it("end-to-end: discard → fork materializes → draw blocked → pick → draw allowed", function()
      -- Drives the full flow through real engine actions rather than
      -- injecting pending_offer state. Catches regressions in the chain
      -- between evaluate_milestones, materialize_next_offer, and the
      -- handle_draw gate.
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      -- Give the wall a couple of tiles so post-pick draws can succeed
      -- after the deal cycles back around to player 1.
      local wall = tiles({
         {"wan_6_a","wan_6"}, {"wan_7_a","wan_7"}, {"wan_8_a","wan_8"},
      })
      local deal = make_deal(concealed, {}, wall)

      -- Step 1: player 1 discards → set_1 milestone fires → offer materializes.
      local tr_disc = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr_disc.ok, tr_disc.error)
      assert.are.equal(3, #tr_disc.deal.pending_offer)
      assert.are.equal("set_1", tr_disc.deal.pending_offer_milestone as string)

      -- Step 2: simulate the deal cycling back to player 1 in awaiting_draw.
      -- (Skipping the full reaction-window-and-3-opponent-turns dance — those
      -- paths are exercised by deal_engine_spec; this test focuses on the
      -- gate.) Set phase + current_player as if the cycle completed.
      local d_at_draw = tr_disc.deal
      d_at_draw.phase = "awaiting_draw" as DealPhase
      d_at_draw.current_player = 1

      -- Step 3: player 1 attempts to draw — must be rejected.
      local tr_blocked = engine.apply_action(d_at_draw, engine.draw(1))
      assert.is_false(tr_blocked.ok)
      assert.is_truthy(tr_blocked.error:find("pending boon offer"))

      -- Step 4: player resolves the offer with a valid pick.
      local pick_id = d_at_draw.pending_offer[1]
      local tr_pick = engine.apply_action(d_at_draw, engine.pick_boon_offer(1, pick_id))
      assert.is_true(tr_pick.ok, tr_pick.error)
      assert.are.equal(0, #tr_pick.deal.pending_offer)
      assert.are.equal(1, #tr_pick.deal.active_boons)

      -- Step 5: the draw that was blocked before now succeeds.
      local tr_draw = engine.apply_action(tr_pick.deal, engine.draw(1))
      assert.is_true(tr_draw.ok, tr_draw.error)
   end)
end)
