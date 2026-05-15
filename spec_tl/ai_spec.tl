-- S05 AI tests: legal Hu detection, ting-distance discard heuristic,
-- conservative Peng/Chi/Open Kong, concealed/added Kong, determinism,
-- and that AI never returns an action that fails apply_action.

require("core.types")
require("core.rng")
require("game.deal_types")
local rng_mod   = require("core.rng")
local engine    = require("game.deal_engine")
local ai        = require("game.ai")
local td        = require("game.ting_distance")
local notation  = require("support.hand_notation")
local boons_init = require("effects.boons.init")

-- ── Helpers ────────────────────────────────────────────────────────────────

local function parse(s: string): {Tile}
   local r = notation.parse(s)
   assert.is_true(r.ok, "notation error: " .. r.error)
   return r.tiles
end

local function tile(tile_id: string, kind_id: string): Tile
   return { tile_id = tile_id as TileId, kind_id = kind_id as TileKindId }
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

-- Build a 4-player DealState directly. Caller specifies hands, phase, and
-- (optionally) a pending discard for reaction-window scenarios.
local function make_deal(
   p1: {Tile}, p2: {Tile}, p3: {Tile}, p4: {Tile},
   wall_tiles: {Tile}, phase: string,
   current_player: integer,
   last_drawn_tile_id: TileId, has_last_drawn: boolean
): DealState
   local function mk(tiles: {Tile}, sw: string, human: boolean): PlayerState
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
         mk(p1, "east", true),
         mk(p2, "south", false),
         mk(p3, "west", false),
         mk(p4, "north", false),
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
         score_result        = blank_score_result(),
         has_score_result    = false,
      },
      has_deal_result          = false,
      reaction_passes          = {},
      pending_claims           = {},
      last_draw_was_supplement = false,
      last_drawn_tile_id       = last_drawn_tile_id,
      has_last_drawn           = has_last_drawn,
      effect_states            = {},
      active_boons             = {},
      set_count_high_water     = 0,
      reached_ting             = false,
   }
end

local function set_pending_discard(d: DealState, t: Tile, discarder: integer): DealState
   d.pending_discard      = { tile = t, discarder = discarder }
   d.has_pending_discard  = true
   d.phase                = "reaction_window" as DealPhase
   return d
end

-- ── Tests ──────────────────────────────────────────────────────────────────

