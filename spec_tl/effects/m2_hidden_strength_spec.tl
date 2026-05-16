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
      -- Engine sorts eligible kinds before emission, so the order is stable
      -- across runs. Sort: "east" < "tiao_5" lexicographically.
      assert.are.same({"east", "tiao_5"}, observed)
   end)

   it("does NOT fire when no kind has count >= 3", function()
      -- Sanity baseline: pair-only + singletons should produce zero events.
      local active, observed = record_pung_events()
      local p1 = tiles({
         {"east_a","east"}, {"east_b","east"},                       -- pair only
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"tiao_9_a","tiao_9"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"wan_9_a","wan_9"},
      })
      local deal = make_deal(p1, {})
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r.ok, r.error)
      assert.are.same({}, observed)
   end)

   it("fires exactly once for a 4-of-a-kind in hand and seen-set records the kind", function()
      -- 4 east + 10 fillers. After discard, 4 easts remain in concealed;
      -- count=4 still satisfies c>=3 and the event must fire once for east
      -- with tiles slice capped at 3.
      local active, observed = record_pung_events()
      local capture_tiles: {{Tile}} = {}
      local capture_b: Boon = {
         id = "capture", cluster = "concealed", name = "capture",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0,
         listens = {"on_concealed_pung_formed"},
         condition = function(_c: BoonContext, _e: EventData): boolean return true end,
         effect    = function(_c: BoonContext, ev: EventData)
            local cp = ev as ConcealedPungFormedEvent
            capture_tiles[#capture_tiles + 1] = cp.tiles
         end,
      }
      registry.register(capture_b)

      local p1 = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"}, {"east_d","east"},
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_9_a","wan_9"},
      })
      local deal = make_deal(p1, {})
      deal.active_boons[#deal.active_boons + 1] = active
      deal.active_boons[#deal.active_boons + 1] =
         context.new_active("capture", "starter" as AcquisitionPoint)

      local r = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r.ok, r.error)
      assert.are.same({"east"}, observed)
      assert.are.equal(1, #capture_tiles)
      assert.are.equal(3, #capture_tiles[1])
      assert.are.equal(1, #r.deal.players[1].concealed_pung_kinds_seen)

      -- Drop one east to 3, then discard — still in seen, must NOT re-fire.
      local d2 = r.deal
      d2.phase = "awaiting_action" as DealPhase
      d2.current_player = 1
      d2.has_pending_discard = false
      d2.reaction_passes = {}
      d2.pending_claims = {}
      d2.players[1].hand.concealed_tiles = tiles({
         {"east_a","east"}, {"east_b","east"}, {"east_c","east"},      -- 3 easts
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
      })
      local r2 = engine.apply_action(d2, engine.discard(1, "wan_2_a" as TileId))
      assert.is_true(r2.ok, r2.error)
      assert.are.same({"east"}, observed)   -- still only the original event
   end)
end)

-- ── Deal-start emission path ─────────────────────────────────────────────

describe("on_concealed_pung_formed at deal start", function()
   local run_state = require("game.run_state")

   before_each(function()
      registry.reset()
   end)

   it("fires once at deal start when the opening hand already contains a pung", function()
      -- Drive via engine.new_deal_with_run with a recording boon attached to
      -- the run. The opening hand is determined by the seed; we sample seeds
      -- until we find one where p1 opens with a triplet, then assert the
      -- event fires for that kind. The boon is added BEFORE start so the
      -- on_deal_start emission path picks it up.
      local active, observed = record_pung_events()
      local rs = run_state.new_run(rng_mod.from_seed(1))
      rs.active_boons[#rs.active_boons + 1] = active

      local found_seed = -1
      local found_kind: string = ""
      for s = 1, 200 do
         local deal_probe = engine.new_deal(rng_mod.from_seed(s))
         local counts: {string:integer} = {}
         for _, t in ipairs(deal_probe.players[1].hand.concealed_tiles) do
            counts[t.kind_id as string] = (counts[t.kind_id as string] or 0) + 1
         end
         for k, c in pairs(counts) do
            if c >= 3 then found_seed = s; found_kind = k; break end
         end
         if found_seed > 0 then break end
      end
      assert.is_true(found_seed > 0, "no seed produced opening triplet in 200 tries")

      local rs2 = run_state.new_run(rng_mod.from_seed(found_seed))
      rs2.active_boons[#rs2.active_boons + 1] = active
      engine.new_deal_with_run(rng_mod.from_seed(found_seed), rs2)
      -- Observed must contain found_kind (and possibly more if multiple
      -- triplets opened).
      local saw = false
      for _, k in ipairs(observed) do
         if k == found_kind then saw = true end
      end
      assert.is_true(saw, "expected event for kind " .. found_kind)
   end)
end)

-- ── Event ordering: pung event precedes on_set_formed ─────────────────────

describe("on_concealed_pung_formed ordering vs on_set_formed", function()
   before_each(function()
      registry.reset()
   end)

   it("fires the pung event before the set_formed event for a crossing-discard", function()
      -- Build a hand where the player's discard SIMULTANEOUSLY (a) leaves a
      -- concealed pung in hand (fires on_concealed_pung_formed) AND (b)
      -- crosses set_count_high_water from 0 to 1 (fires on_set_formed).
      -- A pung counts as a set per total_set_count, so a single concealed
      -- pung at end-of-turn-discard is exactly this case.
      local sequence: {string} = {}
      local watcher: Boon = {
         id = "watcher", cluster = "honor", name = "watcher",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0,
         listens = {"on_concealed_pung_formed", "on_set_formed"},
         condition = function(_c: BoonContext, _e: EventData): boolean return true end,
         effect    = function(_c: BoonContext, ev: EventData)
            sequence[#sequence + 1] = ev.event_name as string
         end,
      }
      registry.register(watcher)

      local active = context.new_active("watcher", "starter" as AcquisitionPoint)
      local deal = make_deal(p1_with_east_pung_plus_discard(), {})
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.discard(1, "wan_9_a" as TileId))
      assert.is_true(r.ok, r.error)
      assert.is_true(#sequence >= 2)
      assert.are.equal("on_concealed_pung_formed", sequence[1])
      assert.are.equal("on_set_formed", sequence[2])
   end)
end)
