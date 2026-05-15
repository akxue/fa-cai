-- S03 deal engine tests: phase transitions, tile conservation, Hu, Kong,
-- wall exhaustion, and engine-enforced reaction priority.

require("core.types")
require("core.rng")
require("game.deal_types")
local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local invariants = require("game.deal_invariants")
local notation   = require("support.hand_notation")

-- ── Helpers ────────────────────────────────────────────────────────────────

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok, "notation error: " .. r.error)
   return r.tiles
end

-- Plays one "safe" turn: current player draws and discards their first tile,
-- then all other players pass.
local function play_safe_turn(deal: DealState): DealState
   local cp = deal.current_player
   local tr1 = engine.apply_action(deal, engine.draw(cp))
   assert.is_true(tr1.ok, "draw failed: " .. tr1.error)
   local first = tr1.deal.players[cp].hand.concealed_tiles[1]
   local tr2 = engine.apply_action(tr1.deal, engine.discard(cp, first.tile_id))
   assert.is_true(tr2.ok, "discard failed: " .. tr2.error)
   local d = tr2.deal
   for i = 1, 4 do
      if i ~= cp then
         local tr = engine.apply_action(d, engine.pass_reaction(i))
         assert.is_true(tr.ok, "pass failed: " .. tr.error)
         d = tr.deal
         if (d.phase as string) ~= "reaction_window" then break end
      end
   end
   return d
end

-- Applies pass_reaction for every reactor in `players` against `deal`.
local function pass_all(deal: DealState, players: {integer}): DealState
   local d = deal
   for _, pi in ipairs(players) do
      local tr = engine.apply_action(d, engine.pass_reaction(pi))
      assert.is_true(tr.ok, "pass failed for player " .. tostring(pi) .. ": " .. tr.error)
      d = tr.deal
   end
   return d
end

-- Constructs a 4-player DealState with the given hands and wall.
-- Tile conservation is the caller's responsibility.
local function make_deal(
   p1: {Tile}, p2: {Tile}, p3: {Tile}, p4: {Tile},
   wall_tiles: {Tile}, phase: string,
   current_player: integer, last_drawn_tile_id: TileId, has_last_drawn: boolean
): DealState
   local function mk_player(tiles: {Tile}, sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = tiles, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
      }
   end
   return {
      players = {
         mk_player(p1, "east", true),
         mk_player(p2, "south", false),
         mk_player(p3, "west", false),
         mk_player(p4, "north", false),
      },
      wall                     = { tiles = wall_tiles },
      phase                    = phase as DealPhase,
      current_player           = current_player,
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
         score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating="" as Rating, valid_hu=false },
         has_score_result = false,
      },
      has_deal_result          = false,
      reaction_passes          = {},
      pending_claims           = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = last_drawn_tile_id,
      has_last_drawn           = has_last_drawn,
      effect_states            = {},
      active_boons             = {},
   }
end

-- Single tile constructor.
local function tile(tile_id: string, kind_id: string): Tile
   return { tile_id = tile_id as TileId, kind_id = kind_id as TileKindId }
end

-- ── Tests ──────────────────────────────────────────────────────────────────

