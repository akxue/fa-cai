-- M2-S01 milestone fork tests: set-count detection and engine-level emission
-- of on_set_formed / on_ting_reached. Builds on the M2-S00 dispatcher.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local registry   = require("effects.boon_registry")
local context    = require("effects.boon_context")
local milestones = require("game.milestone_detection")
local notation   = require("support.hand_notation")

-- ── Helpers ────────────────────────────────────────────────────────────────

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok, "notation error: " .. r.error)
   return r.tiles
end

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

-- Build a DealState with player 1's hand pre-loaded for a specific scenario.
-- p1_concealed should contain the post-draw 14-tile hand (or sets+concealed
-- summing to 14). The deal starts in awaiting_action so the player discards
-- next and triggers milestone evaluation.
local function make_deal_for_p1(
   p1_concealed: {Tile},
   p1_sets:      {TileSet},
   p1_discards:  {Tile},
   wall_tiles:   {Tile}
): DealState
   local function mk_player(concealed: {Tile}, open_sets: {TileSet}, discards: {Tile}, sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = concealed, sets = open_sets, discards = discards },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
         concealed_pung_kinds_seen = {},
      }
   end
   return {
      players = {
         mk_player(p1_concealed, p1_sets,  p1_discards or {}, "east",  true),
         mk_player({},           {},       {}, "south", false),
         mk_player({},           {},       {}, "west",  false),
         mk_player({},           {},       {}, "north", false),
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

-- ── milestone_detection unit tests ────────────────────────────────────────

describe("milestone_detection.max_concealed_sets", function()
   it("returns 0 on an empty hand", function()
      assert.are.equal(0, milestones.max_concealed_sets({}))
   end)

   it("counts a single peng", function()
      local hand = tiles({{"east_a","east"}, {"east_b","east"}, {"east_c","east"}})
      assert.are.equal(1, milestones.max_concealed_sets(hand))
   end)

   it("counts a single chi", function()
      local hand = tiles({{"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"}})
      assert.are.equal(1, milestones.max_concealed_sets(hand))
   end)

   it("counts two disjoint pungs", function()
      local hand = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"south_b","south"}, {"south_c","south"},
      })
      assert.are.equal(2, milestones.max_concealed_sets(hand))
   end)

   it("prefers higher set count over lower decompositions", function()
      -- 1-2-3-3-3 could be (chi 1-2-3 + leftover 3-3) or (pung 3-3-3 + leftover 1-2).
      -- Both yield 1 set, but the algorithm should not get stuck at 0.
      local hand = parse("12333t")
      assert.are.equal(1, milestones.max_concealed_sets(hand))
   end)

   it("counts maximum chis when sequential tiles overlap", function()
      -- 1-2-3-4-5-6 → 2 chis (1-2-3 + 4-5-6)
      local hand = parse("123456t")
      assert.are.equal(2, milestones.max_concealed_sets(hand))
   end)

   it("ignores leftover pairs and singletons", function()
      -- pung + pair + singleton = 1 set + extras
      local hand = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"south_b","south"},
         {"north_a","north"},
      })
      assert.are.equal(1, milestones.max_concealed_sets(hand))
   end)

   it("does not form chi from honor tiles", function()
      local hand = tiles({{"east_a","east"}, {"south_a","south"}, {"west_a","west"}})
      assert.are.equal(0, milestones.max_concealed_sets(hand))
   end)
end)

