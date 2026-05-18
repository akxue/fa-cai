-- M2-S04 suit_sentry: ting-activated boon (Plan C). When the player
-- reaches ting on a "pure dominant-suit wait" (every completing kind is
-- in the dominant suit), peek 1 wall tile each turn for the rest of the
-- deal. Mirrors the Honor Sanctum / Closed Eye two-phase latch.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
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

local function fire_draw(deal: DealState, actives: {ActiveBoon}, kind: string)
   local ev: PlayerDrawEvent = {
      event_name = "on_player_draw",
      tile       = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

describe("M2 boon: suit_sentry", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("activates on a pure-tiao wait at ting and peeks on subsequent draws", function()
      -- Tiao-heavy hand at ting with only tiao completers:
      --   456t 789t 11w + open peng wan_5 + waiting on a tiao 1-3 chi.
      -- Concealed: 12t 456t 789t 11w (10 tiles); 1 open set; waiting on
      -- tiao_3 only (12 + 3 → 123 chi).
      local concealed = parse("12t 456t 789t 11w")
      local open: {TileSet} = {
         {
            kind = "peng" as TileSetKind,
            visibility = "open" as SetVisibility,
            tiles = {
               tile("wan_5_a","wan_5"), tile("wan_5_b","wan_5"), tile("wan_5_c","wan_5"),
            },
            called_from = 2,
         },
      }
      local wall = tiles({{"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}})
      local deal = make_deal(concealed, open, wall)
      local active = context.new_active("suit_sentry", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])

      fire_draw(deal, deal.active_boons, "anything")
      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("bing_5_a", deal.players[1].known_wall_tile_ids[1] as string)
   end)

   it("does NOT activate when the wait is mixed-suit", function()
      -- 3 chi (2 in tiao, 1 in bing) + 11w + 1 floating tiao that can
      -- extend either way → wait on tiao_3 OR tiao_6 — both still tiao,
      -- so this WOULD activate. Make it mixed by having a wait that
      -- includes a non-tiao. Use a shanpon-style hand with a wan pair
      -- candidate so the wait set includes wan + tiao.
      local concealed = parse("123t 456t 789t 11w 1b")
      -- Waits include bing_1 (pair) — not in dominant suit (tiao). So
      -- activation should NOT fire.
      local wall = tiles({{"bing_5_a","bing_5"}})
      local deal = make_deal(concealed, {}, wall)
      local active = context.new_active("suit_sentry", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_falsy(active.flags["active"])

      fire_draw(deal, deal.active_boons, "anything")
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
   end)

   it("does not peek on draws before ting (latch starts disabled)", function()
      local wall = tiles({{"bing_5_a","bing_5"}})
      local deal = make_deal({}, {}, wall)
      local active = context.new_active("suit_sentry", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_draw(deal, deal.active_boons, "anything")
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
   end)

   it("dedupes peeked tile_ids across multiple draws against the same wall front", function()
      -- Latch activated; subsequent draws fire peek_wall(1) which would
      -- return the same front tile repeatedly until the wall actually
      -- shrinks. mark_wall_known dedups so the strip doesn't fill.
      local concealed = parse("12t 456t 789t 11w")
      local open: {TileSet} = {
         {
            kind = "peng" as TileSetKind,
            visibility = "open" as SetVisibility,
            tiles = {
               tile("wan_5_a","wan_5"), tile("wan_5_b","wan_5"), tile("wan_5_c","wan_5"),
            },
            called_from = 2,
         },
      }
      local wall = tiles({{"bing_5_a","bing_5"}, {"bing_6_a","bing_6"}})
      local deal = make_deal(concealed, open, wall)
      local active = context.new_active("suit_sentry", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      fire_draw(deal, deal.active_boons, "anything")
      fire_draw(deal, deal.active_boons, "anything")
      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
   end)
end)
