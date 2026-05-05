-- Headless playtest harness for the AI.
--
-- Runs each seed to completion with all four seats driven by the AI module.
-- Reports per-seed outcomes plus aggregate metrics so each S07 commit can be
-- compared against the same baseline row.
--
-- Run with: make playtest
--
-- ── S06 baseline (recorded 2026-05-04, commit 8a1766b — S07 starting point)
--    Hu rate:           7 / 10  (seeds 42, 100, 12345, 7, 99, 200, 555)
--    Wall exhaustion:   3 / 10  (seeds 1, 2025, 31415)
--    Stuck/error:       0 / 10
--    avg steps/deal:    344.7
--    invalid actions:   0
--    call mix:          peng=64 chi=6 openK=11 concK=2 addK=4
--    target dist:       dui_dui_hu=7  (every Hu was a Dui Dui Hu)
--    pattern dist:      Dui Dui Hu=7
--
--    The S06 plan's completion summary cites 6/10; the actual merge tip is
--    7/10 because the user's PR-review fixes (compute_features suit-count
--    ordering, count_realized_modifiers wind stacking, known-wall draw
--    propagation across all seats) moved one wall exhaustion to a Hu. The
--    7/10 row above is the row each subsequent S07 commit must match or beat.
-- ───────────────────────────────────────────────────────────────────────────

package.path = "lua_compat/?.lua;src/?.lua;src/?/init.lua;" .. package.path

require("game.deal_types")
require("effects.effect_types")
local rng_mod    = require("core.rng")
local engine     = require("game.deal_engine")
local ai         = require("game.ai")
local invariants = require("game.deal_invariants")
local boons_init = require("effects.boons.init")

boons_init.reset_and_register_all()

local SEEDS = { 42, 1, 100, 12345, 7, 99, 200, 555, 2025, 31415 }
local MAX_STEPS = 4000

