-- M2-S04 counter-pattern boon tests: honor_sense (every-3rd opponent
-- honor discard → peek 2) and dragon_pulse (every dragon set you form →
-- 1 mulligan + 1 peek token). Drives the boons through registry.emit
-- with hand-built deal scaffolding.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
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

local function make_deal_with_wall(wall_tiles: {Tile}): DealState
   local function mk(sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = {}, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
         concealed_pung_kinds_seen = {},
      }
   end
   return {
      players = { mk("east", true), mk("south", false), mk("west", false), mk("north", false) },
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

local function fire_opp_honor_discard(deal: DealState, actives: {ActiveBoon}, kind: string)
   local ev: OpponentTilePropertyEvent = {
      event_name     = "on_opponent_honor_discarded",
      opponent_index = 2,
      tile           = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

local function fire_call(deal: DealState, actives: {ActiveBoon}, event_name: string, kind_id: string, set_kind: string)
   local tile_set: TileSet = {
      kind        = set_kind as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = { tile(kind_id .. "_a", kind_id), tile(kind_id .. "_b", kind_id), tile(kind_id .. "_c", kind_id) },
      called_from = 2,
   }
   local ev: CallEvent = {
      event_name    = event_name as EventName,
      tile_set      = tile_set,
      source_player = 2,
      kong_kind     = (event_name == "on_kong" and "open") or "",
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

-- ── honor_sense ───────────────────────────────────────────────────────────

describe("M2 boon: honor_sense", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("does nothing on the 1st or 2nd opponent honor discard", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}})
      local deal = make_deal_with_wall(wall)
      local active = context.new_active("honor_sense", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_opp_honor_discard(deal, deal.active_boons, "east")
      fire_opp_honor_discard(deal, deal.active_boons, "south")
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
      assert.are.equal(2, active.counters["opp_honor_discards"])
   end)

   it("peeks 2 wall tiles on the 3rd opponent honor discard", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}})
      local deal = make_deal_with_wall(wall)
      local active = context.new_active("honor_sense", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_opp_honor_discard(deal, deal.active_boons, "east")
      fire_opp_honor_discard(deal, deal.active_boons, "south")
      fire_opp_honor_discard(deal, deal.active_boons, "west")
      local known = deal.players[1].known_wall_tile_ids
      assert.are.equal(2, #known)
      assert.are.equal("tiao_5_a", known[1] as string)
      assert.are.equal("tiao_6_a", known[2] as string)
   end)

   it("triggers again at the 6th opponent honor discard", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}, {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}})
      local deal = make_deal_with_wall(wall)
      local active = context.new_active("honor_sense", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for i = 1, 6 do
         fire_opp_honor_discard(deal, deal.active_boons, "east")
      end
      -- 3rd fire and 6th fire each peek 2 tiles. Dedupe means the same
      -- wall front (tiao_5_a + tiao_6_a) only contributes once total
      -- (peek_wall returns the front regardless of how many times we
      -- call it, since no actual wall consumption happens).
      assert.are.equal(2, #deal.players[1].known_wall_tile_ids)
      assert.are.equal(6, active.counters["opp_honor_discards"])
   end)
end)

-- ── dragon_pulse ─────────────────────────────────────────────────────────

describe("M2 boon: dragon_pulse", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 mulligan + 1 peek token on a dragon peng", function()
      local deal = make_deal_with_wall({})
      local active = context.new_active("dragon_pulse", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_peng", "fa_cai", "peng")
      assert.are.equal(1, active.tokens["mulligan"])
      assert.are.equal(1, active.tokens["peek"])
   end)

   it("grants tokens on a dragon kong (open or concealed)", function()
      local deal = make_deal_with_wall({})
      local active = context.new_active("dragon_pulse", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_kong",  "hong_zhong", "kong")
      fire_call(deal, deal.active_boons, "on_ankan", "bai_ban",    "kong")
      assert.are.equal(2, active.tokens["mulligan"])
      assert.are.equal(2, active.tokens["peek"])
   end)

   it("does not grant tokens on a non-dragon peng", function()
      local deal = make_deal_with_wall({})
      local active = context.new_active("dragon_pulse", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_peng", "east",   "peng")  -- wind, not dragon
      fire_call(deal, deal.active_boons, "on_peng", "tiao_5", "peng")  -- suited
      local t = active.tokens
      local mul = t["mulligan"] or 0
      local peek = t["peek"] or 0
      assert.are.equal(0, mul)
      assert.are.equal(0, peek)
   end)

   it("does not grant tokens on a non-dragon kong", function()
      local deal = make_deal_with_wall({})
      local active = context.new_active("dragon_pulse", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_kong",  "south",  "kong")
      fire_call(deal, deal.active_boons, "on_ankan", "wan_5",  "kong")
      local t = active.tokens
      local mul = t["mulligan"] or 0
      local peek = t["peek"] or 0
      assert.are.equal(0, mul)
      assert.are.equal(0, peek)
   end)
end)
