-- M2-S04 Plan A: token-spend action surface + cleanse boon.
-- Verifies the engine's SpendBoonTokenAction validation + emission, the
-- registry's eligible_token_spends query, and cleanse's effect (grant
-- token at deal_start, off-suit-swap on spend).

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
         hand                       = { concealed_tiles = concealed, sets = {}, discards = {} },
         opening_trim               = {},
         seat_wind                  = sw as Wind,
         is_human                   = human,
         known_wall_tile_ids        = {},
         concealed_pung_kinds_seen  = {},
         turn_extra_discards_owed   = 0,
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

-- A tiao-dominant hand (10 tiao + 3 wan + 1 honor = 14 tiles). dominant_suit
-- helper picks "tiao". off-suit candidates: 3 wan, 1 honor.
local function tiao_dominant_hand(): {Tile}
   return tiles({
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"tiao_9_a","tiao_9"},
      {"tiao_1_b","tiao_1"},
      {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
      {"east_a","east"},
   })
end

-- ── Cleanse boon ─────────────────────────────────────────────────────────

describe("M2 boon: cleanse", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 cleanse_charge token at deal start", function()
      local deal = make_deal({}, {})
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: DealLifecycleEvent = { event_name = "on_deal_start" }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)

      assert.are.equal(1, active.tokens["cleanse_charge"])
   end)

   it("does not stack cleanse_charge tokens on repeated deal_start fires", function()
      local deal = make_deal({}, {})
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: DealLifecycleEvent = { event_name = "on_deal_start" }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)
      registry.emit(deal, deal.active_boons, 1, ev as EventData)

      assert.are.equal(1, active.tokens["cleanse_charge"])
   end)

   it("swaps an off-suit hand tile for the next wall tile on spend", function()
      local wall = tiles({{"tiao_5_b","tiao_5"}, {"tiao_6_b","tiao_6"}})
      local deal = make_deal(tiao_dominant_hand(), wall)
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      active.tokens["cleanse_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", { tile_id = "wan_1_a" }))
      assert.is_true(r.ok, r.error)

      -- Token deducted.
      local active2 = r.deal.active_boons[1]
      assert.are.equal(0, active2.tokens["cleanse_charge"])
      -- wan_1_a discarded; tiao_5_b drawn into hand.
      local hand = r.deal.players[1].hand
      local saw_drawn, saw_discarded = false, false
      for _, t in ipairs(hand.concealed_tiles) do
         if (t.tile_id as string) == "tiao_5_b" then saw_drawn = true end
         if (t.tile_id as string) == "wan_1_a"  then saw_discarded = true end
      end
      assert.is_true(saw_drawn)
      assert.is_false(saw_discarded)
      assert.are.equal("wan_1_a", hand.discards[1].tile_id as string)
   end)

   it("rejects a spend that names a dominant-suit tile (not off-suit)", function()
      local wall = tiles({{"tiao_5_b","tiao_5"}})
      local deal = make_deal(tiao_dominant_hand(), wall)
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      active.tokens["cleanse_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      -- tiao_1_a IS in the dominant suit (tiao). The action is dispatched
      -- but the listener early-returns without spending or swapping.
      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", { tile_id = "tiao_1_a" }))
      assert.is_true(r.ok, r.error)
      -- Token NOT deducted; wall unchanged.
      assert.are.equal(1, r.deal.active_boons[1].tokens["cleanse_charge"])
      assert.are.equal(1, #r.deal.wall.tiles)
   end)

   it("allows honor tiles as off-suit cleanse targets", function()
      local wall = tiles({{"tiao_5_b","tiao_5"}})
      local deal = make_deal(tiao_dominant_hand(), wall)
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      active.tokens["cleanse_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", { tile_id = "east_a" }))
      assert.is_true(r.ok, r.error)
      assert.are.equal(0, r.deal.active_boons[1].tokens["cleanse_charge"])
   end)
end)

-- ── Engine action surface ────────────────────────────────────────────────

describe("engine: spend_boon_token validation", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("rejects when the player has no such boon active", function()
      local deal = make_deal({}, {})
      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", {}))
      assert.is_false(r.ok)
      assert.is_truthy(r.error:find("not active"))
   end)

   it("rejects when the active boon has zero of the requested token", function()
      local deal = make_deal({}, {})
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active   -- token count 0
      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", {}))
      assert.is_false(r.ok)
      assert.is_truthy(r.error:find("no cleanse_charge"))
   end)

   it("rejects outside awaiting_action phase", function()
      local deal = make_deal({}, {})
      deal.phase = "awaiting_draw" as DealPhase
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      active.tokens["cleanse_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active
      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", { tile_id = "wan_1_a" }))
      assert.is_false(r.ok)
      assert.is_truthy(r.error:find("awaiting_action"))
   end)

   it("rejects while a boon offer is pending", function()
      local deal = make_deal({}, {})
      deal.pending_offer = {"some_boon"}
      deal.pending_offer_milestone = "set_1" as MilestoneId
      local active = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      active.tokens["cleanse_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active
      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "cleanse", "cleanse_charge", { tile_id = "wan_1_a" }))
      assert.is_false(r.ok)
      assert.is_truthy(r.error:find("pending boon offer"))
   end)

   it("rejects when player_index is not the boon owner (seat 1)", function()
      local deal = make_deal({}, {})
      local r = engine.apply_action(deal, engine.spend_boon_token(
         2, "cleanse", "cleanse_charge", {}))
      assert.is_false(r.ok)
   end)
end)

-- ── Eligibility query ─────────────────────────────────────────────────────

describe("boon_registry.eligible_token_spends", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("returns one entry per (boon × token_kind) with count > 0", function()
      local a1 = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      a1.tokens["cleanse_charge"] = 1
      local a2 = context.new_active("hidden_path", "starter" as AcquisitionPoint)
      a2.tokens["mulligan"] = 1
      a2.tokens["peek"]     = 2
      local actives: {ActiveBoon} = { a1, a2 }

      local spends = registry.eligible_token_spends(actives)
      assert.are.equal(3, #spends)
   end)

   it("excludes zero-count token kinds", function()
      local a1 = context.new_active("cleanse", "set_1" as AcquisitionPoint)
      a1.tokens["cleanse_charge"] = 0   -- spent or never granted
      local actives: {ActiveBoon} = { a1 }

      local spends = registry.eligible_token_spends(actives)
      assert.are.equal(0, #spends)
   end)
end)
