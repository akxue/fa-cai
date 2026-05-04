-- Effect runner: orchestrates queries and command application across active
-- effects. Pure rules layer — no love/ui/scenes/app imports. The runner is
-- the only place score modifiers, draw hooks, peng hooks, and opening hooks
-- are stitched into the engine.

require("core.types")
require("core.rng")
require("game.deal_types")
require("effects.effect_types")
local registry = require("effects.effect_registry")
local wall_mod = require("game.wall")

local M = {}

-- ── Fan → rating (mirror of scorer.tl, kept in sync) ──────────────────────

local function fan_to_rating(fan: integer): Rating
   if fan >= 10 then return "SS" as Rating
   elseif fan >= 8 then return "S" as Rating
   elseif fan >= 6 then return "A" as Rating
   elseif fan >= 4 then return "B" as Rating
   else return "C" as Rating
   end
end

-- ── Effect collection helpers ─────────────────────────────────────────────

local function actives_for(deal: DealState): {ActiveEffectState}
   local list: {ActiveEffectState} = {}
   for _, a in pairs(deal.effect_states) do
      list[#list + 1] = a
   end
   return registry.sorted_for(list)
end

-- ── Score integration ────────────────────────────────────────────────────
--
-- Re-runs score reasons through every registered effect, appends them to the
-- base ScoreResult, then recomputes total_fan, valid_hu, and rating.
--
-- valid_hu re-evaluation mirrors scorer.tl exactly: limit OR total_fan >= 3.
-- Effects cannot bypass the 3-fan minimum.

function M.apply_score_modifiers(
   deal:           DealState,
   ctx:            ScoreContext,
   shape:          WinShape,
   base:           ScoreResult,
   player_index:   integer
): ScoreResult
   local merged_reasons: {ScoreReason} = {}
   for _, r in ipairs(base.reasons) do
      merged_reasons[#merged_reasons + 1] = r
   end

   local actives = actives_for(deal)
   for _, a in ipairs(actives) do
      local mod = registry.get(a.effect_id)
      if mod ~= nil and mod.on_score ~= nil then
         local sctx: EffectScoreContext = {
            active       = a,
            ctx          = ctx,
            shape        = shape,
            player_index = player_index,
         }
         local extra = mod.on_score(sctx, deal)
         if extra ~= nil then
            for _, r in ipairs(extra) do
               merged_reasons[#merged_reasons + 1] = r
            end
         end
      end
   end

   local total_fan = 0
   local is_limit = base.is_limit
   for _, r in ipairs(merged_reasons) do
      total_fan = total_fan + r.fan
      if r.is_limit then is_limit = true end
   end

   local valid_hu = is_limit or total_fan >= 3
   local rating: Rating
   if is_limit then
      rating = "Legend" as Rating
   else
      rating = fan_to_rating(total_fan)
   end

   return {
      win_shape_kind = base.win_shape_kind,
      reasons        = merged_reasons,
      total_fan      = total_fan,
      is_limit       = is_limit,
      rating         = rating,
      valid_hu       = valid_hu,
   }
end

-- ── Hook dispatch ────────────────────────────────────────────────────────

function M.dispatch_after_draw(
   deal:          DealState,
   player_index:  integer,
   drawn_tile:    Tile,
   is_supplement: boolean
): {EffectCommand}
   local out: {EffectCommand} = {}
   local actives = actives_for(deal)
   for _, a in ipairs(actives) do
      if not a.has_owner or a.owner_player_index == player_index then
         local mod = registry.get(a.effect_id)
         if mod ~= nil and mod.on_after_draw ~= nil then
            local hctx: EffectAfterDrawContext = {
               active        = a,
               player_index  = player_index,
               drawn_tile    = drawn_tile,
               is_supplement = is_supplement,
            }
            local cmds = mod.on_after_draw(hctx, deal)
            if cmds ~= nil then
               for _, c in ipairs(cmds) do out[#out + 1] = c end
            end
         end
      end
   end
   return out
end

function M.dispatch_after_peng(
   deal:         DealState,
   player_index: integer
): {EffectCommand}
   local out: {EffectCommand} = {}
   local actives = actives_for(deal)
   for _, a in ipairs(actives) do
      if not a.has_owner or a.owner_player_index == player_index then
         local mod = registry.get(a.effect_id)
         if mod ~= nil and mod.on_after_peng ~= nil then
            local hctx: EffectAfterPengContext = { active = a, player_index = player_index }
            local cmds = mod.on_after_peng(hctx, deal)
            if cmds ~= nil then
               for _, c in ipairs(cmds) do out[#out + 1] = c end
            end
         end
      end
   end
   return out
end

function M.dispatch_opening_deal_complete(
   deal:        DealState,
   round_index: integer
): {EffectCommand}
   local out: {EffectCommand} = {}
   local actives = actives_for(deal)
   for _, a in ipairs(actives) do
      local mod = registry.get(a.effect_id)
      if mod ~= nil and mod.on_opening_deal_complete ~= nil then
         local hctx: EffectOpeningContext = { active = a, round_index = round_index }
         local cmds = mod.on_opening_deal_complete(hctx, deal)
         if cmds ~= nil then
            for _, c in ipairs(cmds) do out[#out + 1] = c end
         end
      end
   end
   return out
end

function M.collect_opening_modifiers(
   actives:     {ActiveEffectState},
   round_index: integer
): OpeningModifiers
   local extra = 0
   local sorted = registry.sorted_for(actives)
   for _, a in ipairs(sorted) do
      local mod = registry.get(a.effect_id)
      if mod ~= nil and mod.collect_opening_modifiers ~= nil then
         local m = mod.collect_opening_modifiers(a, round_index)
         if m ~= nil then
            extra = extra + m.extra_opening_tiles
         end
      end
   end
   return { extra_opening_tiles = extra }
end

function M.collect_available_actions(
   deal:         DealState,
   player_index: integer
): {EffectAction}
   local out: {EffectAction} = {}
   local actives = actives_for(deal)
   for _, a in ipairs(actives) do
      if not a.has_owner or a.owner_player_index == player_index then
         local mod = registry.get(a.effect_id)
         if mod ~= nil and mod.collect_available_actions ~= nil then
            local acts = mod.collect_available_actions(a, deal, player_index)
            if acts ~= nil then
               for _, ea in ipairs(acts) do out[#out + 1] = ea end
            end
         end
      end
   end
   return out
end

-- ── Command application ──────────────────────────────────────────────────
--
-- The engine deep-copies the deal before calling apply_commands. This module
-- mutates the passed-in deal directly; that is safe because the engine owns
-- the copy semantics.

local function copy_tile_ids(ids: {TileId}): {TileId}
   local out: {TileId} = {}
   for _, id in ipairs(ids) do out[#out + 1] = id end
   return out
end

local function apply_increment_counter(deal: DealState, c: IncrementCounterCommand): {DealEvent}
   local a = deal.effect_states[c.active_effect_id]
   if a == nil then return {} end
   a.counters[c.counter_key] = (a.counters[c.counter_key] or 0) + c.delta
   return {}
end

local function apply_set_counter(deal: DealState, c: SetCounterCommand): {DealEvent}
   local a = deal.effect_states[c.active_effect_id]
   if a == nil then return {} end
   a.counters[c.counter_key] = c.value
   return {}
end

local function apply_mark_used(deal: DealState, c: MarkUsedCommand): {DealEvent}
   local a = deal.effect_states[c.active_effect_id]
   if a == nil then return {} end
   a.used_this_deal = true
   return {}
end

local function apply_reveal_wall_front(deal: DealState, c: RevealWallFrontCommand): {DealEvent}
   local available = wall_mod.remaining(deal.wall)
   local count = c.count
   if count > available then count = available end
   -- Front tiles are at indices 1..count in wall.tiles.
   for i = 1, count do
      local tile_id = deal.wall.tiles[i].tile_id
      -- Avoid duplicate insertion if already known.
      local already = false
      for _, existing in ipairs(deal.known_wall_tile_ids) do
         if existing == tile_id then already = true; break end
      end
      if not already then
         deal.known_wall_tile_ids[#deal.known_wall_tile_ids + 1] = tile_id
      end
   end
   return {}
end

-- Removes a single tile by id from a {Tile} list, returning the removed tile
-- and a boolean indicating success.
local function remove_tile_by_id(tiles: {Tile}, tile_id: TileId): Tile, boolean
   for i, t in ipairs(tiles) do
      if t.tile_id == tile_id then
         table.remove(tiles, i)
         return t, true
      end
   end
   return {} as Tile, false
end

local function apply_replace_concealed_tiles(deal: DealState, c: ReplaceConcealedTilesCommand): {DealEvent}
   local p = deal.players[c.player_index]
   if p == nil then return {} end

   -- 1) Remove the chosen tiles from concealed.
   local returned: {Tile} = {}
   for _, tid in ipairs(c.tile_ids_to_remove) do
      local t, ok = remove_tile_by_id(p.hand.concealed_tiles, tid)
      if ok then returned[#returned + 1] = t end
   end

   -- 2) Return them to the wall, optionally reshuffling. Reshuffling
   --    invalidates Known Wall (the previously-revealed front tiles are no
   --    longer at the front), so we clear it.
   if c.reshuffle_wall then
      local r = wall_mod.return_and_reshuffle(deal.wall, returned, deal.rng)
      deal.wall = r.wall
      deal.rng  = r.rng
      deal.known_wall_tile_ids = {}
   else
      for _, t in ipairs(returned) do
         deal.wall.tiles[#deal.wall.tiles + 1] = t
      end
   end

   -- 3) Draw replacements from the (possibly reshuffled) front.
   for _ = 1, #returned do
      local dr = wall_mod.draw_front(deal.wall)
      deal.wall = dr.wall
      p.hand.concealed_tiles[#p.hand.concealed_tiles + 1] = dr.tile
   end

   return {}
end

local function apply_add_log(_deal: DealState, c: AddLogCommand): {DealEvent}
   local ev: DealEvent = { kind = "effect_log", message = c.message }
   return { ev }
end

-- Returns events accumulated from log commands. State mutations happen on the
-- passed deal directly (engine has already copied it).
function M.apply_commands(deal: DealState, commands: {EffectCommand}): {DealEvent}
   local events: {DealEvent} = {}
   for _, c in ipairs(commands) do
      local kind = c.command_kind
      if kind == "increment_counter" then
         local out = apply_increment_counter(deal, c as IncrementCounterCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      elseif kind == "set_counter" then
         local out = apply_set_counter(deal, c as SetCounterCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      elseif kind == "mark_used" then
         local out = apply_mark_used(deal, c as MarkUsedCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      elseif kind == "reveal_wall_front" then
         local out = apply_reveal_wall_front(deal, c as RevealWallFrontCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      elseif kind == "replace_concealed_tiles" then
         local out = apply_replace_concealed_tiles(deal, c as ReplaceConcealedTilesCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      elseif kind == "add_log" then
         local out = apply_add_log(deal, c as AddLogCommand)
         for _, e in ipairs(out) do events[#events + 1] = e end
      else
         error("apply_commands: unknown command_kind: " .. tostring(kind))
      end
   end
   return events
end

-- ── Builders for commands (typed boundary) ────────────────────────────────

function M.cmd_increment_counter(active_effect_id: string, counter_key: string, delta: integer): EffectCommand
   local c: IncrementCounterCommand = {
      command_kind     = "increment_counter",
      active_effect_id = active_effect_id,
      counter_key      = counter_key,
      delta            = delta,
   }
   return c as EffectCommand
end

function M.cmd_set_counter(active_effect_id: string, counter_key: string, value: integer): EffectCommand
   local c: SetCounterCommand = {
      command_kind     = "set_counter",
      active_effect_id = active_effect_id,
      counter_key      = counter_key,
      value            = value,
   }
   return c as EffectCommand
end

function M.cmd_mark_used(active_effect_id: string): EffectCommand
   local c: MarkUsedCommand = { command_kind = "mark_used", active_effect_id = active_effect_id }
   return c as EffectCommand
end

function M.cmd_reveal_wall_front(count: integer): EffectCommand
   local c: RevealWallFrontCommand = { command_kind = "reveal_wall_front", count = count }
   return c as EffectCommand
end

function M.cmd_replace_concealed_tiles(player_index: integer, tile_ids_to_remove: {TileId}, reshuffle_wall: boolean): EffectCommand
   local c: ReplaceConcealedTilesCommand = {
      command_kind        = "replace_concealed_tiles",
      player_index        = player_index,
      tile_ids_to_remove  = copy_tile_ids(tile_ids_to_remove),
      reshuffle_wall      = reshuffle_wall,
   }
   return c as EffectCommand
end

function M.cmd_add_log(message: string): EffectCommand
   local c: AddLogCommand = { command_kind = "add_log", message = message }
   return c as EffectCommand
end

return M
