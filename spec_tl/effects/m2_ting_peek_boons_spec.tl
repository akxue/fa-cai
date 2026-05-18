-- M2-S04 ting-activated per-turn peek boons: Honor Sanctum (ting w/ 4+
-- honors) and Closed Eye (concealed ting). Both latch an `active` flag
-- when ting is reached under their respective predicate, then peek 1
-- wall tile on every subsequent on_player_draw.

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

local function make_deal(p1_concealed: {Tile}, p1_sets: {TileSet}, wall_tiles: {Tile}): DealState
   local function mk(concealed: {Tile}, sets: {TileSet}, sw: string, human: boolean): PlayerState
      return {
         hand                = { concealed_tiles = concealed, sets = sets, discards = {} },
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

local function fire_player_draw(deal: DealState, actives: {ActiveBoon}, tile_kind: string)
   local ev: PlayerDrawEvent = {
      event_name = "on_player_draw",
      tile       = tile(tile_kind .. "_a", tile_kind),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

local function open_peng(kind_id: string): TileSet
   return {
      kind        = "peng" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {
         tile(kind_id .. "_a", kind_id), tile(kind_id .. "_b", kind_id), tile(kind_id .. "_c", kind_id),
      },
      called_from = 2,
   }
end

local function open_kong(kind_id: string): TileSet
   return {
      kind        = "kong" as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {
         tile(kind_id .. "_a", kind_id), tile(kind_id .. "_b", kind_id),
         tile(kind_id .. "_c", kind_id), tile(kind_id .. "_d", kind_id),
      },
      called_from = 2,
   }
end

local function concealed_kong(kind_id: string): TileSet
   return {
      kind        = "kong" as TileSetKind,
      visibility  = "concealed" as SetVisibility,
      tiles       = {
         tile(kind_id .. "_a", kind_id), tile(kind_id .. "_b", kind_id),
         tile(kind_id .. "_c", kind_id), tile(kind_id .. "_d", kind_id),
      },
      called_from = -1,
   }
end

-- ── honor_sanctum ─────────────────────────────────────────────────────────

describe("M2 boon: honor_sanctum", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("activates on ting with 4+ honor tiles and peeks on every later draw", function()
      -- Concealed: 4 honors (E S W N) + filler. Activation should latch.
      local concealed = tiles({
         {"east_a","east"}, {"south_a","south"}, {"west_a","west"}, {"north_a","north"},
         {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}, {"tiao_7_a","tiao_7"},
         {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"}, {"bing_4_a","bing_4"},
         {"wan_5_a","wan_5"}, {"wan_5_b","wan_5"}, {"wan_5_c","wan_5"},
      })
      local wall = tiles({{"wan_9_a","wan_9"}, {"wan_8_a","wan_8"}, {"wan_7_a","wan_7"}})
      local deal = make_deal(concealed, {}, wall)
      local active = context.new_active("honor_sanctum", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])

      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("wan_9_a", deal.players[1].known_wall_tile_ids[1] as string)
   end)

   it("does not activate on ting with fewer than 4 honor tiles", function()
      local concealed = tiles({
         {"east_a","east"}, {"south_a","south"}, {"west_a","west"},  -- 3 honors
         {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}, {"tiao_7_a","tiao_7"},
         {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"}, {"bing_4_a","bing_4"},
         {"wan_5_a","wan_5"}, {"wan_5_b","wan_5"}, {"wan_5_c","wan_5"},
         {"wan_6_a","wan_6"},
      })
      local wall = tiles({{"wan_9_a","wan_9"}})
      local deal = make_deal(concealed, {}, wall)
      local active = context.new_active("honor_sanctum", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_falsy(active.flags["active"])

      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
   end)

   it("counts honors across called/concealed sets toward the 4+ threshold", function()
      -- One concealed kong of dragons (4 honors) + filler concealed.
      local concealed = tiles({
         {"tiao_5_a","tiao_5"}, {"tiao_6_a","tiao_6"}, {"tiao_7_a","tiao_7"},
         {"bing_2_a","bing_2"}, {"bing_3_a","bing_3"}, {"bing_4_a","bing_4"},
         {"wan_5_a","wan_5"}, {"wan_5_b","wan_5"}, {"wan_5_c","wan_5"},
      })
      local sets: {TileSet} = { concealed_kong("fa_cai") }
      local deal = make_deal(concealed, sets, tiles({{"wan_9_a","wan_9"}}))
      local active = context.new_active("honor_sanctum", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])
   end)
end)

-- ── closed_eye ────────────────────────────────────────────────────────────

describe("M2 boon: closed_eye", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("activates on ting with zero open sets and peeks on subsequent draws", function()
      local concealed = tiles({
         {"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"},
      })
      local wall = tiles({{"wan_9_a","wan_9"}, {"wan_8_a","wan_8"}})
      local deal = make_deal(concealed, {}, wall)
      local active = context.new_active("closed_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])

      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal("wan_9_a", deal.players[1].known_wall_tile_ids[1] as string)
   end)

   it("treats concealed kongs as still-concealed (activates)", function()
      local concealed = tiles({{"tiao_5_a","tiao_5"}})
      local sets: {TileSet} = { concealed_kong("east") }
      local deal = make_deal(concealed, sets, tiles({{"wan_9_a","wan_9"}}))
      local active = context.new_active("closed_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_true(active.flags["active"])
   end)

   it("does not activate if there is any open set (open peng)", function()
      local concealed = tiles({{"tiao_5_a","tiao_5"}})
      local sets: {TileSet} = { open_peng("east") }
      local deal = make_deal(concealed, sets, tiles({{"wan_9_a","wan_9"}}))
      local active = context.new_active("closed_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_falsy(active.flags["active"])

      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal(0, #deal.players[1].known_wall_tile_ids)
   end)

   it("does not activate if there is any open set (open kong)", function()
      -- Same disqualification path as open peng, exercised via the kong
      -- variant. Locks in the contract that all visibility="open" set
      -- kinds disqualify Closed Eye, not just pengs.
      local concealed = tiles({{"tiao_5_a","tiao_5"}})
      local sets: {TileSet} = { open_kong("east") }
      local deal = make_deal(concealed, sets, tiles({{"wan_9_a","wan_9"}}))
      local active = context.new_active("closed_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      assert.is_falsy(active.flags["active"])
   end)

   it("peeks every draw while active (distinct wall fronts accumulate)", function()
      -- Mutate the wall front between draws so each peek sees a different
      -- tile — proves the boon fires per-draw, not just deduplicates the
      -- same front on repeated emissions.
      local concealed = tiles({{"tiao_1_a","tiao_1"}})
      local wall = tiles({{"wan_9_a","wan_9"}, {"wan_8_a","wan_8"}, {"wan_7_a","wan_7"}})
      local deal = make_deal(concealed, {}, wall)
      local active = context.new_active("closed_eye", "ting" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_ting(deal, deal.active_boons)
      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal(1, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("wan_9_a", deal.players[1].known_wall_tile_ids[1] as string)

      -- Simulate the engine consuming the wall front (real draw would
      -- shift it). Now the next peek sees a different tile.
      table.remove(deal.wall.tiles, 1)
      fire_player_draw(deal, deal.active_boons, "wan_8")
      assert.are.equal(2, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("wan_8_a", deal.players[1].known_wall_tile_ids[2] as string)

      table.remove(deal.wall.tiles, 1)
      fire_player_draw(deal, deal.active_boons, "wan_7")
      assert.are.equal(3, #deal.players[1].known_wall_tile_ids)
      assert.are.equal("wan_7_a", deal.players[1].known_wall_tile_ids[3] as string)
   end)
end)