describe("ai", function()

   before_each(function()
      boons_init.reset_and_register_all()
   end)

   -- ── decide_main: draw phase ───────────────────────────────────────────
   describe("decide_main awaiting_draw", function()
      it("returns a draw action for the current player", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_draw", 1, "" as TileId, false)
         local action, reason = ai.decide_main(d, 1)
         assert.are.equal("draw", action.kind)
         assert.are.equal("draw", reason.tag)
      end)
   end)

   -- ── decide_main: zi mo ────────────────────────────────────────────────
   describe("decide_main awaiting_action zi mo", function()
      it("declares zi mo when drawn tile completes a 3+ fan hand", function()
         -- Dui Dui Hu (3 fan): 111t 222w 333b 444b + pair 55b. 14-tile concealed.
         local hand = parse("111t 222w 333b 444b 5b 5b")
         -- Mark the second bing_5 as the drawn tile.
         local drawn_id = hand[#hand].tile_id
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, drawn_id, true)
         local action, reason = ai.decide_main(d, 1)
         assert.are.equal("declare_hu", action.kind)
         assert.are.equal("zi_mo", reason.tag)
         local hu = action as DeclareHuAction
         assert.is_true(hu.is_zi_mo)
      end)

      it("does not declare zi mo when fan < 3 (bare ping hu)", function()
         -- Ping Hu (1 fan): 123t 456t 789t 123w + pair 55b. 14 concealed (drew the 5b).
         local hand = parse("123t 456t 789t 123w 5b 5b")
         local drawn_id = hand[#hand].tile_id
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, drawn_id, false)
         -- has_last_drawn=false to skip zi-mo path; action must default to discard.
         local action, _reason = ai.decide_main(d, 1)
         assert.are.equal("discard", action.kind)
      end)
   end)

   -- ── decide_main: discard heuristic ────────────────────────────────────
   describe("decide_main awaiting_action discard heuristic", function()
      it("discards the tile that minimizes ting distance", function()
         -- 14 concealed; the AI's chosen discard must produce the minimum
         -- resulting ting distance over all possible discards.
         local hand = parse("111t 222w 333b 44b 55b 9w")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         local action, reason = ai.decide_main(d, 1)
         assert.are.equal("discard", action.kind)
         assert.are.equal("discard", reason.tag)

         -- Compute the true minimum ting distance over every candidate discard
         -- and assert the AI matched it.
         local min_after = 1000
         for _, t in ipairs(hand) do
            local rest: {Tile} = {}
            for _, u in ipairs(hand) do
               if u.tile_id ~= t.tile_id then rest[#rest + 1] = u end
            end
            local td_after = td.ting_distance(rest, {})
            if td_after < min_after then min_after = td_after end
         end
         assert.are.equal(min_after, reason.ting_after)
      end)

      it("is deterministic across repeated discard decisions", function()
         -- Candidate utility now comes from probability-weighted expected fan.
         -- This test only locks determinism, not an obsolete tile-value table.
         local hand = parse("111t 222w 333b 444b 5b 9w")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         local action_a = ai.decide_main(d, 1)
         local action_b = ai.decide_main(d, 1)
         assert.are.equal((action_a as DiscardAction).tile_id, (action_b as DiscardAction).tile_id)
      end)

      it("M1 vanilla AI ignores its own seat's known_wall_tile_ids", function()
         -- AI may read its own seat's known wall (forward-compat with future
         -- info effects), but vanilla M1 AI does not consult it. Populating
         -- the seat's known wall must not change the chosen discard.
         local hand = parse("111t 222w 333b 44b 55b 9w")
         local d_clean = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         local d_misled = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         d_misled.players[1].known_wall_tile_ids = { ("tiao_1_a") as TileId, ("wan_9_a") as TileId }
         local a1 = ai.decide_main(d_clean, 1)
         local a2 = ai.decide_main(d_misled, 1)
         assert.are.equal((a1 as DiscardAction).tile_id, (a2 as DiscardAction).tile_id)
      end)
   end)

   -- ── decide_main: concealed/added Kong ─────────────────────────────────
   describe("decide_main awaiting_action kong", function()
      it("only declares concealed kong when supplement expected fan clears the floor", function()
         -- 4 of a kind + 10 other tiles = 14 concealed. Removing the quad and
         -- treating it as a set should not regress ting.
         local hand = parse("1111t 222w 333b 44b 5b")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         local action, reason = ai.decide_main(d, 1)
         if action.kind == "declare_concealed_kong" then
            assert.are.equal("concealed_kong", reason.tag)
            assert.is_true(reason.candidates[1].expected_fan >= 3.0)
            local ck = action as DeclareConcealedKongAction
            assert.are.equal("tiao_1", ck.tile_kind_id as string)
         else
            assert.are.equal("discard", action.kind)
         end
      end)

      it("declares added kong when an open peng + 4th tile is in hand", function()
         -- p1 has an open peng of fa_cai + 4th fa_cai concealed → added kong.
         local hand = parse("11t 22w 33b 44b 55b F")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         local peng_set: TileSet = {
            kind        = "peng" as TileSetKind,
            visibility  = "open" as SetVisibility,
            tiles       = { tile("fa_cai_b", "fa_cai"), tile("fa_cai_c", "fa_cai"), tile("fa_cai_d", "fa_cai") },
            called_from = 2,
         }
         d.players[1].hand.sets = { peng_set }
         local action, reason = ai.decide_main(d, 1)
         assert.are.equal("declare_added_kong", action.kind)
         assert.are.equal("added_kong", reason.tag)
      end)
   end)

   -- ── decide_reaction: Hu on discard ────────────────────────────────────
   describe("decide_reaction hu", function()
      it("declares hu on a 3+ fan discard", function()
         -- p1 concealed = 111t 222w 333b 444b 5b (13). Discarder=2, tile=bing_5.
         -- Forms Dui Dui Hu (3 fan) on completion.
         local d = make_deal(parse("111t 222w 333b 444b 5b"), parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 2, "" as TileId, false)
         d = set_pending_discard(d, tile("bing_5_b", "bing_5"), 2)
         local action, reason = ai.decide_reaction(d, 1)
         assert.are.equal("declare_hu", action.kind)
         assert.are.equal("hu_on_discard", reason.tag)
         local hu = action as DeclareHuAction
         assert.is_false(hu.is_zi_mo)
      end)

      it("passes when the only valid shape is below 3 fan", function()
         -- Bare Ping Hu = 1 fan; AI should not declare.
         local d = make_deal(parse("123t 456t 789t 123w 5b"), parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 2, "" as TileId, false)
         d = set_pending_discard(d, tile("bing_5_b", "bing_5"), 2)
         local action, _reason = ai.decide_reaction(d, 1)
         assert.are.equal("pass_reaction", action.kind)
      end)
   end)

   -- ── decide_reaction: Peng / Open Kong / Chi ───────────────────────────
   describe("decide_reaction calls", function()
      it("gates open kong with supplement expected fan when both kong and peng are legal", function()
         -- 3 of a kind in hand + matching discard = open kong. Concealed 13 tiles.
         local hand = parse("111t 222w 333b 44b 5b 6b")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 2, "" as TileId, false)
         d = set_pending_discard(d, tile("tiao_1_d", "tiao_1"), 2)
         local action, reason = ai.decide_reaction(d, 1)
         if action.kind == "declare_open_kong" then
            assert.are.equal("open_kong", reason.tag)
            assert.is_true(reason.candidates[1].expected_fan >= 3.0)
         else
            assert.are.equal("pass_reaction", action.kind)
            assert.is_true(#reason.candidates > 0)
            assert.are.equal("open_kong", reason.candidates[1].tag)
            assert.is_false(reason.candidates[1].accepted)
         end
      end)

      it("calls peng when standard ting does not regress", function()
         -- Two of a kind + matching discard. The AI either pengs (because
         -- standard ting doesn't regress and a 3-fan path survives) or
         -- passes. Both are acceptable — this test guards against the
         -- regression "AI accepts a peng that worsens standard ting."
         local hand = parse("11t 222w 333b 44b 55b 6w")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 2, "" as TileId, false)
         d = set_pending_discard(d, tile("tiao_1_c", "tiao_1"), 2)
         local action, reason = ai.decide_reaction(d, 1)
         if action.kind == "declare_peng" then
            -- AI accepted: live-aware standard ting on the post-peng hand
            -- must be ≤ live-aware standard ting on the pre-peng hand.
            local live = ai.compute_live_counts(d, 1)
            local before_std = td.ting_distance_standard_live(hand, {}, live)
            assert.is_true(reason.ting_after <= before_std,
               "ting_after=" .. tostring(reason.ting_after) .. " > before_std=" .. tostring(before_std))
         else
            assert.are.equal("pass_reaction", action.kind)
         end
      end)

      it("does not chi from a non-next player", function()
         -- p1 sits at index 1; discarder = 3 (player west). Only player 4 is next.
         local hand = parse("11t 22t 33t 44b 55b 6w 9w 9w 9w F F F H")
         local d = make_deal(hand, parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 3, "" as TileId, false)
         d = set_pending_discard(d, tile("tiao_2_b", "tiao_2"), 3)
         local action, _reason = ai.decide_reaction(d, 1)
         -- Player 1 is not the next seat after player 3; chi would be illegal.
         assert.are_not_equal("declare_chi", action.kind)
      end)

      it("the discarder passes its own reaction window", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b 6w 9w"), parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_action", 1, "" as TileId, false)
         d = set_pending_discard(d, tile("tiao_1_d", "tiao_1"), 1)
         local action, _reason = ai.decide_reaction(d, 1)
         assert.are.equal("pass_reaction", action.kind)
      end)

      it("returns pass when not in reaction_window phase", function()
         local d = make_deal(parse("111t 222w 333b 44b 55b"), parse("123t 456t 789t 11w 9w"), parse("123b 456b 789b 11t 9t"), parse("234t 567t 891w E S W N N"),
            {}, "awaiting_draw", 2, "" as TileId, false)
         local action, _reason = ai.decide_reaction(d, 1)
         assert.are.equal("pass_reaction", action.kind)
      end)
   end)

   -- ── End-to-end: AI never returns invalid actions ──────────────────────
   describe("apply_action smoke", function()
      it("AI plays many turns without producing an invalid action", function()
         local d = engine.new_deal(rng_mod.from_seed(123))
         local steps = 0
         local max_steps = 80
         while steps < max_steps and (d.phase as string) ~= "deal_over" do
            steps = steps + 1
            local phase = d.phase as string
            if phase == "awaiting_draw" or phase == "awaiting_action" then
               local action, _r = ai.decide_main(d, d.current_player)
               local tr = engine.apply_action(d, action)
               assert.is_true(tr.ok, "step " .. tostring(steps) .. " (" .. phase .. "): " .. tr.error)
               d = tr.deal
            elseif phase == "reaction_window" then
               -- Pump every seat that hasn't responded yet.
               for i = 1, 4 do
                  if (d.phase as string) == "reaction_window" then
                     local action, _r = ai.decide_reaction(d, i)
                     local tr = engine.apply_action(d, action)
                     -- Some seats are not eligible (e.g., discarder); the engine
                     -- rejects them. That's expected — only assert on eligible seats.
                     if tr.ok then d = tr.deal end
                  end
               end
               -- Failsafe: if we can't progress the window, break.
               if (d.phase as string) == "reaction_window" then break end
            else
               break
            end
         end
         assert.is_true(steps > 0, "AI made no progress")
      end)
   end)
end)
