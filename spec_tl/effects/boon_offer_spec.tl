-- M2-S02 boon offer-pool tests: catalog registration, eligible_at filter,
-- deterministic compose_offer, and accept_offer (pick + decline propagation).

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod    = require("core.rng")
local registry   = require("effects.boon_registry")
local offer      = require("effects.boon_offer")
local m2_boons   = require("content.m2_boons")
local context    = require("effects.boon_context")

local function tile(tile_id: string, kind_id: string): Tile
   return { tile_id = tile_id as TileId, kind_id = kind_id as TileKindId }
end

local function empty_deal(): DealState
   local function mk_player(): PlayerState
      return {
         hand                = { concealed_tiles = {}, sets = {}, discards = {} },
         opening_trim        = {},
         seat_wind           = "east" as Wind,
         is_human            = false,
         known_wall_tile_ids = {},
      }
   end
   return {
      players = { mk_player(), mk_player(), mk_player(), mk_player() },
      wall                     = { tiles = {} },
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
   }
end

describe("m2_boons catalog", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("registers exactly 6 starter-and-set_1 boons", function()
      local all = registry.all()
      assert.are.equal(6, #all)
   end)

   it("find returns the boon for a known id", function()
      local b = m2_boons.find("honors_gift")
      assert.is_not_nil(b)
      assert.are.equal("honor", b.cluster as string)
   end)

   it("find returns nil for an unknown id", function()
      assert.is_nil(m2_boons.find("does_not_exist"))
   end)
end)

describe("boon_offer.eligible_at", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("returns the 3 starter boons at milestone starter", function()
      local pool = offer.eligible_at("starter" as MilestoneId, {})
      assert.are.equal(3, #pool)
      local ids: {string} = {}
      for _, b in ipairs(pool) do ids[#ids + 1] = b.id end
      table.sort(ids)
      assert.are.same({"hidden_path", "honors_gift", "pure_path"}, ids)
   end)

   it("returns the 3 set_1 boons at milestone set_1", function()
      local pool = offer.eligible_at("set_1" as MilestoneId, {})
      local ids: {string} = {}
      for _, b in ipairs(pool) do ids[#ids + 1] = b.id end
      table.sort(ids)
      assert.are.same({"cleanse", "honors_eye", "silent_march"}, ids)
   end)

   it("includes flex-eligible boons at multiple milestones", function()
      -- cleanse is eligible at set_1 AND set_2
      local pool = offer.eligible_at("set_2" as MilestoneId, {})
      local found = false
      for _, b in ipairs(pool) do
         if b.id == "cleanse" then found = true end
      end
      assert.is_true(found)
   end)

   it("excludes boon ids in the excluded set", function()
      local pool = offer.eligible_at("starter" as MilestoneId, { honors_gift = true })
      assert.are.equal(2, #pool)
      for _, b in ipairs(pool) do
         assert.is_true(b.id ~= "honors_gift")
      end
   end)
end)

describe("boon_offer.compose_offer", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("returns 3 boons when pool size >= 3", function()
      local d = empty_deal()
      local out, _new_rng = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 3)
      assert.are.equal(3, #out)
   end)

   it("is deterministic for a given seed + deal state", function()
      local d = empty_deal()
      local a, _ = offer.compose_offer(rng_mod.from_seed(123), "starter" as MilestoneId, d, 3)
      local b, _ = offer.compose_offer(rng_mod.from_seed(123), "starter" as MilestoneId, d, 3)
      local a_ids = offer.offer_ids(a)
      local b_ids = offer.offer_ids(b)
      assert.are.same(a_ids, b_ids)
   end)

   it("yields different ordering for different seeds (over many trials)", function()
      -- Probabilistic: with 3 boons and Fisher-Yates, ~33% chance ordering matches.
      -- Try 5 seeds; at least one should differ from seed 1's order.
      local d = empty_deal()
      local base, _ = offer.compose_offer(rng_mod.from_seed(1), "starter" as MilestoneId, d, 3)
      local base_ids = offer.offer_ids(base)
      local any_diff = false
      for s = 2, 6 do
         local other, _ = offer.compose_offer(rng_mod.from_seed(s), "starter" as MilestoneId, d, 3)
         local other_ids = offer.offer_ids(other)
         for i = 1, #base_ids do
            if base_ids[i] ~= other_ids[i] then any_diff = true; break end
         end
         if any_diff then break end
      end
      assert.is_true(any_diff)
   end)

   it("excludes already-active boons from the offer", function()
      local d = empty_deal()
      d.active_boons[#d.active_boons + 1] = context.new_active("honors_gift", "starter" as AcquisitionPoint)
      local out, _ = offer.compose_offer(rng_mod.from_seed(42), "starter" as MilestoneId, d, 3)
      for _, b in ipairs(out) do
         assert.is_true(b.id ~= "honors_gift")
      end
      assert.are.equal(2, #out)  -- pool drops to 2
   end)

   it("excludes declined boons from the offer", function()
      local d = empty_deal()
      d.declined_boons_this_deal[#d.declined_boons_this_deal + 1] = "pure_path"
      local out, _ = offer.compose_offer(rng_mod.from_seed(42), "starter" as MilestoneId, d, 3)
      for _, b in ipairs(out) do
         assert.is_true(b.id ~= "pure_path")
      end
   end)

   it("returns empty list when pool is exhausted", function()
      local d = empty_deal()
      d.declined_boons_this_deal[#d.declined_boons_this_deal + 1] = "honors_gift"
      d.declined_boons_this_deal[#d.declined_boons_this_deal + 1] = "pure_path"
      d.declined_boons_this_deal[#d.declined_boons_this_deal + 1] = "hidden_path"
      local out, _ = offer.compose_offer(rng_mod.from_seed(42), "starter" as MilestoneId, d, 3)
      assert.are.equal(0, #out)
   end)

   it("returns count = 1 boons when asked for one", function()
      local d = empty_deal()
      local out, _ = offer.compose_offer(rng_mod.from_seed(42), "starter" as MilestoneId, d, 1)
      assert.are.equal(1, #out)
   end)

   it("clamps to pool size when count exceeds available (§369 exhaustion fallback)", function()
      local d = empty_deal()
      -- Decline one starter so only 2 remain eligible. Ask for 5.
      d.declined_boons_this_deal[#d.declined_boons_this_deal + 1] = "honors_gift"
      local out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 5)
      assert.are.equal(2, #out)
   end)

   it("returns empty offer when count is 0 or negative", function()
      local d = empty_deal()
      local zero_out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 0)
      assert.are.equal(0, #zero_out)
      local neg_out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, -3)
      assert.are.equal(0, #neg_out)
   end)
end)

describe("boon_offer.accept_offer", function()
   before_each(function()
      registry.reset()
      m2_boons.register_all()
   end)

   it("adds the picked boon to active_boons", function()
      local d = empty_deal()
      local out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 3)
      local ids = offer.offer_ids(out)
      local ok = offer.accept_offer(d, ids, "starter" as MilestoneId, ids[1])
      assert.is_true(ok)
      assert.are.equal(1, #d.active_boons)
      assert.are.equal(ids[1], d.active_boons[1].boon_id)
      assert.are.equal("starter", d.active_boons[1].acquired_at as string)
   end)

   it("adds the other offered boons to declined_boons_this_deal", function()
      local d = empty_deal()
      local out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 3)
      local ids = offer.offer_ids(out)
      local _ = offer.accept_offer(d, ids, "starter" as MilestoneId, ids[1])
      assert.are.equal(2, #d.declined_boons_this_deal)
      local declined_sorted = {d.declined_boons_this_deal[1], d.declined_boons_this_deal[2]}
      table.sort(declined_sorted)
      local expected = {ids[2], ids[3]}
      table.sort(expected)
      assert.are.same(expected, declined_sorted)
   end)

   it("returns false when picked id is not in offer", function()
      local d = empty_deal()
      local out, _ = offer.compose_offer(rng_mod.from_seed(7), "starter" as MilestoneId, d, 3)
      local ids = offer.offer_ids(out)
      local ok = offer.accept_offer(d, ids, "starter" as MilestoneId, "not_offered_id")
      assert.is_false(ok)
      assert.are.equal(0, #d.active_boons)
      assert.are.equal(0, #d.declined_boons_this_deal)
   end)

   it("declined boons do not reappear in a subsequent offer", function()
      local d = empty_deal()
      local first, _ = offer.compose_offer(rng_mod.from_seed(11), "starter" as MilestoneId, d, 3)
      local first_ids = offer.offer_ids(first)
      offer.accept_offer(d, first_ids, "starter" as MilestoneId, first_ids[1])

      -- All 3 starter boons are now either active or declined.
      local next_offer, _ = offer.compose_offer(rng_mod.from_seed(99), "starter" as MilestoneId, d, 3)
      assert.are.equal(0, #next_offer)
   end)

   it("set_1 offer does not include the boon picked at starter (cross-milestone exclusion)", function()
      local d = empty_deal()
      -- Pick a starter boon directly (no offer compose needed for setup).
      d.active_boons[#d.active_boons + 1] = context.new_active("hidden_path", "starter" as AcquisitionPoint)

      local set1, _ = offer.compose_offer(rng_mod.from_seed(11), "set_1" as MilestoneId, d, 3)
      -- hidden_path is starter-eligible only, so this exclusion only matters when
      -- the picked boon spans milestones. Here we verify the active boon's
      -- starter-only listing is the relevant gate.
      assert.are.equal(3, #set1)
      for _, b in ipairs(set1) do
         assert.is_true(b.id ~= "hidden_path")
      end
   end)
end)
