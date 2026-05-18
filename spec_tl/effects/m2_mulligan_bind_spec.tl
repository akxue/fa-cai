-- M2-S04 concealed_mulligan + suit_bind: Plan A token-spend boons.
-- concealed_mulligan does discard_and_redraw gated on no-call; suit_bind
-- does 2× extra_draw gated on ≥7 dominant-suit tiles in hand.

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

-- A 14-tile hand sufficient to be in awaiting_action, with a trailing
-- non-dominant tile that discard_and_redraw should target.
local function p1_with_trailing_wan(): {Tile}
   return tiles({
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"tiao_7_a","tiao_7"}, {"tiao_8_a","tiao_8"}, {"tiao_9_a","tiao_9"},
      {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      {"wan_1_a","wan_1"}, {"wan_9_a","wan_9"},
   })
end

-- 14 tiles with ≥7 in tiao (for suit_bind's gate).
local function p1_with_7_tiao(): {Tile}
   return tiles({
      {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
      {"tiao_7_a","tiao_7"},
      {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
      {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
      {"east_a","east"},
   })
end

-- ── concealed_mulligan ───────────────────────────────────────────────────

describe("M2 boon: concealed_mulligan", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 mulligan_charge token at deal_start", function()
      local deal = make_deal({}, {})
      local active = context.new_active("concealed_mulligan", "set_1" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: DealLifecycleEvent = { event_name = "on_deal_start" }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)
      assert.are.equal(1, active.tokens["mulligan_charge"])
   end)

   it("discards the trailing tile and redraws on spend", function()
      local wall = tiles({{"bing_5_a","bing_5"}})
      local deal = make_deal(p1_with_trailing_wan(), wall)
      local active = context.new_active("concealed_mulligan", "set_1" as AcquisitionPoint)
      active.tokens["mulligan_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "concealed_mulligan", "mulligan_charge", {}))
      assert.is_true(r.ok, r.error)
      assert.are.equal(0, r.deal.active_boons[1].tokens["mulligan_charge"])
      -- Trailing wan_9_a discarded; bing_5_a drawn.
      local hand = r.deal.players[1].hand
      assert.are.equal("wan_9_a", hand.discards[1].tile_id as string)
      local last = hand.concealed_tiles[#hand.concealed_tiles]
      assert.are.equal("bing_5_a", last.tile_id as string)
   end)

   it("rejects spend after the player has called (no-call gate)", function()
      local wall = tiles({{"bing_5_a","bing_5"}})
      local deal = make_deal(p1_with_trailing_wan(), wall)
      local active = context.new_active("concealed_mulligan", "set_1" as AcquisitionPoint)
      active.tokens["mulligan_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      -- Fire a peng event directly to trip the disqualifier.
      local tile_set: TileSet = {
         kind        = "peng" as TileSetKind,
         visibility  = "open" as SetVisibility,
         tiles       = {
            tile("tiao_5_a","tiao_5"), tile("tiao_5_b","tiao_5"), tile("tiao_5_c","tiao_5"),
         },
         called_from = 2,
      }
      local ev: CallEvent = {
         event_name    = "on_peng",
         tile_set      = tile_set,
         source_player = 2,
         kong_kind     = "",
      }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)
      assert.is_true(active.flags["disqualified"])

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "concealed_mulligan", "mulligan_charge", {}))
      assert.is_true(r.ok, r.error)
      -- Token preserved; no swap occurred.
      assert.are.equal(1, r.deal.active_boons[1].tokens["mulligan_charge"])
      assert.are.equal(1, #r.deal.wall.tiles)
   end)

   it("rejects spend when wall is empty", function()
      local deal = make_deal(p1_with_trailing_wan(), {})
      local active = context.new_active("concealed_mulligan", "set_1" as AcquisitionPoint)
      active.tokens["mulligan_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "concealed_mulligan", "mulligan_charge", {}))
      assert.is_true(r.ok, r.error)
      assert.are.equal(1, r.deal.active_boons[1].tokens["mulligan_charge"])
   end)
end)

-- ── suit_bind ─────────────────────────────────────────────────────────────

describe("M2 boon: suit_bind", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("grants 1 bind_charge token at deal_start", function()
      local deal = make_deal({}, {})
      local active = context.new_active("suit_bind", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      local ev: DealLifecycleEvent = { event_name = "on_deal_start" }
      registry.emit(deal, deal.active_boons, 1, ev as EventData)
      assert.are.equal(1, active.tokens["bind_charge"])
   end)

   it("takes 2 extra draws when player has ≥7 dominant tiles", function()
      local wall = tiles({
         {"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}, {"bing_7_a","bing_7"},
      })
      local deal = make_deal(p1_with_7_tiao(), wall)
      local active = context.new_active("suit_bind", "set_3" as AcquisitionPoint)
      active.tokens["bind_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "suit_bind", "bind_charge", {}))
      assert.is_true(r.ok, r.error)
      assert.are.equal(0, r.deal.active_boons[1].tokens["bind_charge"])
      assert.are.equal(1, #r.deal.wall.tiles)   -- 2 consumed from 3
      assert.are.equal(2, r.deal.players[1].turn_extra_discards_owed)
   end)

   it("rejects when dominant count is below 7", function()
      -- 6 tiao + filler — below the threshold.
      local p1 = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
         {"tiao_4_a","tiao_4"}, {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"},
         {"bing_1_a","bing_1"}, {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"},
         {"bing_4_a","bing_4"}, {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"},
         {"east_a","east"}, {"south_a","south"},
      })
      local wall = tiles({{"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}})
      local deal = make_deal(p1, wall)
      local active = context.new_active("suit_bind", "set_3" as AcquisitionPoint)
      active.tokens["bind_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "suit_bind", "bind_charge", {}))
      assert.is_true(r.ok, r.error)
      -- Token preserved; no extra draws taken.
      assert.are.equal(1, r.deal.active_boons[1].tokens["bind_charge"])
      assert.are.equal(2, #r.deal.wall.tiles)
      assert.are.equal(0, r.deal.players[1].turn_extra_discards_owed)
   end)

   it("rejects when wall has fewer than 2 tiles", function()
      local wall = tiles({{"bing_5_a","bing_5"}})   -- only 1
      local deal = make_deal(p1_with_7_tiao(), wall)
      local active = context.new_active("suit_bind", "set_3" as AcquisitionPoint)
      active.tokens["bind_charge"] = 1
      deal.active_boons[#deal.active_boons + 1] = active

      local r = engine.apply_action(deal, engine.spend_boon_token(
         1, "suit_bind", "bind_charge", {}))
      assert.is_true(r.ok, r.error)
      assert.are.equal(1, r.deal.active_boons[1].tokens["bind_charge"])
      assert.are.equal(1, #r.deal.wall.tiles)
   end)
end)
