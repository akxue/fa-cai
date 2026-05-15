-- M2-S02 offer-pool composition.
--
-- At each milestone fork the engine constructs an offer of N (default 3)
-- random boons drawn from the catalog filtered by:
--   - eligibility (boon.eligible_milestones contains the firing milestone)
--   - not already active on the deal (picked at a previous fork)
--   - not declined this deal (offered at a previous fork and skipped)
--
-- See MILESTONE-2-PLAN.md §357 for the offer rule and §371 for re-offer.
-- Pure rules layer — no love/ui/scenes/app imports.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.boon_types")

local rng_mod  = require("core.rng")
local registry = require("effects.boon_registry")

local M = {}

local DEFAULT_OFFER_SIZE <const> = 3

-- Looks up the catalog and returns every boon eligible at the given milestone
-- whose id is NOT in the excluded set. Sorted by id for determinism.
function M.eligible_at(milestone: MilestoneId, excluded: {string: boolean}): {Boon}
   local out: {Boon} = {}
   for _, b in ipairs(registry.all()) do
      local eligible = false
      for _, m in ipairs(b.eligible_milestones) do
         if m == milestone then eligible = true; break end
      end
      if eligible and not excluded[b.id] then
         out[#out + 1] = b
      end
   end
   return out
end

-- Helper: builds the excluded set from active+declined ids on a deal.
local function build_excluded(deal: DealState): {string: boolean}
   local excluded: {string: boolean} = {}
   for _, ab in ipairs(deal.active_boons) do
      excluded[ab.boon_id] = true
   end
   for _, id in ipairs(deal.declined_boons_this_deal) do
      excluded[id] = true
   end
   return excluded
end

-- Composes an offer of up to `count` boons drawn deterministically from the
-- eligible pool. Consumes `rng` and returns the new RNG state.
--
-- Drawing without replacement: shuffle the eligible pool, take the first
-- `count`. If the pool has fewer than `count`, return what's available
-- (defensive fallback per plan §369).
function M.compose_offer(
   rng:       RngState,
   milestone: MilestoneId,
   deal:      DealState,
   count:     integer
): {Boon}, RngState
   if count <= 0 then count = DEFAULT_OFFER_SIZE end
   local excluded = build_excluded(deal)
   local pool     = M.eligible_at(milestone, excluded)

   if #pool == 0 then return {}, rng end

   -- Fisher-Yates over a small pool; we only need the first `count` slots
   -- shuffled correctly.
   local indices: {integer} = {}
   for i = 1, #pool do indices[i] = i end
   local cur = rng
   local limit = math.min(count, #pool)
   for i = #indices, math.max(2, #indices - limit + 1), -1 do
      local r = rng_mod.next_int(cur, 1, i)
      local j = r.value
      indices[i], indices[j] = indices[j], indices[i]
      cur = r.rng
   end

   local out: {Boon} = {}
   for i = 1, limit do
      out[i] = pool[indices[#indices - i + 1]]
   end
   return out, cur
end

-- Returns the boon ids in an offer list — convenience for storing on DealState.
function M.offer_ids(offer: {Boon}): {string}
   local out: {string} = {}
   for _, b in ipairs(offer) do out[#out + 1] = b.id end
   return out
end

-- Resolves a pick against the current offer:
--   - Adds the picked boon as an ActiveBoon on the deal.
--   - Marks the other offered boons as declined (added to declined list).
-- Returns true on success, false if `picked_boon_id` is not in the offer.
function M.accept_offer(
   deal:           DealState,
   offer:          {string},
   milestone:      MilestoneId,
   picked_boon_id: string
): boolean
   local found = false
   for _, id in ipairs(offer) do
      if id == picked_boon_id then found = true; break end
   end
   if not found then return false end

   deal.active_boons[#deal.active_boons + 1] = {
      boon_id     = picked_boon_id,
      acquired_at = milestone as AcquisitionPoint,
      counters    = {},
      flags       = {},
      tokens      = {},
   }
   for _, id in ipairs(offer) do
      if id ~= picked_boon_id then
         deal.declined_boons_this_deal[#deal.declined_boons_this_deal + 1] = id
      end
   end
   return true
end

return M