describe("deal_engine", function()

   -- ── new_deal ─────────────────────────────────────────────────────────────
   describe("new_deal", function()
      it("deals 13 tiles to each of 4 players", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         assert.are.equal(4, #deal.players)
         for i = 1, 4 do
            assert.are.equal(13, #deal.players[i].hand.concealed_tiles)
         end
      end)

      it("wall has 84 tiles remaining (136 - 4*13)", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         assert.are.equal(84, #deal.wall.tiles)
      end)

      it("starts in awaiting_draw phase at player 1", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         assert.are.equal("awaiting_draw", deal.phase as string)
         assert.are.equal(1, deal.current_player)
      end)

      it("passes tile conservation", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local result = invariants.validate_tile_conservation(deal)
         assert.is_true(result.ok, result.details)
      end)

      it("player 1 is human, others are AI", function()
         local deal = engine.new_deal(rng_mod.from_seed(99))
         assert.is_true(deal.players[1].is_human)
         for i = 2, 4 do
            assert.is_false(deal.players[i].is_human)
         end
      end)
   end)

   -- ── draw ─────────────────────────────────────────────────────────────────
   describe("draw", function()
      it("player 1 draws a tile, hand grows to 14", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr = engine.apply_action(deal, engine.draw(1))
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("awaiting_action", tr.deal.phase as string)
         assert.are.equal(14, #tr.deal.players[1].hand.concealed_tiles)
         assert.are.equal(83, #tr.deal.wall.tiles)
      end)

      it("rejects draw by wrong player", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr = engine.apply_action(deal, engine.draw(2))
         assert.is_false(tr.ok)
      end)

      it("rejects draw in awaiting_action phase", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local tr2 = engine.apply_action(tr1.deal, engine.draw(1))
         assert.is_false(tr2.ok)
      end)

      it("tile conservation holds after draw", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr = engine.apply_action(deal, engine.draw(1))
         assert.is_true(tr.ok, tr.error)
         local r = invariants.validate_tile_conservation(tr.deal)
         assert.is_true(r.ok, r.details)
      end)

      it("removes the drawn tile from every player's Known Wall view", function()
         local d = make_deal(
            {}, {}, {}, {},
            { tile("bing_1_a", "bing_1"), tile("bing_2_a", "bing_2") },
            "awaiting_draw", 2, "" as TileId, false
         )
         d.players[1].known_wall_tile_ids = { "bing_1_a" as TileId, "bing_2_a" as TileId }
         d.players[2].known_wall_tile_ids = { "bing_1_a" as TileId }
         d.players[3].known_wall_tile_ids = { "bing_2_a" as TileId }

         local tr = engine.apply_action(d, engine.draw(2))
         assert.is_true(tr.ok, tr.error)
         assert.are.equal(1, #tr.deal.players[1].known_wall_tile_ids)
         assert.are.equal("bing_2_a", tr.deal.players[1].known_wall_tile_ids[1] as string)
         assert.are.equal(0, #tr.deal.players[2].known_wall_tile_ids)
         assert.are.equal(1, #tr.deal.players[3].known_wall_tile_ids)
      end)
   end)

   -- ── discard ───────────────────────────────────────────────────────────────
   describe("discard", function()
      it("player 1 draws then discards, opens reaction window", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, first.tile_id))
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("reaction_window", tr2.deal.phase as string)
         assert.is_true(tr2.deal.has_pending_discard)
         assert.are.equal(13, #tr2.deal.players[1].hand.concealed_tiles)
      end)

      it("rejects discard of tile not in hand", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, "fa_cai_z" as TileId))
         assert.is_false(tr2.ok)
      end)

      it("tile conservation holds after discard", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, first.tile_id))
         local r = invariants.validate_tile_conservation(tr2.deal)
         assert.is_true(r.ok, r.details)
      end)
   end)

   -- ── reaction window: all pass ─────────────────────────────────────────────
   describe("reaction window: all pass", function()
      it("resolves to player 2 awaiting_draw after all three pass", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, first.tile_id))

         local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(2))
         assert.is_true(tr3.ok, tr3.error)
         assert.are.equal("reaction_window", tr3.deal.phase as string)

         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(3))
         assert.is_true(tr4.ok, tr4.error)
         assert.are.equal("reaction_window", tr4.deal.phase as string)

         local tr5 = engine.apply_action(tr4.deal, engine.pass_reaction(4))
         assert.is_true(tr5.ok, tr5.error)
         assert.are.equal("awaiting_draw", tr5.deal.phase as string)
         assert.are.equal(2, tr5.deal.current_player)
         assert.are.equal(1, #tr5.deal.players[1].hand.discards)
         assert.is_false(tr5.deal.has_pending_discard)
      end)

      it("tile conservation holds after full turn cycle", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, first.tile_id))
         local d = pass_all(tr2.deal, {2, 3, 4})
         local r = invariants.validate_tile_conservation(d)
         assert.is_true(r.ok, r.details)
      end)

      it("rejects double-response by same player", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, engine.draw(1))
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, engine.discard(1, first.tile_id))
         local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(2))
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(2))
         assert.is_false(tr4.ok)
      end)

      it("turn 4 wraps back to player 1", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local d = deal
         for _ = 1, 3 do d = play_safe_turn(d) end
         assert.are.equal(4, d.current_player)
         d = play_safe_turn(d)
         assert.are.equal(1, d.current_player)
      end)
   end)

   -- ── Peng (queued + resolved after others pass) ───────────────────────────
   describe("peng", function()
      it("player 2 pengs after p3 and p4 pass", function()
         -- p1 has just one tile (tiao_1_c), already drew. p2 has two tiao_1.
         local p1_hand = { tile("tiao_1_c", "tiao_1") }
         local p2_hand = parse("11t 234t 567t 89t")  -- 11+2 = 13 tiles, two tiao_1 are _a and _b
         local d = make_deal(p1_hand, p2_hand, {}, {}, {}, "awaiting_action", 1, "tiao_1_c" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_1_c" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         local tr2 = engine.apply_action(tr1.deal, engine.declare_peng(2, "tiao_1_c" as TileId))
         assert.is_true(tr2.ok, tr2.error)
         -- Still in reaction window — p3 and p4 must respond
         assert.are.equal("reaction_window", tr2.deal.phase as string)
         assert.are.equal(1, #tr2.deal.pending_claims)

         local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(3))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("awaiting_action", tr4.deal.phase as string)
         assert.are.equal(2, tr4.deal.current_player)
         assert.are.equal(1, #tr4.deal.players[2].hand.sets)
         assert.are.equal("peng", tr4.deal.players[2].hand.sets[1].kind as string)
      end)
   end)

   -- ── Reaction priority: Hu beats other claims ─────────────────────────────
   describe("reaction priority", function()

      it("Hu beats Peng on the same discard", function()
         -- p3 hus on tiao_3 (Hun Yi Se hand). p2 also has a peng of tiao_3 available.
         -- Engine should resolve Hu in p3's favor.
         local p3_ting = parse("123t 456t 789t 12t 2E")  -- ting on tiao_3, Hun Yi Se
         local p2_hand = parse("33t 456w 789w 12w 33b")  -- has pair of tiao_3 → can peng
         local p1_hand = { tile("tiao_3_c", "tiao_3") }  -- only the discard
         local d = make_deal(p1_hand, p2_hand, p3_ting, {}, {}, "awaiting_action", 1, "tiao_3_c" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_c" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         -- p2 queues peng, p3 queues hu, p4 passes
         local tr2 = engine.apply_action(tr1.deal, engine.declare_peng(2, "tiao_3_c" as TileId))
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("reaction_window", tr2.deal.phase as string)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_hu(3, "tiao_3_c" as TileId, false))
         assert.is_true(tr3.ok, tr3.error)
         assert.are.equal("reaction_window", tr3.deal.phase as string)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         -- Hu wins: p3 is the deal winner, not p2's peng.
         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(3, tr4.deal.deal_result.winner_player_index)
         assert.is_false(tr4.deal.deal_result.won_by_zi_mo)
         -- p2 did NOT get a peng set
         assert.are.equal(0, #tr4.deal.players[2].hand.sets)
      end)

      it("Hu beats Chi on the same discard", function()
         -- p2 (next player) can chi, p3 hus. Hu wins.
         local p3_ting = parse("123t 456t 789t 12t 2E")
         local p2_hand = parse("24t 456w 789w 12w 33b")  -- has 2t and 4t → can chi tiao_3
         local p1_hand = { tile("tiao_3_c", "tiao_3") }
         local d = make_deal(p1_hand, p2_hand, p3_ting, {}, {}, "awaiting_action", 1, "tiao_3_c" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_c" as TileId))
         -- p2 queues chi using its tiao_2_a and tiao_4_a
         local tr2 = engine.apply_action(tr1.deal, engine.declare_chi(2, "tiao_3_c" as TileId, { "tiao_2_a" as TileId, "tiao_4_a" as TileId }))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_hu(3, "tiao_3_c" as TileId, false))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(3, tr4.deal.deal_result.winner_player_index)
      end)

      it("Peng beats Chi on the same discard", function()
         -- p2 (next player) chis tiao_3, p3 pengs tiao_3. Peng wins.
         -- Use unique tile_ids — p2 has tiao_2_a and tiao_4_a, p3 has tiao_3_a and tiao_3_b.
         local p2_hand = parse("24t 456w 789w 12w 33b")  -- 11 tiles
         local p3_hand = parse("33t 456b 789b 12b 33w")  -- 11 tiles, has 33t for peng
         local p1_hand = { tile("tiao_3_c", "tiao_3") }
         local d = make_deal(p1_hand, p2_hand, p3_hand, {}, {}, "awaiting_action", 1, "tiao_3_c" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_c" as TileId))
         local tr2 = engine.apply_action(tr1.deal, engine.declare_chi(2, "tiao_3_c" as TileId, { "tiao_2_a" as TileId, "tiao_4_a" as TileId }))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_peng(3, "tiao_3_c" as TileId))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         -- Peng (p3) wins, not chi (p2)
         assert.are.equal("awaiting_action", tr4.deal.phase as string)
         assert.are.equal(3, tr4.deal.current_player)
         assert.are.equal(1, #tr4.deal.players[3].hand.sets)
         assert.are.equal("peng", tr4.deal.players[3].hand.sets[1].kind as string)
         assert.are.equal(0, #tr4.deal.players[2].hand.sets)
      end)

      it("Open Kong beats Chi on the same discard", function()
         -- p3 has 3 tiao_3 → open kong. p2 (next) tries chi. Kong wins.
         local p2_hand = parse("24t 456w 789w 12w 33b")
         local p3_hand = parse("333t 456b 78b 12b 33w")  -- 3+3+2+2+2 = 12; +1 to make 13
         p3_hand[#p3_hand + 1] = tile("wan_5_a", "wan_5")
         local p1_hand = { tile("tiao_3_d", "tiao_3") }
         local d = make_deal(p1_hand, p2_hand, p3_hand, {}, { tile("bing_9_d", "bing_9") }, "awaiting_action", 1, "tiao_3_d" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_d" as TileId))
         local tr2 = engine.apply_action(tr1.deal, engine.declare_chi(2, "tiao_3_d" as TileId, { "tiao_2_a" as TileId, "tiao_4_a" as TileId }))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_open_kong(3, "tiao_3_d" as TileId))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("awaiting_action", tr4.deal.phase as string)
         assert.are.equal(3, tr4.deal.current_player)
         assert.are.equal(1, #tr4.deal.players[3].hand.sets)
         assert.are.equal("kong", tr4.deal.players[3].hand.sets[1].kind as string)
      end)

      it("nearest-next wins among same-priority Hu claims", function()
         -- Both p2 and p3 declare Hu on p1's discard. p2 (nearest-next) should win.
         local p2_ting = parse("123t 456t 789t 12t 2E")
         local p3_ting: {Tile} = {
            tile("wan_1_a", "wan_1"), tile("wan_1_b", "wan_1"), tile("wan_1_c", "wan_1"),
            tile("wan_2_a", "wan_2"), tile("wan_2_b", "wan_2"), tile("wan_2_c", "wan_2"),
            tile("wan_3_a", "wan_3"), tile("wan_3_b", "wan_3"), tile("wan_3_c", "wan_3"),
            tile("wan_4_a", "wan_4"), tile("wan_4_b", "wan_4"), tile("wan_4_c", "wan_4"),
            tile("tiao_3_b", "tiao_3"),
         }
         local p1_hand = { tile("tiao_3_c", "tiao_3") }
         local d = make_deal(p1_hand, p2_ting, p3_ting, {}, {}, "awaiting_action", 1, "tiao_3_c" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_c" as TileId))
         local tr2 = engine.apply_action(tr1.deal, engine.declare_hu(3, "tiao_3_c" as TileId, false))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_hu(2, "tiao_3_c" as TileId, false))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(2, tr4.deal.deal_result.winner_player_index)
      end)

      it("human Hu beats nearer AI Hu", function()
         -- p2 discards tiao_3. p3 is nearest-next and can Hu, but p1 is human
         -- and also claims Hu, so the human prompt priority wins.
         local p1_ting: {Tile} = {
            tile("tiao_1_a", "tiao_1"), tile("tiao_2_a", "tiao_2"), tile("tiao_3_a", "tiao_3"),
            tile("tiao_4_a", "tiao_4"), tile("tiao_5_a", "tiao_5"), tile("tiao_6_a", "tiao_6"),
            tile("tiao_7_a", "tiao_7"), tile("tiao_8_a", "tiao_8"), tile("tiao_9_a", "tiao_9"),
            tile("tiao_1_b", "tiao_1"), tile("tiao_2_b", "tiao_2"),
            tile("east_a", "east"), tile("east_b", "east"),
         }
         local p3_ting: {Tile} = {
            tile("tiao_1_c", "tiao_1"), tile("tiao_2_c", "tiao_2"), tile("tiao_3_b", "tiao_3"),
            tile("tiao_4_b", "tiao_4"), tile("tiao_5_b", "tiao_5"), tile("tiao_6_b", "tiao_6"),
            tile("tiao_7_b", "tiao_7"), tile("tiao_8_b", "tiao_8"), tile("tiao_9_b", "tiao_9"),
            tile("tiao_1_d", "tiao_1"), tile("tiao_2_d", "tiao_2"),
            tile("east_c", "east"), tile("east_d", "east"),
         }
         local p2_hand = { tile("tiao_3_d", "tiao_3") }
         local d = make_deal(p1_ting, p2_hand, p3_ting, {}, {}, "awaiting_action", 2, "tiao_3_d" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(2, "tiao_3_d" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         local tr2 = engine.apply_action(tr1.deal, engine.declare_hu(3, "tiao_3_d" as TileId, false))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.declare_hu(1, "tiao_3_d" as TileId, false))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(1, tr4.deal.deal_result.winner_player_index)
      end)
   end)

   -- ── Wall exhaustion ───────────────────────────────────────────────────────
   describe("wall exhaustion", function()
      it("draw on empty wall ends the deal", function()
         local d = make_deal({}, {}, {}, {}, {}, "awaiting_draw", 1, "" as TileId, false)
         local tr = engine.apply_action(d, engine.draw(1))
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("deal_over", tr.deal.phase as string)
         assert.is_true(tr.deal.has_deal_result)
         assert.are.equal(-1, tr.deal.deal_result.winner_player_index)
      end)

      it("open kong on empty supplement wall exhausts before kong resolves", function()
         local p1_hand = { tile("tiao_3_d", "tiao_3") }
         local p3_hand = {
            tile("tiao_3_a", "tiao_3"),
            tile("tiao_3_b", "tiao_3"),
            tile("tiao_3_c", "tiao_3"),
         }
         local d = make_deal(p1_hand, {}, p3_hand, {}, {}, "awaiting_action", 1, "tiao_3_d" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_d" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         local tr2 = engine.apply_action(tr1.deal, engine.declare_open_kong(3, "tiao_3_d" as TileId))
         assert.is_true(tr2.ok, tr2.error)
         local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(2))
         assert.is_true(tr3.ok, tr3.error)
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)

         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(-1, tr4.deal.deal_result.winner_player_index)
         assert.are.equal(0, #tr4.deal.players[3].hand.sets)
         assert.are.equal(3, #tr4.deal.players[3].hand.concealed_tiles)
      end)

      it("tile conservation holds across many turns", function()
         local deal = engine.new_deal(rng_mod.from_seed(7))
         local d = deal
         for _ = 1, 10 do
            if (d.phase as string) == "deal_over" then break end
            d = play_safe_turn(d)
            local r = invariants.validate_tile_conservation(d)
            assert.is_true(r.ok, r.details)
         end
      end)
   end)

   -- ── Zi Mo ─────────────────────────────────────────────────────────────────
   describe("zi mo", function()
      it("player 1 wins on a self-drawn completing tile", function()
         -- 13-tile ting: 123t 456t 789t 11w 23w; incoming wan_4_a → Ping Hu + Zi Mo + Men Qian = 3 fan
         local ting = parse("123t 456t 789t 11w 23w")
         local d = make_deal(ting, {}, {}, {}, { tile("wan_4_a", "wan_4") }, "awaiting_draw", 1, "" as TileId, false)

         local tr1 = engine.apply_action(d, engine.draw(1))
         assert.is_true(tr1.ok, tr1.error)

         local tr2 = engine.apply_action(tr1.deal, engine.declare_hu(1, "" as TileId, true))
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("deal_over", tr2.deal.phase as string)
         assert.are.equal(1, tr2.deal.deal_result.winner_player_index)
         assert.is_true(tr2.deal.deal_result.won_by_zi_mo)
         assert.is_true(tr2.deal.deal_result.score_result.valid_hu)
      end)

      it("rejects zi mo when last drawn tile does not complete a valid hu", function()
         local non_ting = parse("123t 456t 789t 12w 23w")
         local d = make_deal(non_ting, {}, {}, {}, { tile("wan_9_a", "wan_9") }, "awaiting_draw", 1, "" as TileId, false)
         local tr1 = engine.apply_action(d, engine.draw(1))
         local tr2 = engine.apply_action(tr1.deal, engine.declare_hu(1, "" as TileId, true))
         assert.is_false(tr2.ok)
      end)
   end)

   -- ── Hu on discard ─────────────────────────────────────────────────────────
   describe("hu on discard", function()
      it("player 2 wins on player 1's discard after others pass", function()
         -- p2 ting: 123t 456t 789t 12t 2E (Hun Yi Se), incoming tiao_3 → 4 fan
         local p2_ting = parse("123t 456t 789t 12t 2E")
         local p1_hand = { tile("tiao_3_b", "tiao_3") }
         local d = make_deal(p1_hand, p2_ting, {}, {}, {}, "awaiting_action", 1, "tiao_3_b" as TileId, true)

         local tr1 = engine.apply_action(d, engine.discard(1, "tiao_3_b" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         local tr2 = engine.apply_action(tr1.deal, engine.declare_hu(2, "tiao_3_b" as TileId, false))
         assert.is_true(tr2.ok, tr2.error)
         -- p3 and p4 pass to close window
         local tr3 = engine.apply_action(tr2.deal, engine.pass_reaction(3))
         local tr4 = engine.apply_action(tr3.deal, engine.pass_reaction(4))
         assert.is_true(tr4.ok, tr4.error)
         assert.are.equal("deal_over", tr4.deal.phase as string)
         assert.are.equal(2, tr4.deal.deal_result.winner_player_index)
         assert.is_false(tr4.deal.deal_result.won_by_zi_mo)
      end)
   end)

   -- ── Concealed Kong ────────────────────────────────────────────────────────
   describe("concealed kong", function()
      it("player declares concealed kong and draws supplement", function()
         local hand14 = parse("1111t 234t 567t 89w 1w 5w")  -- 14 tiles
         local supp = tile("bing_5_a", "bing_5")
         local d = make_deal(hand14, {}, {}, {}, { supp }, "awaiting_action", 1, "wan_5_a" as TileId, true)
         d.players[1].known_wall_tile_ids = { "bing_5_a" as TileId }
         d.players[2].known_wall_tile_ids = { "bing_5_a" as TileId }

         local tr = engine.apply_action(d, engine.declare_concealed_kong(1, "tiao_1" as TileKindId))
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("awaiting_action", tr.deal.phase as string)
         -- 14 - 4 (kong tiles removed) + 1 (supplement) = 11
         assert.are.equal(11, #tr.deal.players[1].hand.concealed_tiles)
         assert.are.equal(1, #tr.deal.players[1].hand.sets)
         assert.are.equal("kong", tr.deal.players[1].hand.sets[1].kind as string)
         assert.are.equal("concealed", tr.deal.players[1].hand.sets[1].visibility as string)
         assert.is_true(tr.deal.last_draw_was_supplement)
         assert.are.equal(0, #tr.deal.players[1].known_wall_tile_ids)
         assert.are.equal(0, #tr.deal.players[2].known_wall_tile_ids)
      end)

      it("empty supplement wall exhausts before concealed kong resolves", function()
         local hand14 = parse("1111t 234t 567t 89w 1w 5w")
         local d = make_deal(hand14, {}, {}, {}, {}, "awaiting_action", 1, "wan_5_a" as TileId, true)

         local tr = engine.apply_action(d, engine.declare_concealed_kong(1, "tiao_1" as TileKindId))
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("deal_over", tr.deal.phase as string)
         assert.are.equal(-1, tr.deal.deal_result.winner_player_index)
         assert.are.equal(0, #tr.deal.players[1].hand.sets)
         assert.are.equal(14, #tr.deal.players[1].hand.concealed_tiles)
      end)
   end)

   -- ── Added Kong + Qiang Gang ──────────────────────────────────────────────
   describe("added kong / qiang gang", function()
      it("added kong resolves when all pass — peng upgrades to kong", function()
         -- p1 has open peng of tiao_5 + the fourth tiao_5 in concealed.
         local p1_concealed = parse("234t 678t 1w 23w 4b")  -- 3+3+1+2+1 = 10 tiles
         p1_concealed[#p1_concealed + 1] = tile("tiao_5_d", "tiao_5")  -- 11; this is the kong tile
         local p1_state: PlayerState = {
            hand = {
               concealed_tiles = p1_concealed,
               sets = {
                  {
                     kind = "peng" as TileSetKind,
                     visibility = "open" as SetVisibility,
                     tiles = { tile("tiao_5_a", "tiao_5"), tile("tiao_5_b", "tiao_5"), tile("tiao_5_c", "tiao_5") },
                     called_from = 4,
                  },
               },
               discards = {},
            },
            opening_trim = {},
            seat_wind = "east" as Wind,
            is_human = true,
            known_wall_tile_ids = {},
         }
         local empty: PlayerState = {
            hand = { concealed_tiles = {}, sets = {}, discards = {} },
            opening_trim = {}, seat_wind = "south" as Wind, is_human = false,
            known_wall_tile_ids = {},
         }
         local d: DealState = {
            players = { p1_state, empty,
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "west" as Wind, is_human = false, known_wall_tile_ids = {} },
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "north" as Wind, is_human = false, known_wall_tile_ids = {} },
            },
            wall = { tiles = { tile("bing_9_d", "bing_9") } },  -- supplement
            phase = "awaiting_action" as DealPhase,
            current_player = 1, dealer = 1, round_wind = "east" as Wind,
            pending_discard = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard = false,
            pending_added_kong = {
               tile_id  = "" as TileId,
               tile     = { tile_id = "" as TileId, kind_id = "" as TileKindId },
               declarer = 0,
            }, has_pending_kong = false,
            rng = rng_mod.from_seed(1),
            deal_result = { winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false },
            has_deal_result = false, reaction_passes = {}, pending_claims = {},
            last_draw_was_supplement = false, last_drawn_tile_id = "tiao_5_d" as TileId, has_last_drawn = true,
            effect_states = {},
            active_boons = {},
         }

         local tr1 = engine.apply_action(d, engine.declare_added_kong(1, "tiao_5_d" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         assert.are.equal("reaction_window", tr1.deal.phase as string)
         assert.is_true(tr1.deal.has_pending_kong)
         assert.are.equal("tiao_5_d", tr1.deal.pending_added_kong.tile.tile_id as string)
         assert.are.equal("tiao_5", tr1.deal.pending_added_kong.tile.kind_id as string)

         local d2 = pass_all(tr1.deal, {2, 3, 4})
         -- After all pass: peng → kong, supplement drawn
         assert.are.equal("awaiting_action", d2.phase as string)
         assert.are.equal(1, d2.current_player)
         assert.are.equal(1, #d2.players[1].hand.sets)
         assert.are.equal("kong", d2.players[1].hand.sets[1].kind as string)
         assert.are.equal(4, #d2.players[1].hand.sets[1].tiles)
         assert.is_true(d2.last_draw_was_supplement)
      end)

      it("empty supplement wall exhausts before added kong upgrade resolves", function()
         local p1_concealed = parse("234t 678t 1w 23w 4b")
         p1_concealed[#p1_concealed + 1] = tile("tiao_5_d", "tiao_5")
         local p1_state: PlayerState = {
            hand = {
               concealed_tiles = p1_concealed,
               sets = {
                  {
                     kind = "peng" as TileSetKind,
                     visibility = "open" as SetVisibility,
                     tiles = { tile("tiao_5_a", "tiao_5"), tile("tiao_5_b", "tiao_5"), tile("tiao_5_c", "tiao_5") },
                     called_from = 4,
                  },
               },
               discards = {},
            },
            opening_trim = {},
            seat_wind = "east" as Wind,
            is_human = true,
            known_wall_tile_ids = {},
         }
         local empty: PlayerState = {
            hand = { concealed_tiles = {}, sets = {}, discards = {} },
            opening_trim = {}, seat_wind = "south" as Wind, is_human = false,
            known_wall_tile_ids = {},
         }
         local d: DealState = {
            players = { p1_state, empty,
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "west" as Wind, is_human = false, known_wall_tile_ids = {} },
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "north" as Wind, is_human = false, known_wall_tile_ids = {} },
            },
            wall = { tiles = {} },
            phase = "awaiting_action" as DealPhase,
            current_player = 1, dealer = 1, round_wind = "east" as Wind,
            pending_discard = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard = false,
            pending_added_kong = {
               tile_id  = "" as TileId,
               tile     = { tile_id = "" as TileId, kind_id = "" as TileKindId },
               declarer = 0,
            }, has_pending_kong = false,
            rng = rng_mod.from_seed(1),
            deal_result = { winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false },
            has_deal_result = false, reaction_passes = {}, pending_claims = {},
            last_draw_was_supplement = false, last_drawn_tile_id = "tiao_5_d" as TileId, has_last_drawn = true,
            effect_states = {},
            active_boons = {},
         }

         local tr1 = engine.apply_action(d, engine.declare_added_kong(1, "tiao_5_d" as TileId))
         assert.is_true(tr1.ok, tr1.error)
         local d2 = pass_all(tr1.deal, {2, 3, 4})

         assert.are.equal("deal_over", d2.phase as string)
         assert.are.equal(-1, d2.deal_result.winner_player_index)
         assert.are.equal("peng", d2.players[1].hand.sets[1].kind as string)
         assert.are.equal(3, #d2.players[1].hand.sets[1].tiles)
         assert.are.equal(11, #d2.players[1].hand.concealed_tiles)
      end)
   end)

   -- ── apply_action rejects actions on ended deal ─────────────────────────────
   describe("post-deal guard", function()
      it("rejects any action after deal_over", function()
         local d = make_deal({}, {}, {}, {}, {}, "awaiting_draw", 1, "" as TileId, false)
         local over = engine.apply_action(d, engine.draw(1))
         assert.is_true(over.ok)
         assert.are.equal("deal_over", over.deal.phase as string)
         local tr2 = engine.apply_action(over.deal, engine.draw(1))
         assert.is_false(tr2.ok)
      end)
   end)

end)
