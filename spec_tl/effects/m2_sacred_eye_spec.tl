-- M2-S04 sacred_eye: ting-activated honor-pair detection (Plan C). Also
-- covers the new per-seat last_drawn_tile_id PlayerState field that
-- engine.handle_draw + draw_supplement populate. UI rendering of opp
-- draws under sacred_eye's flag is deferred.

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

local function make_deal(p1_concealed: {Tile}, p1_sets: {TileSet}, wall_tiles: {Tile}): DealState
   local function mk(concealed: {Tile}, sets: {TileSet}, sw: string, human: boolean): PlayerState
      return {
         hand                       = { concealed_tiles = concealed, sets = sets, discards = {} },
         opening_trim               = {},
         seat_wind                  = sw as Wind,
         is_human                   = human,
         known_wall_tile_ids        = {},
         concealed_pung_kinds_seen  = {},
         turn_extra_discards_owed   = 0,
         last_drawn_tile_id         = "" as TileId,
      }
   end
   return {
      players = {
         mk(p1_concealed, p1_sets, "east",  true),
         mk({}, {}, "south", false),
         mk({}, {}, "west",  false),
         mk({}, {}, "north", false),
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

local function fire_ting(deal: DealState, actives: {ActiveBoon})
   local ev: TingReachedEvent = { event_name = "on_ting_reached" }
   registry.emit(deal, actives, 1, ev as EventData)
end

-- ── sacred_eye latch ─────────────────────────────────────────────────────

describe("M2 boon: sacred_eye", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("activates on ting where the winning pair is honors", function()
      -- 123t 456t 789t 111w + east → 13 tiles, waiting on east to pair.
      local concealed = parse("123t 456t 789t 111w E")
      local deal = make_deal(concealed, {}, {})
      local active = context.new_active("sacred_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])
   end)

   it("does NOT activate when no wait-shape pairs on an honor", function()
      -- 123t 456t 789t 11w + 5b → waiting on bing_5 to pair. Pair kind
      -- is bing_5 (suited), not honor. Should not activate.
      local concealed = parse("123t 456t 789t 11w 5b")
      local deal = make_deal(concealed, {}, {})
      local active = context.new_active("sacred_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_falsy(active.flags["active"])
   end)

   it("does NOT activate before ting (latch starts disabled)", function()
      local deal = make_deal({}, {}, {})
      local active = context.new_active("sacred_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      assert.is_falsy(active.flags["active"])
   end)
end)

-- ── PlayerState.last_drawn_tile_id is set per-seat on draw ────────────────

describe("engine: per-seat last_drawn_tile_id", function()
   it("populates the drawn seat's last_drawn_tile_id on wall draw", function()
      local deal = engine.new_deal(rng_mod.from_seed(42))
      assert.are.equal("" as TileId, deal.players[1].last_drawn_tile_id)

      local r = engine.apply_action(deal, engine.draw(1))
      assert.is_true(r.ok, r.error)
      -- Seat 1's per-seat field is set; others remain empty.
      assert.is_true((r.deal.players[1].last_drawn_tile_id as string) ~= "")
      assert.are.equal("" as TileId, r.deal.players[2].last_drawn_tile_id)
      assert.are.equal("" as TileId, r.deal.players[3].last_drawn_tile_id)
      assert.are.equal("" as TileId, r.deal.players[4].last_drawn_tile_id)
   end)

   it("persists across other seats' draws (per-seat, not global)", function()
      local deal = engine.new_deal(rng_mod.from_seed(7))
      -- Play one safe turn to advance the deal: seat 1 draws + discards,
      -- everyone passes; seat 2's draw comes next.
      local d = engine.apply_action(deal, engine.draw(1)).deal
      local seat1_tile = d.players[1].last_drawn_tile_id
      assert.is_true((seat1_tile as string) ~= "")

      local first_in_hand = d.players[1].hand.concealed_tiles[1]
      d = engine.apply_action(d, engine.discard(1, first_in_hand.tile_id)).deal
      for i = 2, 4 do d = engine.apply_action(d, engine.pass_reaction(i)).deal end
      -- Now seat 2 to draw.
      d = engine.apply_action(d, engine.draw(2)).deal
      -- Seat 2's per-seat field set; seat 1's value preserved.
      assert.is_true((d.players[2].last_drawn_tile_id as string) ~= "")
      assert.are.equal(seat1_tile, d.players[1].last_drawn_tile_id)
   end)
end)