describe("milestone_detection.total_set_count", function()
   it("sums open sets and concealed sets", function()
      local hand: PlayerHand = {
         concealed_tiles = tiles({
            {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         }),
         sets = { peng("south", 2), peng("west", 3) },
         discards = {},
      }
      assert.are.equal(3, milestones.total_set_count(hand))
   end)

   it("returns just #sets when concealed has no decomposable sets", function()
      local hand: PlayerHand = {
         concealed_tiles = tiles({{"north_a","north"}, {"tiao_5_a","tiao_5"}}),
         sets = { peng("east", 2) },
         discards = {},
      }
      assert.are.equal(1, milestones.total_set_count(hand))
   end)
end)

-- ── Engine emission tests ─────────────────────────────────────────────────

-- Helper: register a single boon that records every event of the given names
-- into an order-preserving list. Returns (active, observed).
local function record_events(boon_id: string, watched: {string}): ActiveBoon, {string}
   local observed: {string} = {}
   local b: Boon = {
      id = boon_id, cluster = "honor", name = boon_id,
      description = "", eligible_milestones = {"starter"},
      effect_kind = "info", weight = 1.0,
      listens = watched,
      condition = function(_c: BoonContext, _e: EventData): boolean return true end,
      effect    = function(_c: BoonContext, ev: EventData)
         observed[#observed + 1] = ev.event_name as string
      end,
   }
   registry.register(b)
   return context.new_active(boon_id, "starter" as AcquisitionPoint), observed
end

describe("milestone fork emission", function()
   before_each(function()
      registry.reset()
   end)

   it("fires on_set_formed once when player crosses set_1 via concealed pung", function()
      local active, observed = record_events("set_watcher", {"on_set_formed", "on_ting_reached"})

      -- Player 1: concealed = east-pung + 10 random singletons + 1 extra to discard.
      -- After discarding the extra, max_concealed_sets = 1 → fires on_set_formed(1).
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},  -- 14 total (post-draw)
      })
      local deal = make_deal_for_p1(concealed, {}, {}, {})
      deal.active_boons[#deal.active_boons + 1] = active

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({"on_set_formed"}, observed)
      assert.are.equal(1, tr.deal.set_count_high_water)
      assert.is_false(tr.deal.reached_ting)
   end)

   it("counts called open sets toward milestones", function()
      local active, observed = record_events("set_watcher", {"on_set_formed", "on_ting_reached"})

      -- Player 1 has 1 open peng. Concealed = 10 singletons + 1 extra to discard.
      -- After discard: total = 1 (open peng) + 0 (concealed) = 1 → set_1 fires.
      local concealed = tiles({
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      local deal = make_deal_for_p1(concealed, { peng("east", 4) }, {}, {})
      deal.active_boons[#deal.active_boons + 1] = active

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({"on_set_formed"}, observed)
      assert.are.equal(1, tr.deal.set_count_high_water)
   end)

   it("does not re-fire set_1 when high_water already at current count", function()
      local active, observed = record_events("set_watcher", {"on_set_formed", "on_ting_reached"})

      -- Player has high_water=1 (fired set_1 previously) and still holds a
      -- single pung. End-of-turn evaluation sees set_count == high_water → no
      -- event.
      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      local deal = make_deal_for_p1(concealed, {}, {}, {})
      deal.set_count_high_water = 1  -- already fired set_1 in a prior turn
      deal.active_boons[#deal.active_boons + 1] = active

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({}, observed)  -- no re-fire
      assert.are.equal(1, tr.deal.set_count_high_water)
   end)

   it("does not re-fire set_1 when the pung breaks and a new one forms across turns", function()
      -- Plan §326: if max-sets drops below a threshold and later crosses it
      -- again, the fork does NOT re-trigger. Drive two consecutive discards
      -- through engine.apply_action — first leaves the deal with one pung
      -- intact, second breaks it and reforms a different pung. Watcher must
      -- see exactly one on_set_formed.
      local active, observed = record_events("set_watcher", {"on_set_formed", "on_ting_reached"})

      -- Turn A: concealed has east-pung intact + filler + 1 discard target.
      -- After discard, max_sets = 1 → fires set_1.
      local concealed_a = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"south_b","south"},
         {"west_a","west"},  {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"wan_1_a","wan_1"},  -- discard target
      })
      local deal = make_deal_for_p1(concealed_a, {}, {}, {})
      deal.active_boons[#deal.active_boons + 1] = active

      local tr_a = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr_a.ok, tr_a.error)
      assert.are.same({"on_set_formed"}, observed)
      assert.are.equal(1, tr_a.deal.set_count_high_water)

      -- Turn B: break the east-pung by replacing the hand with a south-pung
      -- only (no east-pung). The set_count is 1 again but high_water stayed
      -- at 1; no new event should fire even though the "current" set differs.
      -- We script this by manually mutating the deal between turns (the
      -- engine doesn't model drawing a tile that splits a pung; this is the
      -- minimum scaffolding for the invariant test).
      tr_a.deal.players[1].hand.concealed_tiles = tiles({
         {"south_a","south"}, {"south_b","south"}, {"south_c","south"},
         {"west_a","west"},  {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_3_a","wan_3"},
         {"wan_4_a","wan_4"},  -- new discard target
      })
      tr_a.deal.phase = "awaiting_action" as DealPhase
      tr_a.deal.current_player = 1

      local tr_b = engine.apply_action(tr_a.deal, engine.discard(1, "wan_4_a" as TileId))
      assert.is_true(tr_b.ok, tr_b.error)
      assert.are.same({"on_set_formed"}, observed)  -- still exactly one
      assert.are.equal(1, tr_b.deal.set_count_high_water)
   end)

   it("fires set_1, set_2, set_3, then on_ting_reached in order for pair-wait ting", function()
      local active, observed = record_events("milestone_watcher", {"on_set_formed", "on_ting_reached"})

      -- Player has 3 open pengs. Concealed = [fa_cai*3, north, X].
      -- After discarding X, concealed = [fa_cai*3, north]:
      --   max_concealed_sets = 1, total = 3 (open) + 1 = 4 → fires set_1, set_2, set_3.
      --   ting_distance for ([fa_cai*3, north] + 3 open sets) = -1 → fires on_ting_reached.
      local concealed = tiles({
         {"fa_cai_a","fa_cai"}, {"fa_cai_b","fa_cai"}, {"fa_cai_c","fa_cai"},
         {"north_a","north"},
         {"wan_1_a","wan_1"},  -- the discard target
      })
      local deal = make_deal_for_p1(
         concealed,
         { peng("east", 2), peng("south", 3), peng("west", 4) },
         {},
         {}
      )
      deal.active_boons[#deal.active_boons + 1] = active

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({"on_set_formed", "on_set_formed", "on_set_formed", "on_ting_reached"}, observed)
      assert.are.equal(4, tr.deal.set_count_high_water)
      assert.is_true(tr.deal.reached_ting)
   end)

   it("does not fire milestones for opponent discards", function()
      local _active, observed = record_events("milestone_watcher", {"on_set_formed", "on_ting_reached"})

      -- Put player 2 in an awaiting_action state with a 14-tile hand that would
      -- cross set_1 if it were player 1. Player 1 has no boons fire.
      local p2_concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"bing_5_a","bing_5"},
         {"tiao_9_a","tiao_9"}, {"wan_1_a","wan_1"},
      })
      -- Build a deal whose current_player is 2 with the above hand.
      local deal = make_deal_for_p1({}, {}, {}, {})
      deal.players[2].hand.concealed_tiles = p2_concealed
      deal.current_player = 2
      deal.active_boons[#deal.active_boons + 1] =
         context.new_active("milestone_watcher", "starter" as AcquisitionPoint)

      local tr = engine.apply_action(deal, engine.discard(2, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({}, observed)
      assert.are.equal(0, tr.deal.set_count_high_water)
   end)

   it("fires set_2 only when crossing from 1→2 without re-firing set_1", function()
      local active, observed = record_events("milestone_watcher", {"on_set_formed", "on_ting_reached"})

      local concealed = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},
         {"south_a","south"}, {"south_b","south"}, {"south_c","south"},
         {"west_a","west"}, {"north_a","north"},
         {"fa_cai_a","fa_cai"}, {"hong_zhong_a","hong_zhong"}, {"bai_ban_a","bai_ban"},
         {"tiao_5_a","tiao_5"}, {"wan_5_a","wan_5"}, {"wan_1_a","wan_1"},  -- 14 total
      })
      local deal = make_deal_for_p1(concealed, {}, {}, {})
      deal.set_count_high_water = 1  -- set_1 already fired in a prior turn
      deal.active_boons[#deal.active_boons + 1] = active

      local tr = engine.apply_action(deal, engine.discard(1, "wan_1_a" as TileId))
      assert.is_true(tr.ok, tr.error)
      assert.are.same({"on_set_formed"}, observed)
      assert.are.equal(2, tr.deal.set_count_high_water)
   end)
end)