-- Returns a sorted list of hand_pattern reason labels from a Hu's score result.
local function hand_pattern_labels(score_result)
   local labels = {}
   for _, r in ipairs(score_result.reasons) do
      if r.category == "hand_pattern" then
         labels[#labels + 1] = r.label
      end
   end
   table.sort(labels)
   return labels
end

local function run_seed(seed)
   local call_counts = { peng = 0, chi = 0, open_kong = 0, concealed_kong = 0, added_kong = 0 }
   local invalid_actions = 0
   local last_target_by_seat = { [1] = "", [2] = "", [3] = "", [4] = "" }

   local rng = rng_mod.from_seed(seed)
   local rs = {
      round_index = 1,
      lives       = 3,
      active_effects = {},
      previous_win_rating = "",
      has_previous_win = false,
      rng         = rng,
   }
   local deal = engine.new_deal_with_run(rng, rs)
   if deal.phase == "opening_actions" then
      local tr = engine.apply_action(deal, engine.confirm_opening(1))
      if tr.ok then deal = tr.deal end
   end

   local steps = 0
   while deal.phase ~= "deal_over" and steps < MAX_STEPS do
      steps = steps + 1
      local action, reason
      local actor_index
      if deal.phase == "reaction_window" then
         local responded = {}
         for _, pi in ipairs(deal.reaction_passes) do responded[pi] = true end
         for _, c in ipairs(deal.pending_claims) do responded[c.player_index] = true end
         if deal.has_pending_discard then responded[deal.pending_discard.discarder] = true end
         if deal.has_pending_kong then responded[deal.pending_added_kong.declarer] = true end
         actor_index = nil
         for i = 1, 4 do
            if not responded[i] then actor_index = i; break end
         end
         if actor_index == nil then break end
         action, reason = ai.decide_reaction(deal, actor_index)
      else
         actor_index = deal.current_player
         action, reason = ai.decide_main(deal, actor_index)
      end

      if reason and reason.target and reason.target ~= "" then
         last_target_by_seat[actor_index] = reason.target
      end

      if action.kind == "declare_peng" then call_counts.peng = call_counts.peng + 1
      elseif action.kind == "declare_chi" then call_counts.chi = call_counts.chi + 1
      elseif action.kind == "declare_open_kong" then call_counts.open_kong = call_counts.open_kong + 1
      elseif action.kind == "declare_concealed_kong" then call_counts.concealed_kong = call_counts.concealed_kong + 1
      elseif action.kind == "declare_added_kong" then call_counts.added_kong = call_counts.added_kong + 1
      end

      local prev_phase = deal.phase
      local tr = engine.apply_action(deal, action)
      if not tr.ok then
         invalid_actions = invalid_actions + 1
         print(string.format("seed=%d step=%d action_kind=%s INVALID: %s",
            seed, steps, action.kind, tr.error or "?"))
         break
      end
      deal = tr.deal
      local inv = invariants.validate_tile_conservation(deal)
      if not inv.ok then
         print(string.format("seed=%d step=%d CONSERVATION FAIL after action_kind=%s prev_phase=%s new_phase=%s: %s",
            seed, steps, action.kind, prev_phase, deal.phase, inv.details))
         break
      end
   end

   local outcome_kind
   local outcome_label
   local winner_target = ""
   local winner_patterns = {}
   local winner_fan = 0
   if deal.phase == "deal_over" then
      if deal.has_deal_result and deal.deal_result.winner_player_index > 0 then
         local w = deal.deal_result.winner_player_index
         local zm = deal.deal_result.won_by_zi_mo and " (zi mo)" or ""
         outcome_kind = "hu"
         outcome_label = string.format("Hu by p%d%s", w, zm)
         winner_target = last_target_by_seat[w]
         if deal.deal_result.has_score_result then
            winner_patterns = hand_pattern_labels(deal.deal_result.score_result)
            winner_fan = deal.deal_result.score_result.total_fan
         end
      else
         outcome_kind = "wall"
         outcome_label = "wall exhaustion"
      end
   else
      outcome_kind = "stuck"
      outcome_label = string.format("STUCK at phase=%s after %d steps", deal.phase, steps)
   end

   print(string.format("seed=%5d steps=%4d outcome=%-30s calls: peng=%d chi=%d openK=%d concK=%d addK=%d invalid=%d",
      seed, steps, outcome_label,
      call_counts.peng, call_counts.chi, call_counts.open_kong,
      call_counts.concealed_kong, call_counts.added_kong, invalid_actions))
   if outcome_kind == "hu" then
      print(string.format("  winner target=%s fan=%d patterns=[%s]",
         winner_target ~= "" and winner_target or "(none)",
         winner_fan,
         table.concat(winner_patterns, ", ")))
   end

   return {
      seed = seed,
      outcome_kind = outcome_kind,
      outcome_label = outcome_label,
      steps = steps,
      calls = call_counts,
      invalid_actions = invalid_actions,
      winner_target = winner_target,
      winner_patterns = winner_patterns,
      winner_fan = winner_fan,
   }
end

local results = {}
for _, s in ipairs(SEEDS) do
   results[#results + 1] = run_seed(s)
end

-- ── Aggregates ─────────────────────────────────────────────────────────────
local hu_count, wall_count, stuck_count = 0, 0, 0
local total_steps = 0
local agg_calls = { peng = 0, chi = 0, open_kong = 0, concealed_kong = 0, added_kong = 0 }
local total_invalid = 0
local target_dist = {}    -- target name → count (at Hu)
local pattern_dist = {}   -- pattern label → count (at Hu, multi-pattern Hu counts each)

for _, r in ipairs(results) do
   if r.outcome_kind == "hu" then hu_count = hu_count + 1
   elseif r.outcome_kind == "wall" then wall_count = wall_count + 1
   else stuck_count = stuck_count + 1 end
   total_steps = total_steps + r.steps
   for k, v in pairs(r.calls) do agg_calls[k] = agg_calls[k] + v end
   total_invalid = total_invalid + r.invalid_actions
   if r.outcome_kind == "hu" then
      local tk = r.winner_target ~= "" and r.winner_target or "(none)"
      target_dist[tk] = (target_dist[tk] or 0) + 1
      for _, p in ipairs(r.winner_patterns) do
         pattern_dist[p] = (pattern_dist[p] or 0) + 1
      end
   end
end

local n = #SEEDS
print("")
print("Summary:")
print(string.format("  Hu rate:         %d / %d (%.0f%%)", hu_count, n, 100.0 * hu_count / n))
print(string.format("  wall exhaustion: %d / %d (%.0f%%)", wall_count, n, 100.0 * wall_count / n))
print(string.format("  stuck/error:     %d / %d (%.0f%%)", stuck_count, n, 100.0 * stuck_count / n))
print(string.format("  avg steps/deal:  %.1f", total_steps / n))
print(string.format("  invalid actions: %d total", total_invalid))
print(string.format("  call mix:        peng=%d chi=%d openK=%d concK=%d addK=%d",
   agg_calls.peng, agg_calls.chi, agg_calls.open_kong,
   agg_calls.concealed_kong, agg_calls.added_kong))

local function sorted_pairs(map)
   local keys = {}
   for k in pairs(map) do keys[#keys + 1] = k end
   table.sort(keys)
   local out = {}
   for _, k in ipairs(keys) do out[#out + 1] = string.format("%s=%d", k, map[k]) end
   return table.concat(out, " ")
end

if hu_count > 0 then
   print(string.format("  target dist:     %s", sorted_pairs(target_dist)))
   print(string.format("  pattern dist:    %s", sorted_pairs(pattern_dist)))
end
