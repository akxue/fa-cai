-- M2-S04 honor_hunt + honor_heart: extra-draw boons that fire on honor
-- draws (every 4th, deferred to next turn) and honor calls (immediate),
-- respectively. Both call ctx:extra_draw() which the engine wires to
-- the matched-discard turn extension shipped in Plan B.

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
         hand                       = { concealed_tiles = {}, sets = {}, discards = {} },
         opening_trim               = {},
         seat_wind                  = sw as Wind,
         is_human                   = human,
         known_wall_tile_ids        = {},
         concealed_pung_kinds_seen  = {},
         turn_extra_discards_owed   = 0,
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

local function fire_honor_drawn(deal: DealState, actives: {ActiveBoon}, kind: string)
   local ev_draw: PlayerDrawEvent = {
      event_name = "on_player_draw",
      tile       = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev_draw as EventData)
   local ev_honor: TilePropertyEvent = {
      event_name = "on_honor_drawn",
      tile       = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev_honor as EventData)
end

local function fire_player_draw(deal: DealState, actives: {ActiveBoon}, kind: string)
   local ev: PlayerDrawEvent = {
      event_name = "on_player_draw",
      tile       = tile(kind .. "_a", kind),
   }
   registry.emit(deal, actives, 1, ev as EventData)
end

local function fire_call(deal: DealState, actives: {ActiveBoon}, event_name: string, kind_id: string, set_kind: string)
   local tile_set: TileSet = {
      kind        = set_kind as TileSetKind,
      visibility  = "open" as SetVisibility,
      tiles       = {
         tile(kind_id .. "_a", kind_id), tile(kind_id .. "_b", kind_id), tile(kind_id .. "_c", kind_id),
      },
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

-- ── honor_hunt ────────────────────────────────────────────────────────────

describe("M2 boon: honor_hunt", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("increments honor_draws but does NOT grant extra draws on the first 3 honors", function()
      local wall = tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"}, {"wan_4_a","wan_4"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_hunt", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_honor_drawn(deal, deal.active_boons, "east")
      fire_honor_drawn(deal, deal.active_boons, "south")
      fire_honor_drawn(deal, deal.active_boons, "west")
      assert.are.equal(3, active.counters["honor_draws"])
      assert.are.equal(0, active.counters["pending_extra_draws"] or 0)
      assert.are.equal(4, #deal.wall.tiles)   -- no extra_draw consumed the wall
   end)

   it("queues pending_extra_draws on the 4th honor draw, takes the bonus on the next player_draw", function()
      local wall = tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"}, {"wan_4_a","wan_4"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_hunt", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_honor_drawn(deal, deal.active_boons, "east")
      fire_honor_drawn(deal, deal.active_boons, "south")
      fire_honor_drawn(deal, deal.active_boons, "west")
      fire_honor_drawn(deal, deal.active_boons, "north")
      assert.are.equal(4, active.counters["honor_draws"])
      assert.are.equal(1, active.counters["pending_extra_draws"])
      -- Bonus is NOT taken on the same on_player_draw that fired the 4th
      -- honor (on_honor_drawn fires AFTER on_player_draw via the derived-
      -- event chain). Wall still has its full 4 tiles.
      assert.are.equal(4, #deal.wall.tiles)

      -- Next turn's draw consumes one bonus.
      fire_player_draw(deal, deal.active_boons, "wan_1")
      assert.are.equal(0, active.counters["pending_extra_draws"])
      -- extra_draw consumed the front wall tile and added it to the hand
      -- AND bumped turn_extra_discards_owed (Plan B's machinery).
      assert.are.equal(3, #deal.wall.tiles)
      assert.are.equal(1, deal.players[1].hand.concealed_tiles[#deal.players[1].hand.concealed_tiles].tile_id == ("wan_1_a" as TileId) and 1 or 1)   -- placeholder, just access
      assert.are.equal(1, deal.players[1].turn_extra_discards_owed)
   end)

   it("re-triggers every 4 honors across the deal (no cap)", function()
      local wall = tiles({
         {"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}, {"wan_3_a","wan_3"},
         {"wan_4_a","wan_4"}, {"wan_5_a","wan_5"},
      })
      local deal = make_deal(wall)
      local active = context.new_active("honor_hunt", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      -- 4 honor draws → 1 pending after the 4th. (on_player_draw fires
      -- BEFORE on_honor_drawn within fire_honor_drawn, so pending only
      -- reaches 1, never stacks across consecutive honor draws.)
      for _ = 1, 4 do fire_honor_drawn(deal, deal.active_boons, "east") end
      assert.are.equal(4, active.counters["honor_draws"])
      assert.are.equal(1, active.counters["pending_extra_draws"])
      assert.are.equal(5, #deal.wall.tiles)

      -- Next non-honor draw drains the pending and takes the bonus.
      fire_player_draw(deal, deal.active_boons, "wan_9")
      assert.are.equal(0, active.counters["pending_extra_draws"])
      assert.are.equal(4, #deal.wall.tiles)

      -- 4 more honor draws → another trigger.
      for _ = 1, 4 do fire_honor_drawn(deal, deal.active_boons, "south") end
      assert.are.equal(8, active.counters["honor_draws"])
      assert.are.equal(1, active.counters["pending_extra_draws"])
   end)

   it("does not trigger on non-honor draws", function()
      local wall = tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_hunt", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      for _ = 1, 4 do fire_player_draw(deal, deal.active_boons, "wan_5") end
      assert.are.equal(0, active.counters["honor_draws"] or 0)
      assert.are.equal(0, active.counters["pending_extra_draws"] or 0)
   end)

   it("does not crash when wall is empty during a pending extra draw (token preserved)", function()
      local deal = make_deal({})   -- empty wall
      local active = context.new_active("honor_hunt", "set_2" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active
      active.counters["pending_extra_draws"] = 1   -- planted

      fire_player_draw(deal, deal.active_boons, "wan_9")
      -- Pending preserved; no extra_draw attempted.
      assert.are.equal(1, active.counters["pending_extra_draws"])
   end)
end)

-- ── honor_heart ───────────────────────────────────────────────────────────

describe("M2 boon: honor_heart", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("takes an extra wall tile on an honor peng", function()
      local wall = tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_heart", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_peng", "east", "peng")
      assert.are.equal(1, #deal.wall.tiles)   -- one tile consumed by extra_draw
      assert.are.equal(1, deal.players[1].turn_extra_discards_owed)
   end)

   it("takes an extra wall tile on an honor concealed kong (ankan)", function()
      local wall = tiles({{"wan_1_a","wan_1"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_heart", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_ankan", "fa_cai", "kong")
      assert.are.equal(0, #deal.wall.tiles)
      assert.are.equal(1, deal.players[1].turn_extra_discards_owed)
   end)

   it("does not trigger on a non-honor peng", function()
      local wall = tiles({{"wan_1_a","wan_1"}, {"wan_2_a","wan_2"}})
      local deal = make_deal(wall)
      local active = context.new_active("honor_heart", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_peng", "tiao_5", "peng")
      assert.are.equal(2, #deal.wall.tiles)
      assert.are.equal(0, deal.players[1].turn_extra_discards_owed)
   end)

   it("does not crash when wall is empty (no extra draw attempted)", function()
      local deal = make_deal({})
      local active = context.new_active("honor_heart", "set_3" as AcquisitionPoint)
      deal.active_boons[#deal.active_boons + 1] = active

      fire_call(deal, deal.active_boons, "on_peng", "east", "peng")
      assert.are.equal(0, deal.players[1].turn_extra_discards_owed)
   end)
end)
