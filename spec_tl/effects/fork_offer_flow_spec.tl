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
      -- All 3 set_1-eligible M2 boons should be in the offer (cleanse,
      -- honors_eye, silent_march). With only 3 eligible, the offer is the
      -- full pool regardless of RNG.
      local seen: {string: boolean} = {}
      for _, id in ipairs(tr.deal.pending_offer) do seen[id] = true end
      assert.is_true(seen["honors_eye"])
      assert.is_true(seen["cleanse"])
      assert.is_true(seen["silent_march"])
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

   it("queues set_1+2+3+ting and chains through resolution, skipping empty pools", function()
      -- Pair-wait ting: 3 open pengs + concealed [fa_cai×3, north, X].
      -- After discarding X, set_count crosses 0→3 and ting reaches → fires
      -- set_1, set_2, set_3, then ting. pending_forks queued in that order;
      -- pending_offer = the materialized head (set_1).
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
      assert.are.equal(3, #tr.deal.pending_offer)
      assert.are.equal(3, #tr.deal.pending_forks)  -- set_2, set_3, ting
      assert.are.equal("set_2", tr.deal.pending_forks[1] as string)
      assert.are.equal("set_3", tr.deal.pending_forks[2] as string)
      assert.are.equal("ting",  tr.deal.pending_forks[3] as string)

      -- Resolve set_1. The S02 catalog has only set_1 + 2-flex eligible
      -- boons; once set_1 fires, the picked boon goes to active_boons and
      -- the other 2 to declined. set_2's eligible pool (cleanse +
      -- silent_march, both flex) overlaps the declined set, so set_2's
      -- offer is empty. set_3 and ting have no S02-catalog boons either.
      -- Engine should skip all empty forks and drain the queue cleanly.
      local pick1 = tr.deal.pending_offer[1]
      local tr_p1 = engine.apply_action(tr.deal, engine.pick_boon_offer(1, pick1))
      assert.is_true(tr_p1.ok, tr_p1.error)

      -- Queue fully drained without leaving the player stuck.
      assert.are.equal(0, #tr_p1.deal.pending_offer)
      assert.are.equal(0, #tr_p1.deal.pending_forks)
      assert.are.equal("", tr_p1.deal.pending_offer_milestone as string)

      -- Final state: 1 active boon, 2 declined, no fork loose ends.
      assert.are.equal(1, #tr_p1.deal.active_boons)
      assert.are.equal(2, #tr_p1.deal.declined_boons_this_deal)
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
end)
