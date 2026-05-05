-- S06 strategy tests: target selection, ukeire, fan estimation, forward-
-- compat boon path. Pure unit tests — no engine integration.

require("core.types")
require("game.deal_types")
require("effects.effect_types")
local rng_mod   = require("core.rng")
local strategy  = require("game.ai_strategy")
local notation  = require("support.hand_notation")
local boons_init = require("effects.boons.init")
local registry  = require("effects.effect_registry")

-- ── Helpers ────────────────────────────────────────────────────────────────

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok, "notation error: " .. r.error)
   return r.tiles
end

local function blank_score_result(): ScoreResult
   return {
      win_shape_kind = "" as WinShapeKind,
      reasons        = {},
      total_fan      = 0,
      is_limit       = false,
      rating         = "" as Rating,
      valid_hu       = false,
   }
end

-- Build a 4-player DealState with the given concealed tiles for player 1.
local function make_deal(p1_concealed: {Tile}, sets: {TileSet}): DealState
   local function mk(tiles: {Tile}, sw: string, human: boolean, declared_sets: {TileSet}): PlayerState
      return {
         hand                = { concealed_tiles = tiles, sets = declared_sets, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
      }
   end
   return {
      players = {
         mk(p1_concealed, "east", true, sets),
         mk({}, "south", false, {}),
         mk({}, "west",  false, {}),
         mk({}, "north", false, {}),
      },
      wall                     = { tiles = {} },
      phase                    = "awaiting_action" as DealPhase,
      current_player           = 1,
      dealer                   = 1,
      round_wind               = "east" as Wind,
      pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
      has_pending_discard      = false,
      pending_added_kong       = {
         tile_id  = "" as TileId,
         tile     = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         declarer = 0,
      },
      has_pending_kong         = false,
      rng                      = rng_mod.from_seed(1),
      deal_result              = {
         winner_player_index = 0, won_by_zi_mo = false,
         score_result        = blank_score_result(),
         has_score_result    = false,
      },
      has_deal_result          = false,
      reaction_passes          = {},
      pending_claims           = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = "" as TileId,
      has_last_drawn           = false,
      effect_states            = {},
   }
end

-- ── Tests ──────────────────────────────────────────────────────────────────

describe("ai_strategy", function()

   before_each(function()
      boons_init.reset_and_register_all()
   end)

   describe("compute_features", function()
      it("counts honor tiles and pairs from concealed and open sets", function()
         local concealed = parse("111t 5w E S W F H 9b")
         local f = strategy.compute_features(concealed, {})
         -- Honors: E, S, W, F, H = 5 honor tiles. None of them paired.
         assert.are.equal(5, f.honor_count)
         assert.are.equal(0, f.honor_pairs)
         assert.are.equal(1, f.pair_count)   -- only triple of 1t counts >=2
         assert.are.equal(1, f.triplet_count) -- 111t
      end)

      it("identifies dominant suit", function()
         local concealed = parse("123t 456t 789t 23t 99w")
         local f = strategy.compute_features(concealed, {})
         assert.are.equal("tiao", f.max_suit)
         assert.are.equal(11, f.max_suit_count)
         assert.are.equal(2, f.off_suit_count)   -- two wan_9
      end)

      it("credits open peng/kong as triplet (Fix A)", function()
         -- Concealed has 1 triplet (444t); one open peng of 5T should bump
         -- triplet_count to 2 — the open peng is structurally a pung
         -- equivalent for dui_dui_hu fitness.
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "tiao_5_a" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_b" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_c" as TileId, kind_id = "tiao_5" as TileKindId },
               },
               called_from = 4,
            },
         }
         local f = strategy.compute_features(parse("444t 22w 33b"), sets)
         assert.are.equal(2, f.triplet_count)
         assert.are.equal(0, f.open_chi_count)
         assert.is_false(f.has_committed_honor)
      end)

      it("tracks open_chi_count and committed_suits", function()
         -- Open chi of 4T-5T-6T → open_chi_count=1, committed_suits=[tiao].
         local sets: {TileSet} = {
            {
               kind = "chi" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "tiao_4_a" as TileId, kind_id = "tiao_4" as TileKindId },
                  { tile_id = "tiao_5_a" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_6_a" as TileId, kind_id = "tiao_6" as TileKindId },
               },
               called_from = 4,
            },
         }
         local f = strategy.compute_features(parse("11w 22w 33b 44b 5b"), sets)
         assert.are.equal(0, f.triplet_count)         -- chi is not a triplet
         assert.are.equal(1, f.open_chi_count)
         assert.are.equal(1, #f.committed_suits)
         assert.are.equal("tiao", f.committed_suits[1])
      end)

      it("includes open sets before choosing dominant suit", function()
         -- Concealed is tiao-heavy by itself, but the committed open bing peng
         -- makes bing the full-hand dominant suit.
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_b" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_c" as TileId, kind_id = "bing_5" as TileKindId },
               },
               called_from = 4,
            },
         }
         local f = strategy.compute_features(parse("123t 4b"), sets)
         assert.are.equal("bing", f.max_suit)
         assert.are.equal(4, f.max_suit_count)
         assert.are.equal(3, f.off_suit_count)
      end)

      it("flags has_committed_honor on open peng of an honor", function()
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "fa_cai_a" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_b" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_c" as TileId, kind_id = "fa_cai" as TileKindId },
               },
               called_from = 4,
            },
         }
         local f = strategy.compute_features(parse("123t 456t 99t"), sets)
         assert.is_true(f.has_committed_honor)
         assert.are.equal(1, f.triplet_count)   -- open peng counted
      end)
   end)

   describe("estimate_fan_for_target", function()
      it("returns >=3 fan for dui_dui_hu base", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         local fan = strategy.estimate_fan_for_target(d, 1, "dui_dui_hu" as TargetKind)
         -- dui_dui_hu base = 3; men_qian is intentionally not counted in the estimate.
         assert.is_true(fan >= 3, "expected ≥3 fan, got " .. tostring(fan))
      end)

      it("counts seat wind and round wind modifiers independently", function()
         -- Player 1 is east in east round. A realized east triplet adds both
         -- Seat Wind Pung and Round Wind Pung in the real scorer, so the
         -- estimate should be default base 1 + 2 modifiers = 3.
         local d = make_deal(parse("E E E 123t 456w 78b 9b"), {})
         local fan = strategy.estimate_fan_for_target(d, 1, "default" as TargetKind)
         assert.are.equal(3, fan)
      end)

      it("returns >=6 for qing_yi_se", function()
         local d = make_deal(parse("123t 456t 789t 23t 99t"), {})
         local fan = strategy.estimate_fan_for_target(d, 1, "qing_yi_se" as TargetKind)
         assert.is_true(fan >= 6, "expected ≥6 fan, got " .. tostring(fan))
      end)

      it("returns < 3 fan for default (Ping Hu base) without men_qian", function()
         -- A hand with an open peng cannot be men_qian. default = 1 fan.
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "tiao_5_a" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_b" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_c" as TileId, kind_id = "tiao_5" as TileKindId },
               },
               called_from = 4,
            },
         }
         local d = make_deal(parse("123t 456t 789t 99w"), sets)
         local fan = strategy.estimate_fan_for_target(d, 1, "default" as TargetKind)
         assert.are.equal(1, fan)
      end)

      it("returns 0 for dui_dui_hu when an open chi exists (Fix B)", function()
         local sets: {TileSet} = {
            {
               kind = "chi" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "tiao_3_a" as TileId, kind_id = "tiao_3" as TileKindId },
                  { tile_id = "tiao_4_a" as TileId, kind_id = "tiao_4" as TileKindId },
                  { tile_id = "tiao_5_a" as TileId, kind_id = "tiao_5" as TileKindId },
               },
               called_from = 4,
            },
         }
         -- Hand-shape would otherwise look great for dui_dui_hu (3 triplets).
         local d = make_deal(parse("888t 99t 444w 55w 7b"), sets)
         local fan = strategy.estimate_fan_for_target(d, 1, "dui_dui_hu" as TargetKind)
         assert.are.equal(0, fan)
      end)

      it("returns 0 for qing_yi_se with a committed honor (Fix B)", function()
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "fa_cai_a" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_b" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_c" as TileId, kind_id = "fa_cai" as TileKindId },
               },
               called_from = 4,
            },
         }
         local d = make_deal(parse("123t 456t 789t 99t"), sets)
         local fan = strategy.estimate_fan_for_target(d, 1, "qing_yi_se" as TargetKind)
         assert.are.equal(0, fan)
      end)

      it("returns 0 for qing_yi_se with two committed suits (Fix B)", function()
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "tiao_5_a" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_b" as TileId, kind_id = "tiao_5" as TileKindId },
                  { tile_id = "tiao_5_c" as TileId, kind_id = "tiao_5" as TileKindId },
               },
               called_from = 4,
            },
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "wan_3_a" as TileId, kind_id = "wan_3" as TileKindId },
                  { tile_id = "wan_3_b" as TileId, kind_id = "wan_3" as TileKindId },
                  { tile_id = "wan_3_c" as TileId, kind_id = "wan_3" as TileKindId },
               },
               called_from = 4,
            },
         }
         local d = make_deal(parse("123t 99w 7b"), sets)
         assert.are.equal(0, strategy.estimate_fan_for_target(d, 1, "qing_yi_se" as TargetKind))
         assert.are.equal(0, strategy.estimate_fan_for_target(d, 1, "hun_yi_se" as TargetKind))
      end)

      it("includes boon contributions via the runner (forward-compat)", function()
         -- Construct a synthetic active effect that always adds +2 fan to
         -- player 1's score. Locks in that the runner is wired even though
         -- M1 vanilla AIs have no real boons.
         registry.register({
            metadata = {
               effect_id   = "test_plus_two",
               label       = "Test +2",
               description = "synthetic test boon",
               source_kind = "boon" as EffectSourceKind,
               source_id   = "test_plus_two",
               priority    = 100,
            },
            on_score = function(_sctx: EffectScoreContext, _deal: DealState): {ScoreReason}
               return { {
                  category = "boon" as ScoreReasonCategory,
                  label    = "Test +2",
                  fan      = 2,
                  is_limit = false,
               } }
            end,
         } as EffectModule)

         local d = make_deal(parse("123t 456t 789t 23t 99t"), {})
         d.effect_states["test_plus_two_1"] = {
            active_effect_id   = "test_plus_two_1",
            effect_id          = "test_plus_two",
            source_kind        = "boon" as EffectSourceKind,
            source_id          = "test_plus_two",
            owner_player_index = 1,
            has_owner          = true,
            counters           = {},
            used_this_deal     = false,
         }
         local fan_with_boon = strategy.estimate_fan_for_target(d, 1, "qing_yi_se" as TargetKind)
         d.effect_states = {}
         local fan_without   = strategy.estimate_fan_for_target(d, 1, "qing_yi_se" as TargetKind)
         assert.are.equal(2, fan_with_boon - fan_without,
            "synthetic +2 boon should contribute +2 fan to projected estimate")
      end)
   end)

   describe("visible_depletion (T11)", function()
      it("returns 0 for default target (no specific tile pool)", function()
         local d = make_deal(parse("11t 22w 33b 44t 55w 66b 7b"), {})
         local live = strategy.compute_live_counts(d, 1)
         local feat = strategy.compute_features(d.players[1].hand.concealed_tiles, {})
         local dep = strategy.visible_depletion(
            "default" as TargetKind, feat, live, "east" as Wind, "east" as Wind
         )
         assert.are.equal(0.0, dep)
      end)

      it("rises for qing_yi_se when opponents have committed the dominant suit", function()
         -- p1 has bing-suit-leaning hand. Compute depletion before and
         -- after p2 grabs an open peng of bing_5: opponent commitment
         -- removes 3 bing tiles from the wall, raising depletion.
         local d_clean = make_deal(parse("123b 456b 9b 99w E S"), {})
         local live_clean = strategy.compute_live_counts(d_clean, 1)
         local feat_clean = strategy.compute_features(d_clean.players[1].hand.concealed_tiles, {})
         local dep_clean = strategy.visible_depletion(
            "qing_yi_se" as TargetKind, feat_clean, live_clean, "east" as Wind, "east" as Wind
         )

         local d_committed = make_deal(parse("123b 456b 9b 99w E S"), {})
         d_committed.players[2].hand.sets = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_b" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_c" as TileId, kind_id = "bing_5" as TileKindId },
               },
               called_from = 1,
            },
         }
         local live_committed = strategy.compute_live_counts(d_committed, 1)
         local feat_committed = strategy.compute_features(d_committed.players[1].hand.concealed_tiles, {})
         local dep_committed = strategy.visible_depletion(
            "qing_yi_se" as TargetKind, feat_committed, live_committed, "east" as Wind, "east" as Wind
         )

         assert.is_true(dep_committed > dep_clean,
            string.format("opponent peng of bing_5 should raise qing_yi_se depletion: clean=%.3f committed=%.3f",
               dep_clean, dep_committed))
      end)

      it("rises for hun_yi_se when opponents discard suit + honors", function()
         local d_clean = make_deal(parse("123b 456b 9b E E S S"), {})
         local live_clean = strategy.compute_live_counts(d_clean, 1)
         local feat_clean = strategy.compute_features(d_clean.players[1].hand.concealed_tiles, {})
         local dep_clean = strategy.visible_depletion(
            "hun_yi_se" as TargetKind, feat_clean, live_clean, "east" as Wind, "east" as Wind
         )

         local d_dump = make_deal(parse("123b 456b 9b E E S S"), {})
         -- p3 dumps bing tiles in their discard pile.
         d_dump.players[3].hand.discards = {
            { tile_id = "bing_2_d" as TileId, kind_id = "bing_2" as TileKindId },
            { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId },
            { tile_id = "bing_5_b" as TileId, kind_id = "bing_5" as TileKindId },
            { tile_id = "bing_8_a" as TileId, kind_id = "bing_8" as TileKindId },
         }
         local live_dump = strategy.compute_live_counts(d_dump, 1)
         local feat_dump = strategy.compute_features(d_dump.players[1].hand.concealed_tiles, {})
         local dep_dump = strategy.visible_depletion(
            "hun_yi_se" as TargetKind, feat_dump, live_dump, "east" as Wind, "east" as Wind
         )

         assert.is_true(dep_dump > dep_clean,
            "discards in the dominant suit should raise hun_yi_se depletion")
      end)
   end)

   describe("expected_fan_dist (T10)", function()
      it("downgrades qing_yi_se relative to dui_dui_hu when opponents commit the suit", function()
         -- Pair-heavy hand with leaning toward bing. Without opponent
         -- pressure, qing_yi_se is a real path (6 fan). After p2 commits
         -- a bing peng, qing_yi_se's contribution drops sharply while
         -- dui_dui_hu's contribution stays robust.
         local d_clean = make_deal(parse("11b 22b 33b 44t 55w F F"), {})
         local live_clean = strategy.compute_live_counts(d_clean, 1)
         local _dist_clean, _total_clean, dom_clean = strategy.expected_fan_dist(d_clean, 1, live_clean)

         local d_pressure = make_deal(parse("11b 22b 33b 44t 55w F F"), {})
         d_pressure.players[2].hand.sets = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "bing_7_a" as TileId, kind_id = "bing_7" as TileKindId },
                  { tile_id = "bing_7_b" as TileId, kind_id = "bing_7" as TileKindId },
                  { tile_id = "bing_7_c" as TileId, kind_id = "bing_7" as TileKindId },
               },
               called_from = 1,
            },
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "bing_8_a" as TileId, kind_id = "bing_8" as TileKindId },
                  { tile_id = "bing_8_b" as TileId, kind_id = "bing_8" as TileKindId },
                  { tile_id = "bing_8_c" as TileId, kind_id = "bing_8" as TileKindId },
               },
               called_from = 1,
            },
         }
         local live_pressure = strategy.compute_live_counts(d_pressure, 1)
         local dist_pressure, _total_pressure, dom_pressure = strategy.expected_fan_dist(d_pressure, 1, live_pressure)

         -- After heavy bing commitment by an opponent, the dominant
         -- target should not still be qing_yi_se (its pool is depleted).
         assert.is_true(dom_clean as string ~= "qing_yi_se" or dom_pressure as string ~= "qing_yi_se",
            "expected at least one of clean/pressure to step away from qing_yi_se under depletion pressure")
         assert.is_true(dist_pressure["dui_dui_hu"] >= dist_pressure["qing_yi_se"],
            "with opponent bing commitment, dui_dui_hu should be at least as attractive as qing_yi_se")
      end)
   end)

   describe("choose_target", function()
      it("picks dui_dui_hu when the hand is pair-heavy", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         local live = strategy.compute_live_counts(d, 1)
         local target, est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY, live)
         assert.are.equal("dui_dui_hu", target as string)
         assert.is_true(est >= 3)
      end)

      it("picks qing_yi_se when hand is single-suit-heavy with no honors", function()
         local d = make_deal(parse("123t 456t 789t 23t 99t"), {})
         local live = strategy.compute_live_counts(d, 1)
         local target, _est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY, live)
         assert.are.equal("qing_yi_se", target as string)
      end)

      it("picks hun_yi_se when hand is single-suit + honors", function()
         local d = make_deal(parse("123t 456t 789t E E F F"), {})
         local live = strategy.compute_live_counts(d, 1)
         local target, _est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY, live)
         assert.are.equal("hun_yi_se", target as string)
      end)

      it("falls through to default for genuinely mixed hands", function()
         -- Tiles spread across all three suits + a couple of honors, with
         -- weak pair structure. No single target shape fits well, so the
         -- baseline (default) wins.
         local d = make_deal(parse("1t 4w 7b 2t 5w 8b 3t 6w 9b 23t E S"), {})
         local live = strategy.compute_live_counts(d, 1)
         local target, est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY, live)
         assert.are.equal("default", target as string)
         assert.is_true(est >= 1)   -- ping hu base
      end)
   end)

   describe("pick_best_discard (target-aware)", function()
      it("dui_dui_hu prefers to drop sequence singletons over pair tiles", function()
         -- Hand: 1 open peng of fa_cai (committed to dui_dui_hu) +
         -- 9T-9T pair + 3W-3W pair + 4T 5T 6T sequence singletons + 5B.
         -- Target is dui_dui_hu. Among equal-ting candidates the AI should
         -- drop a sequence-only singleton (4T/5T/6T/5B), not a pair tile.
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "fa_cai_a" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_b" as TileId, kind_id = "fa_cai" as TileKindId },
                  { tile_id = "fa_cai_c" as TileId, kind_id = "fa_cai" as TileKindId },
               },
               called_from = 4,
            },
         }
         local d = make_deal(parse("4t 5t 6t 99t 33w 5b"), sets)
         -- Maximally permissive live counts so generic ting doesn't dominate.
         local live: {string: integer} = {}
         for _, k in ipairs({"tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9",
            "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9",
            "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9",
            "east","south","west","north","fa_cai","hong_zhong","bai_ban"}) do
            live[k] = 4
         end
         local tid, _b, _a, _u = strategy.pick_best_discard(d, 1, strategy.NEUTRAL_PERSONALITY,
            "dui_dui_hu" as TargetKind, live)
         -- The chosen discard's kind must NOT be a paired kind (9t or 3w).
         local chosen_kind = ""
         for _, t in ipairs(d.players[1].hand.concealed_tiles) do
            if t.tile_id == tid then chosen_kind = t.kind_id as string; break end
         end
         assert.is_true(chosen_kind ~= "tiao_9" and chosen_kind ~= "wan_3",
            "expected a singleton drop, got " .. chosen_kind)
      end)

      it("qing_yi_se prefers to drop honors and off-suit tiles", function()
         -- Hand: 1 open peng of bing 5; concealed has tiao-suit tiles +
         -- a couple of honors. Target is qing_yi_se with max_suit=bing.
         -- The AI should drop a non-bing tile — preferentially an honor
         -- or off-suit tile — over the bing tile.
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_b" as TileId, kind_id = "bing_5" as TileKindId },
                  { tile_id = "bing_5_c" as TileId, kind_id = "bing_5" as TileKindId },
               },
               called_from = 4,
            },
         }
         local d = make_deal(parse("123b 456b 789b 7b E"), sets)
         local live: {string: integer} = {}
         for _, k in ipairs({"tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9",
            "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9",
            "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9",
            "east","south","west","north","fa_cai","hong_zhong","bai_ban"}) do
            live[k] = 4
         end
         local tid, _b, _a, _u = strategy.pick_best_discard(d, 1, strategy.NEUTRAL_PERSONALITY,
            "qing_yi_se" as TargetKind, live)
         local chosen_kind = ""
         for _, t in ipairs(d.players[1].hand.concealed_tiles) do
            if t.tile_id == tid then chosen_kind = t.kind_id as string; break end
         end
         assert.are.equal("east", chosen_kind, "qing_yi_se should drop the honor first")
      end)

      it("hun_yi_se keeps honors but drops off-suit non-honors", function()
         local sets: {TileSet} = {
            {
               kind = "peng" as TileSetKind,
               visibility = "open" as SetVisibility,
               tiles = {
                  { tile_id = "wan_3_a" as TileId, kind_id = "wan_3" as TileKindId },
                  { tile_id = "wan_3_b" as TileId, kind_id = "wan_3" as TileKindId },
                  { tile_id = "wan_3_c" as TileId, kind_id = "wan_3" as TileKindId },
               },
               called_from = 4,
            },
         }
         -- max_suit will be wan (3 tiles in concealed + 3 in peng = 6 wan).
         -- Off-suit non-honor (bing) should be dropped; honors should stay.
         local d = make_deal(parse("123w 456w 5b E E F"), sets)
         local live: {string: integer} = {}
         for _, k in ipairs({"tiao_1","tiao_2","tiao_3","tiao_4","tiao_5","tiao_6","tiao_7","tiao_8","tiao_9",
            "wan_1","wan_2","wan_3","wan_4","wan_5","wan_6","wan_7","wan_8","wan_9",
            "bing_1","bing_2","bing_3","bing_4","bing_5","bing_6","bing_7","bing_8","bing_9",
            "east","south","west","north","fa_cai","hong_zhong","bai_ban"}) do
            live[k] = 4
         end
         local tid, _b, _a, _u = strategy.pick_best_discard(d, 1, strategy.NEUTRAL_PERSONALITY,
            "hun_yi_se" as TargetKind, live)
         local chosen_kind = ""
         for _, t in ipairs(d.players[1].hand.concealed_tiles) do
            if t.tile_id == tid then chosen_kind = t.kind_id as string; break end
         end
         assert.are.equal("bing_5", chosen_kind, "hun_yi_se should drop off-suit non-honor first")
      end)
   end)

   describe("has_three_fan_target", function()
      it("returns true for a hand that can reach dui_dui_hu", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         local live = strategy.compute_live_counts(d, 1)
         assert.is_true(strategy.has_three_fan_target(d, 1, live))
      end)

      it("returns true via default fallback when no strong target", function()
         -- A hand with at least some structure should reach a 3-fan target
         -- through one of the four target paths.
         local d = make_deal(parse("11t 22w 33b 44t 55w 66b 7b"), {})
         local live = strategy.compute_live_counts(d, 1)
         assert.is_true(strategy.has_three_fan_target(d, 1, live))
      end)
   end)
end)
