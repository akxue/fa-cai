-- Effect registry: holds EffectModule definitions keyed by effect_id and
-- exposes deterministic ordered iteration. Pure — no love/ui/scenes/app.

require("effects.effect_types")

local M = {}

local modules: {string: EffectModule} = {}

-- Default registration order is captured for tie-breaking when priorities
-- match; we still sort by (priority, effect_id) for full determinism.

function M.register(mod: EffectModule)
   if mod == nil then
      error("register: nil effect module")
   end
   local id = mod.metadata.effect_id
   if id == nil or id == "" then
      error("register: effect module missing effect_id")
   end
   modules[id] = mod
end

function M.get(effect_id: string): EffectModule
   return modules[effect_id]
end

function M.has(effect_id: string): boolean
   return modules[effect_id] ~= nil
end

-- Sorted iteration: returns the modules referenced by `actives`, sorted by
-- (priority asc, effect_id asc). Skips ids that have no registered module.
function M.sorted_for(actives: {ActiveEffectState}): {ActiveEffectState}
   local resolved: {ActiveEffectState} = {}
   for _, a in ipairs(actives) do
      if modules[a.effect_id] ~= nil then
         resolved[#resolved + 1] = a
      end
   end
   table.sort(resolved, function(x: ActiveEffectState, y: ActiveEffectState): boolean
      local mx = modules[x.effect_id]
      local my = modules[y.effect_id]
      local px = mx.metadata.priority
      local py = my.metadata.priority
      if px ~= py then
         return px < py
      end
      if mx.metadata.effect_id ~= my.metadata.effect_id then
         return mx.metadata.effect_id < my.metadata.effect_id
      end
      return x.active_effect_id < y.active_effect_id
   end)
   return resolved
end

-- Test/utility: clears all registrations. Use with care; production code
-- registers once at startup.
function M.reset()
   modules = {}
end

return M
