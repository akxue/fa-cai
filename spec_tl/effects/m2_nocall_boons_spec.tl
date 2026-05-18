-- M2-S04 no-call-gated boon tests: silent_march (reset-on-call streak),
-- silent_stand (same, 5-streak / mulligan), concealed_insight (dead-on-call).
-- Drives the boons through registry.emit with hand-built deal scaffolding.

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

local function make_deal(wall_tiles: {Tile}): DealState
   local function mk(sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = {}, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
         concealed_pung_kinds_seen = {},
         turn_extra_discards_owed = 0,
         last_drawn_tile_id = "" as TileId,
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

local function fire_player_discard(deal: DealState, actives: {ActiveBoon})
   local ev: PlayerDiscardEvent = {
      event_name = "on_player_discard",
      tile       = tile("wan_1_a", "wan_1"),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

local function fire_player_peng(deal: DealState, actives: {ActiveBoon})
   local tile_set: TileSet = {
      kind        = "peng" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {
         tile("tiao_5_a", "tiao_5"), tile("tiao_5_b", "tiao_5"), tile("tiao_5_c", "tiao_5"),
      },
      called_from = 2,
   }
   local ev: CallEvent = {
      event_name    = "on_peng",
      tile_set      = tile_set,
      source_player = 2,
      kong_kind     = "",
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

-- ── silent_march ─────────────────────────────────────────────────────────

describe("M2 boon: silent_march", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 peek token after 3 no-call player discards", function()
      local deal = make_deal({})
      local active = context.new_active("silent_march", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(2, active.counters["consecutive_no_call"])
      assert.are.equal(0, active.tokens["peek"] or 0)

      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(3, active.counters["consecutive_no_call"])
      assert.are.equal(1, active.tokens["peek"])
   end)

   it("resets the consecutive counter when the player calls", function()
      local deal = make_deal({})
      local active = context.new_active("silent_march", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      -- Player calls during a reaction window, then their forced discard
      -- arrives. The counter should reset and that discard should NOT
      -- count toward the next streak.
      fire_player_peng(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(0, active.counters["consecutive_no_call"])
      assert.are.equal(0, active.tokens["peek"] or 0)
   end)

   it("can earn a second token in a later quiet streak after a call", function()
      local deal = make_deal({})
      local active = context.new_active("silent_march", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      -- First streak: 3 discards → 1 token.
      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(1, active.tokens["peek"])

      -- Call interrupts; counter resets; called-this-turn flag drops on
      -- the next discard.
      fire_player_peng(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(0, active.counters["consecutive_no_call"])

      -- Second streak: 3 more no-call discards → another token.
      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(2, active.tokens["peek"])
   end)
end)

-- ── silent_stand ─────────────────────────────────────────────────────────

describe("M2 boon: silent_stand", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 mulligan token after 5 no-call player discards", function()
      local deal = make_deal({})
      local active = context.new_active("silent_stand", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for _ = 1, 4 do fire_player_discard(deal, deal.active_boons) end
      assert.are.equal(0, active.tokens["mulligan"] or 0)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(1, active.tokens["mulligan"])
   end)

   it("grants tokens at 5 / 10 / 15 …", function()
      local deal = make_deal({})
      local active = context.new_active("silent_stand", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for _ = 1, 10 do fire_player_discard(deal, deal.active_boons) end
      assert.are.equal(2, active.tokens["mulligan"])
   end)

   it("resets the consecutive counter when the player calls", function()
      -- Mirror of the silent_march reset test against the 5-streak boon
      -- so the shared pattern's reset semantics are proven for both.
      local deal = make_deal({})
      local active = context.new_active("silent_stand", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for _ = 1, 4 do fire_player_discard(deal, deal.active_boons) end
      assert.are.equal(4, active.counters["consecutive_no_call"])

      fire_player_peng(deal, deal.active_boons)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(0, active.counters["consecutive_no_call"])
      assert.are.equal(0, active.tokens["mulligan"] or 0)
   end)
end)

-- ── concealed_insight ────────────────────────────────────────────────────

describe("M2 boon: concealed_insight", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("peeks 1 wall tile after 4 no-call player discards", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}})
      local deal = make_deal(wall)
      local active = context.new_active("concealed_insight", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for _ = 1, 3 do fire_player_discard(deal, deal.active_boons) end
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
      fire_player_discard(deal, deal.active_boons)
      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("tiao_5_a", deal.players[1].known_wall_tile_ids[1] as string)
   end)

   it("permanently disqualifies on the first player call", function()
      local wall = tiles({{"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}})
      local deal = make_deal(wall)
      local active = context.new_active("concealed_insight", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      -- 3 quiet discards, then a peng — disqualified forever.
      for _ = 1, 3 do fire_player_discard(deal, deal.active_boons) end
      fire_player_peng(deal, deal.active_boons)
      assert.is_true(active.flags["disqualified"])

      -- 10 more discards should not advance the counter or peek.
      for _ = 1, 10 do fire_player_discard(deal, deal.active_boons) end
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
      -- Counter is cleared to 0 alongside the disqualify flag (cleaner
      -- debug surface than leaving it frozen at the pre-call value).
      assert.are.equal(0, active.counters["no_call_discards"])
   end)
end)
