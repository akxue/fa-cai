-- S03 deal engine tests: phase transitions, tile conservation, Hu, Kong, wall exhaustion.

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
-- then all other players pass. Returns final DealState.
local function play_safe_turn(deal: DealState): DealState
   local cp = deal.current_player
   local tr1 = engine.apply_action(deal, { kind = "draw", player_index = cp } as DrawAction)
   assert.is_true(tr1.ok, "draw failed: " .. tr1.error)
   local first = tr1.deal.players[cp].hand.concealed_tiles[1]
   local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = cp, tile_id = first.tile_id } as DiscardAction)
   assert.is_true(tr2.ok, "discard failed: " .. tr2.error)
   -- All other players pass
   local d = tr2.deal
   for i = 1, 4 do
      if i ~= cp then
         local tr = engine.apply_action(d, { kind = "pass_reaction", player_index = i } as PassReactionAction)
         assert.is_true(tr.ok, "pass failed: " .. tr.error)
         d = tr.deal
         if (d.phase as string) == "awaiting_draw" then break end
      end
   end
   return d
end

-- Creates a minimal DealState for Hu scenario testing (tile conservation not guaranteed).
-- player1_tiles: 13-tile ting hand for player 1.
-- wall_top: the tile at the front of the wall (player 1 will draw this).
local function make_hu_scenario(player1_tiles: {Tile}, wall_top: Tile): DealState
   return {
      players = {
         {
            hand         = { concealed_tiles = player1_tiles, sets = {}, discards = {} },
            opening_trim = {},
            seat_wind    = "east" as Wind,
            is_human     = true,
         },
         {
            hand         = { concealed_tiles = {}, sets = {}, discards = {} },
            opening_trim = {},
            seat_wind    = "south" as Wind,
            is_human     = false,
         },
         {
            hand         = { concealed_tiles = {}, sets = {}, discards = {} },
            opening_trim = {},
            seat_wind    = "west" as Wind,
            is_human     = false,
         },
         {
            hand         = { concealed_tiles = {}, sets = {}, discards = {} },
            opening_trim = {},
            seat_wind    = "north" as Wind,
            is_human     = false,
         },
      },
      wall                     = { tiles = { wall_top } },
      phase                    = "awaiting_draw" as DealPhase,
      current_player           = 1,
      dealer                   = 1,
      round_wind               = "east" as Wind,
      pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
      has_pending_discard      = false,
      pending_added_kong       = { tile_id = "" as TileId, declarer = 0 },
      has_pending_kong         = false,
      known_wall_tile_ids      = {},
      rng                      = rng_mod.from_seed(1),
      deal_result              = {
         winner_player_index = 0,
         won_by_zi_mo        = false,
         score_result        = {
            win_shape_kind = "" as WinShapeKind,
            reasons        = {},
            total_fan      = 0,
            is_limit       = false,
            rating         = "" as Rating,
            valid_hu       = false,
         },
         has_score_result    = false,
      },
      has_deal_result          = false,
      reaction_passes          = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = "" as TileId,
      has_last_drawn           = false,
   }
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
         local tr = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("awaiting_action", tr.deal.phase as string)
         assert.are.equal(14, #tr.deal.players[1].hand.concealed_tiles)
         assert.are.equal(83, #tr.deal.wall.tiles)
      end)

      it("rejects draw by wrong player", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr = engine.apply_action(deal, { kind = "draw", player_index = 2 } as DrawAction)
         assert.is_false(tr.ok)
      end)

      it("rejects draw in awaiting_action phase", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local tr2 = engine.apply_action(tr1.deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_false(tr2.ok)
      end)

      it("tile conservation holds after draw", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(tr.ok, tr.error)
         local r = invariants.validate_tile_conservation(tr.deal)
         assert.is_true(r.ok, r.details)
      end)
   end)

   -- ── discard ───────────────────────────────────────────────────────────────
   describe("discard", function()
      it("player 1 draws then discards, opens reaction window", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = first.tile_id } as DiscardAction)
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("reaction_window", tr2.deal.phase as string)
         assert.is_true(tr2.deal.has_pending_discard)
         assert.are.equal(13, #tr2.deal.players[1].hand.concealed_tiles)
      end)

      it("rejects discard of tile not in hand", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = "fa_cai_z" as TileId } as DiscardAction)
         assert.is_false(tr2.ok)
      end)

      it("tile conservation holds after discard", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = first.tile_id } as DiscardAction)
         local r = invariants.validate_tile_conservation(tr2.deal)
         assert.is_true(r.ok, r.details)
      end)
   end)

   -- ── reaction window: all pass ─────────────────────────────────────────────
   describe("reaction window: all pass", function()
      it("resolves to player 2 awaiting_draw after all three pass", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = first.tile_id } as DiscardAction)

         local tr3 = engine.apply_action(tr2.deal, { kind = "pass_reaction", player_index = 2 } as PassReactionAction)
         assert.is_true(tr3.ok, tr3.error)
         assert.are.equal("reaction_window", tr3.deal.phase as string)   -- still open

         local tr4 = engine.apply_action(tr3.deal, { kind = "pass_reaction", player_index = 3 } as PassReactionAction)
         assert.is_true(tr4.ok, tr4.error)
         assert.are.equal("reaction_window", tr4.deal.phase as string)   -- still open

         local tr5 = engine.apply_action(tr4.deal, { kind = "pass_reaction", player_index = 4 } as PassReactionAction)
         assert.is_true(tr5.ok, tr5.error)
         assert.are.equal("awaiting_draw", tr5.deal.phase as string)
         assert.are.equal(2, tr5.deal.current_player)
         assert.are.equal(1, #tr5.deal.players[1].hand.discards)
         assert.is_false(tr5.deal.has_pending_discard)
      end)

      it("tile conservation holds after full turn cycle", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = first.tile_id } as DiscardAction)
         local tr3 = engine.apply_action(tr2.deal, { kind = "pass_reaction", player_index = 2 } as PassReactionAction)
         local tr4 = engine.apply_action(tr3.deal, { kind = "pass_reaction", player_index = 3 } as PassReactionAction)
         local tr5 = engine.apply_action(tr4.deal, { kind = "pass_reaction", player_index = 4 } as PassReactionAction)
         local r = invariants.validate_tile_conservation(tr5.deal)
         assert.is_true(r.ok, r.details)
      end)

      it("rejects double-pass by same player", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         local first = tr1.deal.players[1].hand.concealed_tiles[1]
         local tr2 = engine.apply_action(tr1.deal, { kind = "discard", player_index = 1, tile_id = first.tile_id } as DiscardAction)
         local tr3 = engine.apply_action(tr2.deal, { kind = "pass_reaction", player_index = 2 } as PassReactionAction)
         local tr4 = engine.apply_action(tr3.deal, { kind = "pass_reaction", player_index = 2 } as PassReactionAction)
         assert.is_false(tr4.ok)
      end)

      it("turn 4 wraps back to player 1", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         -- Play 3 safe turns (players 1, 2, 3) so player 4 is current
         local d = deal
         for _ = 1, 3 do d = play_safe_turn(d) end
         assert.are.equal(4, d.current_player)
         -- Play player 4's turn — next should wrap to player 1
         d = play_safe_turn(d)
         assert.are.equal(1, d.current_player)
      end)
   end)

   -- ── Peng ─────────────────────────────────────────────────────────────────
   describe("peng", function()
      it("player 2 pengs a discard", function()
         -- Give player 2 two matching tiles and player 1 a third to discard.
         -- We'll use tiles from a parsed hand.
         local p2_hand = parse("11t 234t 567t 89t")    -- 13 tiles; has pair of tiao_1
         local p1_discard_tile: Tile = { tile_id = "tiao_1_c" as TileId, kind_id = "tiao_1" as TileKindId }
         local d: DealState = {
            players = {
               {
                  hand         = { concealed_tiles = { p1_discard_tile }, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "east" as Wind,
                  is_human     = true,
               },
               {
                  hand         = { concealed_tiles = p2_hand, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "south" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "west" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "north" as Wind,
                  is_human     = false,
               },
            },
            wall                     = { tiles = {} },
            phase                    = "awaiting_action" as DealPhase,
            current_player           = 1,
            dealer                   = 1,
            round_wind               = "east" as Wind,
            pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard      = false,
            pending_added_kong       = { tile_id = "" as TileId, declarer = 0 },
            has_pending_kong         = false,
            known_wall_tile_ids      = {},
            rng                      = rng_mod.from_seed(1),
            deal_result              = {
               winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false,
            },
            has_deal_result          = false,
            reaction_passes          = {},
            last_draw_was_supplement = false,
            last_drawn_tile_id       = "" as TileId,
            has_last_drawn           = true,  -- p1 already has their 1 tile as if drawn
         }
         -- p1 discards tiao_1_c
         local tr1 = engine.apply_action(d, { kind = "discard", player_index = 1, tile_id = "tiao_1_c" as TileId } as DiscardAction)
         assert.is_true(tr1.ok, tr1.error)
         -- p2 pengs
         local tr2 = engine.apply_action(tr1.deal, { kind = "declare_peng", player_index = 2, tile_id = "tiao_1_c" as TileId } as DeclarePengAction)
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("awaiting_action", tr2.deal.phase as string)
         assert.are.equal(2, tr2.deal.current_player)
         assert.are.equal(1, #tr2.deal.players[2].hand.sets)
         assert.are.equal("peng", tr2.deal.players[2].hand.sets[1].kind as string)
         assert.are.equal(3, #tr2.deal.players[2].hand.sets[1].tiles)
      end)
   end)

   -- ── Wall exhaustion ───────────────────────────────────────────────────────
   describe("wall exhaustion", function()
      it("draw on empty wall ends the deal", function()
         -- Construct a deal with an empty wall directly.
         local d: DealState = {
            players = {
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "east" as Wind,
                  is_human     = true,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "south" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "west" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "north" as Wind,
                  is_human     = false,
               },
            },
            wall                     = { tiles = {} },   -- empty wall
            phase                    = "awaiting_draw" as DealPhase,
            current_player           = 1,
            dealer                   = 1,
            round_wind               = "east" as Wind,
            pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard      = false,
            pending_added_kong       = { tile_id = "" as TileId, declarer = 0 },
            has_pending_kong         = false,
            known_wall_tile_ids      = {},
            rng                      = rng_mod.from_seed(1),
            deal_result              = {
               winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false,
            },
            has_deal_result          = false,
            reaction_passes          = {},
            last_draw_was_supplement = false,
            last_drawn_tile_id       = "" as TileId,
            has_last_drawn           = false,
         }
         local tr = engine.apply_action(d, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("deal_over", tr.deal.phase as string)
         assert.is_true(tr.deal.has_deal_result)
         assert.are.equal(-1, tr.deal.deal_result.winner_player_index)
      end)

      it("tile conservation holds across many turns until wall nearly empty", function()
         local deal = engine.new_deal(rng_mod.from_seed(7))
         local d = deal
         -- Play 10 safe turns and verify conservation after each
         for _ = 1, 10 do
            if (d.phase as string) == "deal_over" then break end
            d = play_safe_turn(d)
            local r = invariants.validate_tile_conservation(d)
            assert.is_true(r.ok, r.details)
         end
      end)
   end)

   -- ── Zi Mo (self-draw win) ─────────────────────────────────────────────────
   describe("zi mo", function()
      it("player 1 wins on a self-drawn completing tile", function()
         -- Ting hand: 123t 456t 789t 11w 23w (13 tiles)
         -- Incoming: wan_4_a → completes 234w chi; pair 11w → standard shape
         -- Score: Ping Hu (+1) + Zi Mo (+1) + Men Qian (+1) = 3 fan → valid hu
         local ting_hand = parse("123t 456t 789t 11w 23w")
         local winning_tile: Tile = { tile_id = "wan_4_a" as TileId, kind_id = "wan_4" as TileKindId }
         local deal = make_hu_scenario(ting_hand, winning_tile)

         -- Draw the winning tile
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(tr1.ok, tr1.error)
         assert.are.equal("awaiting_action", tr1.deal.phase as string)

         -- Declare Zi Mo
         local tr2 = engine.apply_action(tr1.deal, {
            kind             = "declare_hu",
            player_index     = 1,
            incoming_tile_id = "" as TileId,
            is_zi_mo         = true,
         } as DeclareHuAction)
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("deal_over", tr2.deal.phase as string)
         assert.is_true(tr2.deal.has_deal_result)
         assert.are.equal(1, tr2.deal.deal_result.winner_player_index)
         assert.is_true(tr2.deal.deal_result.won_by_zi_mo)
         assert.is_true(tr2.deal.deal_result.has_score_result)
         assert.is_true(tr2.deal.deal_result.score_result.valid_hu)
      end)

      it("rejects zi mo when last drawn tile does not complete a valid hu", function()
         -- Incomplete hand: 123t 456t 789t 12w 23w (13 tiles) — not in ting on wan_4
         -- With wan_9_a incoming, this won't be a valid hu
         local non_ting = parse("123t 456t 789t 12w 23w")
         local bad_tile: Tile = { tile_id = "wan_9_a" as TileId, kind_id = "wan_9" as TileKindId }
         local deal = make_hu_scenario(non_ting, bad_tile)
         local tr1 = engine.apply_action(deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(tr1.ok, tr1.error)
         local tr2 = engine.apply_action(tr1.deal, {
            kind             = "declare_hu",
            player_index     = 1,
            incoming_tile_id = "" as TileId,
            is_zi_mo         = true,
         } as DeclareHuAction)
         assert.is_false(tr2.ok)
      end)
   end)

   -- ── Hu on discard ─────────────────────────────────────────────────────────
   describe("hu on discard", function()
      it("player 2 wins on player 1's discard", function()
         -- Player 2 ting hand: 123t 456t 789t 12t 2E — ting on tiao_3 (Hun Yi Se).
         -- All tiles are tiao + east honors. Incoming tiao_3 forms 4 chi + east pair.
         -- Score: Hun Yi Se (+3) + Men Qian (+1) = 4 fan → valid hu without zi mo.
         local p2_ting = parse("123t 456t 789t 12t 2E")
         local p1_tile: Tile = { tile_id = "tiao_3_b" as TileId, kind_id = "tiao_3" as TileKindId }

         local d: DealState = {
            players = {
               {
                  hand         = { concealed_tiles = { p1_tile }, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "east" as Wind,
                  is_human     = true,
               },
               {
                  hand         = { concealed_tiles = p2_ting, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "south" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "west" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "north" as Wind,
                  is_human     = false,
               },
            },
            wall                     = { tiles = {} },
            phase                    = "awaiting_action" as DealPhase,
            current_player           = 1,
            dealer                   = 1,
            round_wind               = "east" as Wind,
            pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard      = false,
            pending_added_kong       = { tile_id = "" as TileId, declarer = 0 },
            has_pending_kong         = false,
            known_wall_tile_ids      = {},
            rng                      = rng_mod.from_seed(1),
            deal_result              = {
               winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false,
            },
            has_deal_result          = false,
            reaction_passes          = {},
            last_draw_was_supplement = false,
            last_drawn_tile_id       = p1_tile.tile_id,
            has_last_drawn           = true,
         }
         -- p1 discards wan_4_a
         local tr1 = engine.apply_action(d, { kind = "discard", player_index = 1, tile_id = p1_tile.tile_id } as DiscardAction)
         assert.is_true(tr1.ok, tr1.error)
         -- p2 declares hu
         local tr2 = engine.apply_action(tr1.deal, {
            kind             = "declare_hu",
            player_index     = 2,
            incoming_tile_id = p1_tile.tile_id,
            is_zi_mo         = false,
         } as DeclareHuAction)
         assert.is_true(tr2.ok, tr2.error)
         assert.are.equal("deal_over", tr2.deal.phase as string)
         assert.are.equal(2, tr2.deal.deal_result.winner_player_index)
         assert.is_false(tr2.deal.deal_result.won_by_zi_mo)
         assert.is_true(tr2.deal.deal_result.score_result.valid_hu)
      end)
   end)

   -- ── Concealed Kong ────────────────────────────────────────────────────────
   describe("concealed kong", function()
      it("player declares concealed kong and draws supplement", function()
         -- Player 1 has 14 concealed tiles (in awaiting_action after a draw).
         -- 4 tiao_1 for the kong + 10 other tiles = 14.
         local hand14 = parse("1111t 234t 567t 89w 1w 5w")  -- 4+3+3+2+1+1 = 14
         local supp_tile: Tile = { tile_id = "bing_5_a" as TileId, kind_id = "bing_5" as TileKindId }
         local extra: Tile = hand14[14]   -- last tile is the "just drew" tile

         local d: DealState = {
            players = {
               {
                  hand         = { concealed_tiles = hand14, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "east" as Wind,
                  is_human     = true,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "south" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "west" as Wind,
                  is_human     = false,
               },
               {
                  hand         = { concealed_tiles = {}, sets = {}, discards = {} },
                  opening_trim = {},
                  seat_wind    = "north" as Wind,
                  is_human     = false,
               },
            },
            wall                     = { tiles = { supp_tile } },
            phase                    = "awaiting_action" as DealPhase,
            current_player           = 1,
            dealer                   = 1,
            round_wind               = "east" as Wind,
            pending_discard          = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard      = false,
            pending_added_kong       = { tile_id = "" as TileId, declarer = 0 },
            has_pending_kong         = false,
            known_wall_tile_ids      = {},
            rng                      = rng_mod.from_seed(1),
            deal_result              = {
               winner_player_index = 0, won_by_zi_mo = false,
               score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false },
               has_score_result = false,
            },
            has_deal_result          = false,
            reaction_passes          = {},
            last_draw_was_supplement = false,
            last_drawn_tile_id       = extra.tile_id,
            has_last_drawn           = true,
         }
         local tr = engine.apply_action(d, { kind = "declare_concealed_kong", player_index = 1, tile_kind_id = "tiao_1" as TileKindId } as DeclareConcealedKongAction)
         assert.is_true(tr.ok, tr.error)
         assert.are.equal("awaiting_action", tr.deal.phase as string)
         -- Kong in sets, hand shrank by 4 then gained 1 supplement = net -3
         assert.are.equal(11, #tr.deal.players[1].hand.concealed_tiles)  -- 14-4+1 = 11
         assert.are.equal(1, #tr.deal.players[1].hand.sets)
         assert.are.equal("kong", tr.deal.players[1].hand.sets[1].kind as string)
         assert.are.equal("concealed", tr.deal.players[1].hand.sets[1].visibility as string)
         assert.is_true(tr.deal.last_draw_was_supplement)
      end)
   end)

   -- ── apply_action rejects actions on ended deal ─────────────────────────────
   describe("post-deal guard", function()
      it("rejects any action after deal_over", function()
         local deal = engine.new_deal(rng_mod.from_seed(42))
         -- Force wall exhaustion
         local d: DealState = {
            players = {
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "east" as Wind, is_human = true },
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "south" as Wind, is_human = false },
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "west" as Wind, is_human = false },
               { hand = { concealed_tiles = {}, sets = {}, discards = {} }, opening_trim = {}, seat_wind = "north" as Wind, is_human = false },
            },
            wall = { tiles = {} },
            phase = "awaiting_draw" as DealPhase,
            current_player = 1, dealer = 1, round_wind = "east" as Wind,
            pending_discard = { tile = { tile_id = "" as TileId, kind_id = "" as TileKindId }, discarder = 0 },
            has_pending_discard = false,
            pending_added_kong = { tile_id = "" as TileId, declarer = 0 },
            has_pending_kong = false,
            known_wall_tile_ids = {},
            rng = rng_mod.from_seed(1),
            deal_result = { winner_player_index = 0, won_by_zi_mo = false, score_result = { win_shape_kind="" as WinShapeKind, reasons={}, total_fan=0, is_limit=false, rating=""as Rating, valid_hu=false }, has_score_result = false },
            has_deal_result = false, reaction_passes = {},
            last_draw_was_supplement = false, last_drawn_tile_id = "" as TileId, has_last_drawn = false,
         }
         local over = engine.apply_action(d, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_true(over.ok)
         assert.are.equal("deal_over", over.deal.phase as string)
         -- Any further action should fail
         local tr2 = engine.apply_action(over.deal, { kind = "draw", player_index = 1 } as DrawAction)
         assert.is_false(tr2.ok)
      end)
   end)

end)
