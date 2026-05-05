-- S04 effect system tests: registry, runner, score modifiers, hooks, command
-- application, and per-boon behavior for the seven Milestone 1 starter boons.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.effect_types")
local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local invariants = require("game.deal_invariants")
local registry   = require("effects.effect_registry")
local runner     = require("effects.effect_runner")
local boons_init = require("effects.boons.init")
local content    = require("content.boons")
local run_state  = require("game.run_state")
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

-- Builds a RunState seeded with the given starter boon ids, owned by player 1.
local function make_run_with_boons(boon_ids: {string}, round_index: integer): RunState
   local rng = rng_mod.from_seed(42)
   local rs = run_state.new_run(rng)
   rs.round_index = round_index
   for _, bid in ipairs(boon_ids) do
      rs.active_effects[#rs.active_effects + 1] = content.activate_for(bid, 1)
   end
   return rs
end

describe("effect_registry", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("returns nil for unknown ids", function()
      assert.is_nil(registry.get("does_not_exist"))
      assert.is_false(registry.has("does_not_exist"))
   end)

   it("returns registered modules", function()
      assert.is_not_nil(registry.get("current"))
      assert.is_true(registry.has("current"))
   end)

   it("sorts active effects by (priority, effect_id)", function()
      local actives: {ActiveEffectState} = {
         content.activate_for("third_eye",      1),
         content.activate_for("current",        1),
         content.activate_for("dragons_weight", 1),
      }
      local sorted = registry.sorted_for(actives)
      -- All starter boons share priority 100 → tie-broken by effect_id alphabetical.
      assert.are.equal("current",        sorted[1].effect_id)
      assert.are.equal("dragons_weight", sorted[2].effect_id)
      assert.are.equal("third_eye",      sorted[3].effect_id)
   end)

   it("sorted_for skips unregistered effect ids", function()
      registry.reset()
      registry.register(require("effects.boons.current"))
      local actives: {ActiveEffectState} = {
         content.activate_for("current",   1),
         content.activate_for("third_eye", 1),
      }
      local sorted = registry.sorted_for(actives)
      assert.are.equal(1, #sorted)
      assert.are.equal("current", sorted[1].effect_id)
   end)
end)

describe("effect_runner.apply_commands", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("increment_counter writes to the active effect's counters", function()
      local rs = make_run_with_boons({"current"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local cmd = runner.cmd_increment_counter("current_1", "x", 3)
      runner.apply_commands(d, { cmd })
      assert.are.equal(3, d.effect_states["current_1"].counters["x"])
      runner.apply_commands(d, { cmd })
      assert.are.equal(6, d.effect_states["current_1"].counters["x"])
   end)

   it("mark_used flips used_this_deal", function()
      local rs = make_run_with_boons({"fresh_start"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      assert.is_false(d.effect_states["fresh_start_1"].used_this_deal)
      runner.apply_commands(d, { runner.cmd_mark_used("fresh_start_1") })
      assert.is_true(d.effect_states["fresh_start_1"].used_this_deal)
   end)

   it("reveal_wall_front clamps at remaining wall size", function()
      local rs = make_run_with_boons({}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      runner.apply_commands(d, { runner.cmd_reveal_wall_front(5, 1) })
      assert.are.equal(5, #d.players[1].known_wall_tile_ids)
   end)
end)

describe("third_eye", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("reveals next 5 front-Wall tiles after opening deal", function()
      local rs = make_run_with_boons({"third_eye"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      assert.are.equal(5, #d.players[1].known_wall_tile_ids)
      assert.are.equal(d.wall.tiles[1].tile_id, d.players[1].known_wall_tile_ids[1])
      assert.are.equal(d.wall.tiles[5].tile_id, d.players[1].known_wall_tile_ids[5])
   end)

   it("preserves tile conservation after reveal", function()
      local rs = make_run_with_boons({"third_eye"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local r = invariants.validate_tile_conservation(d)
      assert.is_true(r.ok, r.details)
   end)
end)

describe("open_eyes", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("reveals 3 tiles after a Peng resolution", function()
      -- Construct a fixture: p1 has 12 + 2 wan_5 in concealed and is waiting.
      -- p4 discards wan_5; p1 calls Peng.
      local p1_concealed = parse("234t 678t 1w 23w 4b") -- 10 tiles
      p1_concealed[#p1_concealed + 1] = tile("wan_5_b", "wan_5")
      p1_concealed[#p1_concealed + 1] = tile("wan_5_c", "wan_5")
      local p4_concealed = { tile("wan_5_a", "wan_5") }

      local rs = make_run_with_boons({"open_eyes"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      -- Reset wall and hands to controlled fixture.
      d.players[1].hand.concealed_tiles = p1_concealed
      d.players[4].hand.concealed_tiles = p4_concealed
      d.players[2].hand.concealed_tiles = {}
      d.players[3].hand.concealed_tiles = {}
      d.wall.tiles = {
         tile("bing_1_a", "bing_1"),
         tile("bing_2_a", "bing_2"),
         tile("bing_3_a", "bing_3"),
         tile("bing_4_a", "bing_4"),
      }
      d.phase = "awaiting_action" as DealPhase
      d.current_player = 4
      d.players[1].known_wall_tile_ids = {}

      -- p4 discards wan_5_a → reaction window
      local tr1 = engine.apply_action(d, engine.discard(4, "wan_5_a" as TileId))
      assert.is_true(tr1.ok, tr1.error)
      -- p1 declares peng (after p2 and p3 pass)
      local tr2 = engine.apply_action(tr1.deal, engine.pass_reaction(2))
      assert.is_true(tr2.ok, tr2.error)
      local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(3))
      assert.is_true(tr3.ok, tr3.error)
      local tr4 = engine.apply_action(tr3.deal, engine.declare_peng(1, "wan_5_a" as TileId))
      assert.is_true(tr4.ok, tr4.error)

      assert.are.equal(3, #tr4.deal.players[1].known_wall_tile_ids)
      assert.are.equal("bing_1_a", tr4.deal.players[1].known_wall_tile_ids[1] as string)
      assert.are.equal("bing_3_a", tr4.deal.players[1].known_wall_tile_ids[3] as string)
   end)
end)

describe("current", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("increments counter when drawn tile matches majority suit", function()
      -- Set up p1 with mostly-wan hand of 13 tiles, then draw a wan tile.
      local rs = make_run_with_boons({"current"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      -- Force p1 hand to 13 tiles, all wan (majority).
      local wan_hand: {Tile} = {
         tile("wan_1_a","wan_1"), tile("wan_2_a","wan_2"), tile("wan_3_a","wan_3"),
         tile("wan_4_a","wan_4"), tile("wan_5_a","wan_5"), tile("wan_6_a","wan_6"),
         tile("wan_7_a","wan_7"), tile("wan_8_a","wan_8"), tile("wan_9_a","wan_9"),
         tile("tiao_1_a","tiao_1"), tile("tiao_2_a","tiao_2"), tile("bing_1_a","bing_1"),
         tile("east_a","east"),
      }
      d.players[1].hand.concealed_tiles = wan_hand
      -- Put a wan tile at the front so the drawn tile matches majority.
      d.wall.tiles = { tile("wan_1_b","wan_1") }

      d.phase = "awaiting_draw" as DealPhase
      d.current_player = 1

      local tr = engine.apply_action(d, engine.draw(1))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal(1, tr.deal.effect_states["current_1"].counters["suit_counters"])
   end)

   it("does not increment for honor draws", function()
      local rs = make_run_with_boons({"current"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      d.players[1].hand.concealed_tiles = {
         tile("wan_1_a","wan_1"), tile("wan_2_a","wan_2"), tile("wan_3_a","wan_3"),
         tile("wan_4_a","wan_4"), tile("wan_5_a","wan_5"), tile("wan_6_a","wan_6"),
         tile("wan_7_a","wan_7"), tile("wan_8_a","wan_8"), tile("wan_9_a","wan_9"),
         tile("tiao_1_a","tiao_1"), tile("tiao_2_a","tiao_2"), tile("bing_1_a","bing_1"),
         tile("east_a","east"),
      }
      d.wall.tiles = { tile("fa_cai_a","fa_cai") }
      d.phase = "awaiting_draw" as DealPhase
      d.current_player = 1

      local tr = engine.apply_action(d, engine.draw(1))
      assert.is_true(tr.ok, tr.error)
      local n = tr.deal.effect_states["current_1"].counters["suit_counters"] or 0
      assert.are.equal(0, n)
   end)

   it("counts tied majorities (any tied suit's draw counts)", function()
      local rs = make_run_with_boons({"current"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      -- 5 wan and 5 tiao tied in majority.
      d.players[1].hand.concealed_tiles = {
         tile("wan_1_a","wan_1"), tile("wan_2_a","wan_2"), tile("wan_3_a","wan_3"),
         tile("wan_4_a","wan_4"), tile("wan_5_a","wan_5"),
         tile("tiao_1_a","tiao_1"), tile("tiao_2_a","tiao_2"), tile("tiao_3_a","tiao_3"),
         tile("tiao_4_a","tiao_4"), tile("tiao_5_a","tiao_5"),
         tile("bing_1_a","bing_1"), tile("bing_2_a","bing_2"), tile("east_a","east"),
      }
      d.wall.tiles = { tile("tiao_6_a","tiao_6") }
      d.phase = "awaiting_draw" as DealPhase
      d.current_player = 1

      local tr = engine.apply_action(d, engine.draw(1))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal(1, tr.deal.effect_states["current_1"].counters["suit_counters"])
   end)
end)

describe("still_water + dragons_weight", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   -- Helper: dispatches the on_score hook directly with a fabricated context
   -- so we can verify each boon's score contribution in isolation.
   local function score_reasons_for(active_id: string, ctx: ScoreContext, shape: WinShape, deal: DealState): {ScoreReason}
      local mod = registry.get(deal.effect_states[active_id].effect_id)
      local sctx: EffectScoreContext = {
         active       = deal.effect_states[active_id],
         ctx          = ctx,
         shape        = shape,
         player_index = 1,
      }
      return mod.on_score(sctx, deal)
   end

   it("Still Water adds +1 fan when Men Qian", function()
      local rs = make_run_with_boons({"still_water"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local ctx: ScoreContext = {
         incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         has_incoming = false, is_zi_mo = true, is_men_qian = true,
         is_hai_di = false, is_gang_shang = false, is_qiang_gang = false,
         round_wind = "east" as Wind, seat_wind = "east" as Wind,
      }
      local shape: WinShape = { kind = "standard_four_sets_pair" as WinShapeKind, sets = {}, pair_kind = "wan_1" as TileKindId }
      local rs_reasons = score_reasons_for("still_water_1", ctx, shape, d)
      assert.are.equal(1, #rs_reasons)
      assert.are.equal(1, rs_reasons[1].fan)
   end)

   it("Still Water contributes nothing when not Men Qian", function()
      local rs = make_run_with_boons({"still_water"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local ctx: ScoreContext = {
         incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         has_incoming = false, is_zi_mo = false, is_men_qian = false,
         is_hai_di = false, is_gang_shang = false, is_qiang_gang = false,
         round_wind = "east" as Wind, seat_wind = "east" as Wind,
      }
      local shape: WinShape = { kind = "standard_four_sets_pair" as WinShapeKind, sets = {}, pair_kind = "wan_1" as TileKindId }
      local rs_reasons = score_reasons_for("still_water_1", ctx, shape, d)
      assert.are.equal(0, #rs_reasons)
   end)

   it("Dragon's Weight adds +1 fan per Dragon Peng/Kong", function()
      local rs = make_run_with_boons({"dragons_weight"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local fa_peng: TileSet = {
         kind = "peng" as TileSetKind, visibility = "open" as SetVisibility,
         tiles = { tile("fa_cai_a","fa_cai"), tile("fa_cai_b","fa_cai"), tile("fa_cai_c","fa_cai") },
         called_from = -1,
      }
      local zhong_kong: TileSet = {
         kind = "kong" as TileSetKind, visibility = "concealed" as SetVisibility,
         tiles = { tile("hong_zhong_a","hong_zhong"), tile("hong_zhong_b","hong_zhong"),
                   tile("hong_zhong_c","hong_zhong"), tile("hong_zhong_d","hong_zhong") },
         called_from = -1,
      }
      local ctx: ScoreContext = {
         incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         has_incoming = false, is_zi_mo = true, is_men_qian = false,
         is_hai_di = false, is_gang_shang = false, is_qiang_gang = false,
         round_wind = "east" as Wind, seat_wind = "east" as Wind,
      }
      local shape: WinShape = {
         kind = "standard_four_sets_pair" as WinShapeKind,
         sets = { fa_peng, zhong_kong }, pair_kind = "wan_1" as TileKindId,
      }
      local rs_reasons = score_reasons_for("dragons_weight_1", ctx, shape, d)
      assert.are.equal(1, #rs_reasons)
      assert.are.equal(2, rs_reasons[1].fan)
   end)
end)

describe("apply_score_modifiers (3-fan threshold)", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("does not promote a sub-3-fan hand to valid_hu via boon fan", function()
      -- A base hand with only 1 fan; a boon adding 1 fan should still leave
      -- total < 3, valid_hu = false. (We construct ScoreResult by hand.)
      local rs = make_run_with_boons({"still_water"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local base: ScoreResult = {
         win_shape_kind = "standard_four_sets_pair" as WinShapeKind,
         reasons = {
            { category = "hand_pattern" as ScoreReasonCategory, label = "Ping Hu", fan = 1, is_limit = false },
         },
         total_fan = 1, is_limit = false, rating = "C" as Rating, valid_hu = false,
      }
      local ctx: ScoreContext = {
         incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         has_incoming = false, is_zi_mo = true, is_men_qian = true,
         is_hai_di = false, is_gang_shang = false, is_qiang_gang = false,
         round_wind = "east" as Wind, seat_wind = "east" as Wind,
      }
      local shape: WinShape = { kind = "standard_four_sets_pair" as WinShapeKind, sets = {}, pair_kind = "wan_1" as TileKindId }
      local final = runner.apply_score_modifiers(d, ctx, shape, base, 1)
      -- Still Water adds +1 → total 2 → still below threshold.
      assert.are.equal(2, final.total_fan)
      assert.is_false(final.valid_hu)
   end)

   it("lets boon fan lift a valid Hu shape to the 3-fan floor", function()
      local rs = make_run_with_boons({"still_water"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      d.players[1].hand.concealed_tiles = parse("123t 456t 789t 123w 5b")
      d.players[4].hand.concealed_tiles = { tile("bing_5_a", "bing_5") }
      d.players[2].hand.concealed_tiles = {}
      d.players[3].hand.concealed_tiles = {}
      d.phase = "awaiting_action" as DealPhase
      d.current_player = 4

      local tr1 = engine.apply_action(d, engine.discard(4, "bing_5_a" as TileId))
      assert.is_true(tr1.ok, tr1.error)
      local tr2 = engine.apply_action(tr1.deal, engine.pass_reaction(2))
      assert.is_true(tr2.ok, tr2.error)
      local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(3))
      assert.is_true(tr3.ok, tr3.error)
      local tr4 = engine.apply_action(tr3.deal, engine.declare_hu(1, "bing_5_a" as TileId, false))
      assert.is_true(tr4.ok, tr4.error)
      assert.are.equal("deal_over", tr4.deal.phase as string)
      assert.are.equal(3, tr4.deal.deal_result.score_result.total_fan)
      assert.is_true(tr4.deal.deal_result.score_result.valid_hu)
   end)
end)

describe("momentum", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("returns 0 extra opening tiles in round 1", function()
      local rs = make_run_with_boons({"momentum"}, 1)
      local mods = runner.collect_opening_modifiers(rs.active_effects, rs.round_index)
      assert.are.equal(0, mods.extra_opening_tiles)
   end)

   it("returns round_index - 1 extras", function()
      local rs = make_run_with_boons({"momentum"}, 4)
      local mods = runner.collect_opening_modifiers(rs.active_effects, rs.round_index)
      assert.are.equal(3, mods.extra_opening_tiles)
   end)

   it("dealer receives extra tiles in opening for round_index > 1", function()
      local rs = make_run_with_boons({"momentum"}, 3)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      assert.are.equal(15, #d.players[1].hand.concealed_tiles)
      -- Total wall: 136 - (15 + 13*3) = 136 - 54 = 82 remaining
      assert.are.equal(82, #d.wall.tiles)
   end)

   it("dealer must trim surplus before confirm_opening", function()
      local rs = make_run_with_boons({"momentum"}, 3)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      -- Confirm should reject — dealer has 15 tiles.
      local tr = engine.apply_action(d, engine.confirm_opening(1))
      assert.is_false(tr.ok)
      -- Trim 2 tiles, then confirm.
      local t1 = d.players[1].hand.concealed_tiles[1].tile_id
      local tr1 = engine.apply_action(d, engine.discard_opening_surplus(1, t1))
      assert.is_true(tr1.ok, tr1.error)
      local t2 = tr1.deal.players[1].hand.concealed_tiles[1].tile_id
      local tr2 = engine.apply_action(tr1.deal, engine.discard_opening_surplus(1, t2))
      assert.is_true(tr2.ok, tr2.error)
      assert.are.equal(13, #tr2.deal.players[1].hand.concealed_tiles)
      assert.are.equal(2, #tr2.deal.players[1].opening_trim)
      local tr3 = engine.apply_action(tr2.deal, engine.confirm_opening(1))
      assert.is_true(tr3.ok, tr3.error)
      assert.are.equal("awaiting_draw", tr3.deal.phase as string)
   end)
end)

describe("fresh_start", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("exposes a swap action during opening_actions", function()
      local rs = make_run_with_boons({"fresh_start"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local actions = runner.collect_available_actions(d, 1)
      assert.are.equal(1, #actions)
      assert.are.equal("fresh_start_1", actions[1].active_effect_id)
      assert.are.equal("swap_tiles", actions[1].payload_kind)
   end)

   it("hides the swap action after used", function()
      local rs = make_run_with_boons({"fresh_start"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      d.effect_states["fresh_start_1"].used_this_deal = true
      local actions = runner.collect_available_actions(d, 1)
      assert.are.equal(0, #actions)
   end)

   it("swaps N tiles, draws N replacements, preserves tile conservation, clears Known Wall", function()
      local rs = make_run_with_boons({"fresh_start", "third_eye"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      -- Sanity: Third Eye filled known_wall; Fresh Start should clear it.
      assert.is_true(#d.players[1].known_wall_tile_ids > 0)

      local original_concealed: {string} = {}
      for _, t in ipairs(d.players[1].hand.concealed_tiles) do
         original_concealed[#original_concealed + 1] = t.tile_id as string
      end

      -- Swap the first 3 tiles of dealer's hand.
      local swap_ids: {TileId} = {
         d.players[1].hand.concealed_tiles[1].tile_id,
         d.players[1].hand.concealed_tiles[2].tile_id,
         d.players[1].hand.concealed_tiles[3].tile_id,
      }
      local tr = engine.apply_action(d, engine.use_effect_action(1, "fresh_start_1", swap_ids))
      assert.is_true(tr.ok, tr.error)

      local d2 = tr.deal
      assert.are.equal(13, #d2.players[1].hand.concealed_tiles)
      assert.is_true(d2.effect_states["fresh_start_1"].used_this_deal)
      assert.are.equal(0, #d2.players[1].known_wall_tile_ids)
      local r = invariants.validate_tile_conservation(d2)
      assert.is_true(r.ok, r.details)
   end)

   it("is rejected when used twice in the same deal", function()
      local rs = make_run_with_boons({"fresh_start"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local swap_id = d.players[1].hand.concealed_tiles[1].tile_id
      local tr1 = engine.apply_action(d, engine.use_effect_action(1, "fresh_start_1", { swap_id }))
      assert.is_true(tr1.ok, tr1.error)
      local swap_id2 = tr1.deal.players[1].hand.concealed_tiles[1].tile_id
      local tr2 = engine.apply_action(tr1.deal, engine.use_effect_action(1, "fresh_start_1", { swap_id2 }))
      assert.is_false(tr2.ok)
   end)

   it("is rejected outside opening_actions", function()
      local rs = make_run_with_boons({"fresh_start"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local tr1 = engine.apply_action(d, engine.confirm_opening(1))
      assert.is_true(tr1.ok, tr1.error)
      local swap_id = tr1.deal.players[1].hand.concealed_tiles[1].tile_id
      local tr2 = engine.apply_action(tr1.deal, engine.use_effect_action(1, "fresh_start_1", { swap_id }))
      assert.is_false(tr2.ok)
   end)
end)

describe("opening_actions phase", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("new_deal_with_run lands in opening_actions", function()
      local rs = make_run_with_boons({}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      assert.are.equal("opening_actions", d.phase as string)
   end)

   it("confirm_opening transitions to awaiting_draw with dealer current", function()
      local rs = make_run_with_boons({}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local tr = engine.apply_action(d, engine.confirm_opening(1))
      assert.is_true(tr.ok, tr.error)
      assert.are.equal("awaiting_draw", tr.deal.phase as string)
      assert.are.equal(1, tr.deal.current_player)
   end)

   it("confirm_opening rejects non-dealer", function()
      local rs = make_run_with_boons({}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local tr = engine.apply_action(d, engine.confirm_opening(2))
      assert.is_false(tr.ok)
   end)
end)

describe("dragon's weight: cannot bypass 3-fan via boons alone", function()
   before_each(function()
      boons_init.reset_and_register_all()
   end)

   it("scorer-side validation still happens before boon fan is added", function()
      -- A 0-fan invalid hand should never reach apply_score_modifiers because
      -- the scorer rejects valid_hu=false before the runner is called. Here we
      -- prove the runner itself does not flip valid_hu when total stays low.
      local rs = make_run_with_boons({"dragons_weight"}, 1)
      local d = engine.new_deal_with_run(rng_mod.from_seed(7), rs)
      local base: ScoreResult = {
         win_shape_kind = "standard_four_sets_pair" as WinShapeKind,
         reasons = {}, total_fan = 0, is_limit = false, rating = "C" as Rating, valid_hu = false,
      }
      local ctx: ScoreContext = {
         incoming_tile = { tile_id = "" as TileId, kind_id = "" as TileKindId },
         has_incoming = false, is_zi_mo = true, is_men_qian = true,
         is_hai_di = false, is_gang_shang = false, is_qiang_gang = false,
         round_wind = "east" as Wind, seat_wind = "east" as Wind,
      }
      local shape: WinShape = { kind = "standard_four_sets_pair" as WinShapeKind, sets = {}, pair_kind = "wan_1" as TileKindId }
      local final = runner.apply_score_modifiers(d, ctx, shape, base, 1)
      assert.are.equal(0, final.total_fan)
      assert.is_false(final.valid_hu)
   end)
end)
