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
   end)

   describe("estimate_fan_for_target", function()
      it("returns >=3 fan for dui_dui_hu base", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         local fan = strategy.estimate_fan_for_target(d, 1, "dui_dui_hu" as TargetKind)
         -- dui_dui_hu base = 3 + men_qian +1 = 4
         assert.is_true(fan >= 3, "expected ≥3 fan, got " .. tostring(fan))
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

   describe("choose_target", function()
      it("picks dui_dui_hu when the hand is pair-heavy", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         local target, est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY)
         assert.are.equal("dui_dui_hu", target as string)
         assert.is_true(est >= 3)
      end)

      it("picks qing_yi_se when hand is single-suit-heavy with no honors", function()
         local d = make_deal(parse("123t 456t 789t 23t 99t"), {})
         local target, _est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY)
         assert.are.equal("qing_yi_se", target as string)
      end)

      it("picks hun_yi_se when hand is single-suit + honors", function()
         local d = make_deal(parse("123t 456t 789t E E F F"), {})
         local target, _est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY)
         assert.are.equal("hun_yi_se", target as string)
      end)

      it("falls through to default for genuinely mixed hands", function()
         -- Tiles spread across all three suits + a couple of honors, with
         -- weak pair structure. No single target shape fits well, so the
         -- baseline (default) wins.
         local d = make_deal(parse("1t 4w 7b 2t 5w 8b 3t 6w 9b 23t E S"), {})
         local target, est = strategy.choose_target(d, 1, strategy.NEUTRAL_PERSONALITY)
         assert.are.equal("default", target as string)
         assert.is_true(est >= 1)   -- ping hu base
      end)
   end)

   describe("tile_value", function()
      it("scores middle suited tiles higher for sequence targets", function()
         local mid = strategy.tile_value("tiao_5" as TileKindId, "default" as TargetKind, "east" as Wind, "east" as Wind)
         local terminal = strategy.tile_value("tiao_1" as TileKindId, "default" as TargetKind, "east" as Wind, "east" as Wind)
         local honor = strategy.tile_value("east" as TileKindId, "default" as TargetKind, "east" as Wind, "east" as Wind)
         assert.is_true(mid > terminal)
         assert.is_true(terminal > honor)
      end)

      it("scores honors high for triplet targets, with seat/round wind boost", function()
         local dragon = strategy.tile_value("fa_cai" as TileKindId, "dui_dui_hu" as TargetKind, "east" as Wind, "east" as Wind)
         local seat_wind = strategy.tile_value("east" as TileKindId, "dui_dui_hu" as TargetKind, "east" as Wind, "south" as Wind)
         local generic_honor = strategy.tile_value("west" as TileKindId, "dui_dui_hu" as TargetKind, "east" as Wind, "south" as Wind)
         assert.is_true(dragon >= 4)
         assert.is_true(seat_wind > generic_honor)   -- seat wind gets +1
      end)
   end)

   describe("has_three_fan_target", function()
      it("returns true for a hand that can reach dui_dui_hu", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), {})
         assert.is_true(strategy.has_three_fan_target(d, 1))
      end)

      it("returns true via default fallback when no strong target", function()
         -- Default's est_fan is base 1 + men_qian 1 = 2, below 3. But choose_target
         -- gates differently from has_three_fan_target — the latter checks all
         -- targets; even a junk hand could reach hun_yi_se / dui_dui_hu / qing_yi_se
         -- in principle. This test pins the contract: a hand with at least *some*
         -- structure should pass.
         local d = make_deal(parse("11t 22w 33b 44t 55w 66b 7b"), {})
         assert.is_true(strategy.has_three_fan_target(d, 1))
      end)
   end)
end)
