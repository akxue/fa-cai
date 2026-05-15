-- M2-S00 boon system unit tests: engine primitives, BoonContext construction,
-- and listener dispatch in isolation. No deal_engine emission yet — that
-- wires up in T04 and is covered by the slice acceptance test.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod    = require("core.rng")
local primitives = require("effects.boon_primitives")
local context    = require("effects.boon_context")
local registry   = require("effects.boon_registry")

-- ── Helpers ────────────────────────────────────────────────────────────────

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

-- Minimal four-player deal scaffolding sufficient to exercise primitives.
-- Player 1 is the boon owner unless otherwise noted in a test.
local function make_deal(
   p1_concealed: {Tile},
   wall_tiles:   {Tile},
   p_other_discards: {{Tile}}    -- discards for players 2/3/4 (3 lists)
): DealState
   local function mk_player(tiles_: {Tile}, sw: string, human: boolean, discards: {Tile}): PlayerState
      return {
         hand                = { concealed_tiles = tiles_, sets = {}, discards = discards or {} },
         opening_trim        = {},
         seat_wind           = sw as Wind,
         is_human            = human,
         known_wall_tile_ids = {},
      }
   end
   return {
      players = {
         mk_player(p1_concealed,    "east",  true,  {}),
         mk_player({},              "south", false, p_other_discards[1] or {}),
         mk_player({},              "west",  false, p_other_discards[2] or {}),
         mk_player({},              "north", false, p_other_discards[3] or {}),
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
   }
end

local function with_ctx(deal: DealState, active: ActiveBoon, player_index: integer): BoonContext
   return context.make(deal, active, player_index)
end

local function new_active(): ActiveBoon
   return context.new_active("test_boon", "starter" as AcquisitionPoint)
end

-- ── Primitives ─────────────────────────────────────────────────────────────

describe("boon_primitives.peek_wall", function()
   it("returns the next N tiles without mutating the wall", function()
      local deal = make_deal({}, tiles({{"tiao_1_a","tiao_1"},{"tiao_2_a","tiao_2"},{"tiao_3_a","tiao_3"}}), {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      local peeked = primitives.peek_wall(ctx, 2)
      assert.are.equal(2, #peeked)
      assert.are.equal("tiao_1_a", peeked[1].tile_id)
      assert.are.equal("tiao_2_a", peeked[2].tile_id)
      assert.are.equal(3, #deal.wall.tiles)
   end)

   it("returns fewer than N if wall is short", function()
      local deal = make_deal({}, tiles({{"a","tiao_1"}}), {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      local peeked = primitives.peek_wall(ctx, 5)
      assert.are.equal(1, #peeked)
   end)
end)

describe("boon_primitives.live_counter", function()
   local function is_honor(t: Tile): boolean
      return t.kind_id == ("east" as TileKindId)
         or  t.kind_id == ("south" as TileKindId)
         or  t.kind_id == ("fa_cai" as TileKindId)
   end

   it("counts wall tiles matching the filter", function()
      local deal = make_deal({}, tiles({
         {"tiao_1_a","tiao_1"}, {"east_a","east"}, {"fa_cai_a","fa_cai"}, {"tiao_2_a","tiao_2"}
      }), {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.are.equal(2, primitives.live_counter(ctx, is_honor, "wall"))
   end)

   it("counts opponent discards excluding owner", function()
      local p2_discards = tiles({{"east_b","east"}, {"tiao_5_a","tiao_5"}})
      local p3_discards = tiles({{"fa_cai_b","fa_cai"}})
      local p4_discards = tiles({{"tiao_6_a","tiao_6"}})
      local deal = make_deal({}, {}, {p2_discards, p3_discards, p4_discards})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.are.equal(2, primitives.live_counter(ctx, is_honor, "opponent_discards"))
   end)

   it("counts all discards across all players", function()
      local p2_discards = tiles({{"east_b","east"}})
      local p4_discards = tiles({{"fa_cai_b","fa_cai"}, {"tiao_1_b","tiao_1"}})
      local deal = make_deal({}, {}, {p2_discards, {}, p4_discards})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.are.equal(2, primitives.live_counter(ctx, is_honor, "all_discards"))
   end)

   it("errors on unknown scope", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.has_error(function()
         primitives.live_counter(ctx, is_honor, "bogus_scope")
      end)
   end)
end)

describe("boon_primitives.discard_and_redraw", function()
   it("discards the trailing concealed tile and pulls next wall", function()
      local hand = tiles({{"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"}})
      local wall = tiles({{"wan_5_a","wan_5"}, {"wan_6_a","wan_6"}})
      local deal = make_deal(hand, wall, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)

      local drawn = primitives.discard_and_redraw(ctx)
      assert.are.equal("wan_5_a", drawn.tile_id)

      local p1 = deal.players[1].hand
      assert.are.equal(3, #p1.concealed_tiles)
      assert.are.equal("tiao_1_a", p1.concealed_tiles[1].tile_id)
      assert.are.equal("tiao_2_a", p1.concealed_tiles[2].tile_id)
      assert.are.equal("wan_5_a",  p1.concealed_tiles[3].tile_id)
      assert.are.equal(1, #p1.discards)
      assert.are.equal("tiao_3_a", p1.discards[1].tile_id)
      assert.are.equal(1, #deal.wall.tiles)
   end)
end)

describe("boon_primitives.swap_hand_for_wall", function()
   it("removes the named tile to discards and pulls next wall in place", function()
      local hand = tiles({{"tiao_1_a","tiao_1"}, {"tiao_2_a","tiao_2"}, {"tiao_3_a","tiao_3"}})
      local wall = tiles({{"wan_5_a","wan_5"}})
      local deal = make_deal(hand, wall, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)

      local drawn = primitives.swap_hand_for_wall(ctx, "tiao_2_a" as TileId)
      assert.are.equal("wan_5_a", drawn.tile_id)

      local p1 = deal.players[1].hand
      assert.are.equal(3, #p1.concealed_tiles)
      local ids: {string} = {}
      for _, t in ipairs(p1.concealed_tiles) do ids[#ids + 1] = t.tile_id end
      table.sort(ids)
      assert.are.same({"tiao_1_a", "tiao_3_a", "wan_5_a"}, ids)
      assert.are.equal("tiao_2_a", p1.discards[1].tile_id)
   end)

   it("errors when the requested tile is not in the concealed hand", function()
      local deal = make_deal(tiles({{"tiao_1_a","tiao_1"}}), tiles({{"wan_5_a","wan_5"}}), {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.has_error(function()
         primitives.swap_hand_for_wall(ctx, "not_here" as TileId)
      end)
   end)
end)

describe("boon_primitives.extra_draw", function()
   it("adds a wall tile to the concealed hand without discarding", function()
      local hand = tiles({{"tiao_1_a","tiao_1"}})
      local wall = tiles({{"wan_5_a","wan_5"}, {"wan_6_a","wan_6"}})
      local deal = make_deal(hand, wall, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)

      local drawn = primitives.extra_draw(ctx)
      assert.are.equal("wan_5_a", drawn.tile_id)
      assert.are.equal(2, #deal.players[1].hand.concealed_tiles)
      assert.are.equal(0, #deal.players[1].hand.discards)
      assert.are.equal(1, #deal.wall.tiles)
   end)
end)

describe("boon_primitives.reveal_opponent_last_draw", function()
   it("returns the opponent's last drawn tile when has_last_drawn is set", function()
      local deal = make_deal({}, {}, {{},{},{}})
      deal.current_player = 2
      deal.has_last_drawn = true
      deal.last_drawn_tile_id = "wan_7_a" as TileId
      deal.players[2].hand.concealed_tiles = tiles({{"tiao_1_a","tiao_1"}, {"wan_7_a","wan_7"}})

      local ctx = with_ctx(deal, new_active(), 1)
      local revealed = primitives.reveal_opponent_last_draw(ctx, 2)
      assert.are.equal("wan_7_a", revealed.tile_id)
   end)

   it("returns sentinel zero-tile when no info is available", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      local revealed = primitives.reveal_opponent_last_draw(ctx, 2)
      assert.are.equal("", revealed.tile_id)
   end)
end)

describe("boon_primitives.take_from_discard_pile", function()
   it("removes the named tile from pile_owner's discards and adds to caller's hand", function()
      local p2_discards = tiles({{"tiao_5_a","tiao_5"}, {"wan_3_a","wan_3"}})
      local deal = make_deal(tiles({{"tiao_1_a","tiao_1"}}), {}, {p2_discards, {}, {}})
      local ctx = with_ctx(deal, new_active(), 1)

      local taken = primitives.take_from_discard_pile(ctx, 2, "wan_3_a" as TileId, 5)
      assert.are.equal("wan_3_a", taken.tile_id)

      assert.are.equal(1, #deal.players[2].hand.discards)
      assert.are.equal("tiao_5_a", deal.players[2].hand.discards[1].tile_id)
      assert.are.equal(2, #deal.players[1].hand.concealed_tiles)
   end)

   it("errors when the tile is not in the named pile", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.has_error(function()
         primitives.take_from_discard_pile(ctx, 2, "missing" as TileId, 0)
      end)
   end)
end)

-- ── Token primitives ──────────────────────────────────────────────────────

describe("boon_primitives token state", function()
   it("grant_token initializes and increments token pools", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.are.equal(0, primitives.get_tokens(ctx, "mulligan"))
      primitives.grant_token(ctx, "mulligan", 2)
      assert.are.equal(2, primitives.get_tokens(ctx, "mulligan"))
      primitives.grant_token(ctx, "mulligan", 1)
      assert.are.equal(3, primitives.get_tokens(ctx, "mulligan"))
   end)

   it("spend_token returns false and leaves pool unchanged when insufficient", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      primitives.grant_token(ctx, "mulligan", 1)
      assert.is_false(primitives.spend_token(ctx, "mulligan", 2))
      assert.are.equal(1, primitives.get_tokens(ctx, "mulligan"))
   end)

   it("spend_token returns true and decrements when sufficient", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      primitives.grant_token(ctx, "mulligan", 3)
      assert.is_true(primitives.spend_token(ctx, "mulligan", 2))
      assert.are.equal(1, primitives.get_tokens(ctx, "mulligan"))
   end)
end)

describe("boon_primitives counter/flag state", function()
   it("get_counter returns 0 for unset keys", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.are.equal(0, primitives.get_counter(ctx, "any"))
   end)

   it("set_counter persists and is observable through get_counter", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      primitives.set_counter(ctx, "honors_seen", 4)
      assert.are.equal(4, primitives.get_counter(ctx, "honors_seen"))
   end)

   it("set_flag / get_flag round-trip", function()
      local deal = make_deal({}, {}, {{},{},{}})
      local ctx = with_ctx(deal, new_active(), 1)
      assert.is_false(primitives.get_flag(ctx, "used"))
      primitives.set_flag(ctx, "used", true)
      assert.is_true(primitives.get_flag(ctx, "used"))
   end)
end)

-- ── Registry + dispatch ───────────────────────────────────────────────────

describe("boon_registry catalog", function()
   before_each(function()
      registry.reset()
   end)

   it("returns nil and false for unknown ids", function()
      assert.is_nil(registry.get("nope"))
      assert.is_false(registry.has("nope"))
   end)

   it("stores and retrieves a registered boon", function()
      local b: Boon = {
         id = "test", cluster = "honor", name = "Test",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0, listens = {"on_player_draw"},
         condition = function(_ctx: BoonContext, _ev: EventData): boolean return true end,
         effect    = function(_ctx: BoonContext, _ev: EventData) end,
      }
      registry.register(b)
      assert.is_true(registry.has("test"))
      assert.are.equal(b, registry.get("test"))
   end)

   it("all() returns boons sorted by id", function()
      local function stub(id: string): Boon
         return {
            id = id, cluster = "honor", name = id, description = "",
            eligible_milestones = {"starter"}, effect_kind = "info", weight = 1.0,
            listens = {"on_player_draw"},
            condition = function(_c: BoonContext, _e: EventData): boolean return true end,
            effect    = function(_c: BoonContext, _e: EventData) end,
         }
      end
      registry.register(stub("zeta"))
      registry.register(stub("alpha"))
      registry.register(stub("mu"))
      local all = registry.all()
      assert.are.equal("alpha", all[1].id)
      assert.are.equal("mu",    all[2].id)
      assert.are.equal("zeta",  all[3].id)
   end)
end)

describe("boon_registry.emit", function()
   before_each(function()
      registry.reset()
   end)

   it("runs a matching listener and observes side effects on ActiveBoon state", function()
      local fired = 0
      local boon: Boon = {
         id = "counter_boon", cluster = "honor", name = "Counter",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0,
         listens = {"on_player_draw"},
         condition = function(_c: BoonContext, _e: EventData): boolean return true end,
         effect    = function(c: BoonContext, _e: EventData)
            fired = fired + 1
            c:set_counter("draws_seen", c:get_counter("draws_seen") + 1)
         end,
      }
      registry.register(boon)

      local active = context.new_active("counter_boon", "starter" as AcquisitionPoint)
      local deal   = make_deal({}, tiles({{"tiao_1_a","tiao_1"}}), {{},{},{}})
      local ev: PlayerDrawEvent = { event_name = "on_player_draw", tile = tile("tiao_1_a","tiao_1") }

      registry.emit(deal, {active}, 1, ev as EventData)
      registry.emit(deal, {active}, 1, ev as EventData)

      assert.are.equal(2, fired)
      assert.are.equal(2, active.counters["draws_seen"])
   end)

   it("skips listeners that do not match the event name", function()
      local fired = false
      local boon: Boon = {
         id = "discard_listener", cluster = "honor", name = "DL",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0,
         listens = {"on_player_discard"},
         condition = function(_c: BoonContext, _e: EventData): boolean return true end,
         effect    = function(_c: BoonContext, _e: EventData) fired = true end,
      }
      registry.register(boon)

      local active = context.new_active("discard_listener", "starter" as AcquisitionPoint)
      local deal   = make_deal({}, {}, {{},{},{}})
      local ev: PlayerDrawEvent = { event_name = "on_player_draw", tile = tile("tiao_1_a","tiao_1") }

      registry.emit(deal, {active}, 1, ev as EventData)
      assert.is_false(fired)
   end)

   it("skips listeners whose condition returns false", function()
      local fired = false
      local boon: Boon = {
         id = "gated", cluster = "honor", name = "G",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "info", weight = 1.0,
         listens = {"on_player_draw"},
         condition = function(_c: BoonContext, _e: EventData): boolean return false end,
         effect    = function(_c: BoonContext, _e: EventData) fired = true end,
      }
      registry.register(boon)

      local active = context.new_active("gated", "starter" as AcquisitionPoint)
      local deal   = make_deal({}, {}, {{},{},{}})
      local ev: PlayerDrawEvent = { event_name = "on_player_draw", tile = tile("tiao_1_a","tiao_1") }

      registry.emit(deal, {active}, 1, ev as EventData)
      assert.is_false(fired)
   end)

   it("runs multiple listeners in active-list order", function()
      local order: {string} = {}
      local function listener(id: string): Boon
         return {
            id = id, cluster = "honor", name = id, description = "",
            eligible_milestones = {"starter"}, effect_kind = "info", weight = 1.0,
            listens = {"on_player_draw"},
            condition = function(_c: BoonContext, _e: EventData): boolean return true end,
            effect    = function(_c: BoonContext, _e: EventData) order[#order + 1] = id end,
         }
      end
      registry.register(listener("a"))
      registry.register(listener("b"))

      local actives: {ActiveBoon} = {
         context.new_active("b", "starter" as AcquisitionPoint),
         context.new_active("a", "starter" as AcquisitionPoint),
      }
      local deal = make_deal({}, {}, {{},{},{}})
      local ev: PlayerDrawEvent = { event_name = "on_player_draw", tile = tile("tiao_1_a","tiao_1") }
      registry.emit(deal, actives, 1, ev as EventData)
      assert.are.same({"b","a"}, order)
   end)

   it("acceptance: stub boon on on_player_draw observes fire and calls peek_wall(1)", function()
      local peeked_tile_id: TileId = "" as TileId
      local boon: Boon = {
         id = "stub_peeker", cluster = "honor", name = "Stub",
         description = "", eligible_milestones = {"starter"},
         effect_kind = "peek", weight = 1.0,
         listens = {"on_player_draw"},
         condition = function(_c: BoonContext, _e: EventData): boolean return true end,
         effect    = function(c: BoonContext, _e: EventData)
            local front = c:peek_wall(1)
            if #front > 0 then peeked_tile_id = front[1].tile_id end
         end,
      }
      registry.register(boon)

      local active = context.new_active("stub_peeker", "starter" as AcquisitionPoint)
      local deal   = make_deal({}, tiles({{"wan_9_a","wan_9"},{"wan_8_a","wan_8"}}), {{},{},{}})
      local ev: PlayerDrawEvent = { event_name = "on_player_draw", tile = tile("anything","tiao_1") }

      registry.emit(deal, {active}, 1, ev as EventData)
      assert.are.equal("wan_9_a", peeked_tile_id)
      -- peek_wall must not mutate the wall
      assert.are.equal(2, #deal.wall.tiles)
   end)
end)
