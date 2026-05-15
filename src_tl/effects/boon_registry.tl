-- M2 boon registry + event dispatcher.
--
-- Catalog: maps boon id → Boon record (pure data definitions from content/).
-- Dispatch: given an event and the active boons in scope, runs each matching
-- listener's condition; if true, runs the effect with a fresh BoonContext.
--
-- Pure rules layer — no love/ui/scenes/app imports.
-- M1's effect_registry.tl + effect_runner.tl remain active in parallel; this
-- module is the M2 (D012) replacement to be exercised first by S00's stub
-- boon and then progressively by S01–S04 features.

require("core.types")
require("game.deal_types")
require("effects.boon_types")

local boon_context = require("effects.boon_context")

local M = {}

-- ── Catalog ───────────────────────────────────────────────────────────────

local catalog: {string: Boon} = {}

function M.register(boon: Boon)
   assert(boon ~= nil, "register: nil boon")
   assert(boon.id ~= nil and boon.id ~= "", "register: boon missing id")
   assert(boon.listens ~= nil, "register: boon missing listens list")
   catalog[boon.id] = boon
end

function M.get(id: string): Boon
   return catalog[id]
end

function M.has(id: string): boolean
   return catalog[id] ~= nil
end

function M.all(): {Boon}
   local out: {Boon} = {}
   for _, b in pairs(catalog) do
      out[#out + 1] = b
   end
   table.sort(out, function(x: Boon, y: Boon): boolean
      return x.id < y.id
   end)
   return out
end

-- Test/utility: clears the catalog. Production registers once at startup.
function M.reset()
   catalog = {}
end

-- ── Dispatch ──────────────────────────────────────────────────────────────
--
-- emit walks the supplied active boon list in registration order, filters to
-- those whose `listens` contains the event name, and runs condition+effect.
-- Each effect mutates ctx.deal in place via primitives; the engine that
-- called emit observes the updated state on the same DealState reference.
--
-- Listener execution is sequential. Multiple boons listening to the same
-- event run in the order they appear in `actives` — the caller controls
-- ordering (S00 keeps insertion order; later slices may sort by priority).

-- Linear scan of the listens list. Lists are tiny (1–3 entries in the
-- 24-boon library), so no hashed lookup is justified yet.
local function listens_for(boon: Boon, event_name: EventName): boolean
   for _, ev in ipairs(boon.listens) do
      if ev == event_name then return true end
   end
   return false
end

function M.emit(deal: DealState, actives: {ActiveBoon}, player_index: integer, event: EventData)
   for _, active in ipairs(actives) do
      local boon = catalog[active.boon_id]
      if boon ~= nil then
         if listens_for(boon, event.event_name) then
            local ctx = boon_context.make(deal, active, player_index)
            if boon.condition(ctx, event) then
               boon.effect(ctx, event)
            end
         end
      end
   end
end

return M
