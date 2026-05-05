# S06 Smart AI — current state and open problems

Snapshot at branch `agent/s06-smart-ai` head. Read this first if you're
picking up the AI work; it's the freshest summary of what's been built,
what's broken, and what to try next.

## Where we are

- Branch: `agent/s06-smart-ai`, 10 commits ahead of `main`.
- Tests: **195 / 0 / 0**.
- 10-seed playtest: **6 / 10 Hu**. Calls per deal: ~5–10 (peng-heavy
  with occasional chis and kongs). Up from a baseline of 3/10 with
  almost no calls.
- Seed 42 specifically: ends in p4 Hu at step 218 via three pengs
  building dui_dui_hu, with the 4th set landed by Hu-on-discard.

## What S06 was supposed to do

Replace the placeholder "discard the rightmost tile" AI with one that:

1. Picks a **target** hand pattern (default / dui_dui_hu / hun_yi_se /
   qing_yi_se).
2. Estimates fan reachable for that target through the boon-aware
   scoring runner (`estimate_fan_for_target`).
3. Gates calls on whether the post-call hand still has a 3-fan path
   (the HK minimum-fan threshold).
4. Discards via a target-aware ranking with ukeire and tile-value as
   tiebreaks.

The decision module is in `src_tl/game/ai.tl`; the heuristic kernel
(target picker, fan estimator, ukeire, tile-value, post-call ting) is
in `src_tl/game/ai_strategy.tl`. Both are pure — no LÖVE, no UI imports.

## How the AI works today

### `ai.decide_main` (own turn)

```
if awaiting_draw → DRAW
if awaiting_action:
   if zi_mo possible (evaluate_hu) → DECLARE_HU
   target := strategy.choose_target(...)
   if added kong AND post-kong has_3fan_target_hypothetical → DECLARE_ADDED_KONG
   if concealed kong AND ting doesn't regress AND post-kong has_3fan → DECLARE_CONCEALED_KONG
   tile := strategy.pick_best_discard(target, live)
   return DISCARD(tile)
```

### `ai.decide_reaction` (reaction window)

```
if can hu_on_discard (evaluate_hu) → DECLARE_HU
if can qiang_gang → DECLARE_HU on pending kong
if can open_kong AND post-call has_3fan → DECLARE_OPEN_KONG
if can peng AND post-call has_3fan → DECLARE_PENG
for each chi combo (only the next player can chi):
   if post-chi has_3fan → DECLARE_CHI
return PASS
```

The ting-regression check on peng/chi was removed earlier this session;
the gate is now purely "does a 3-fan target survive the call?"

### `strategy.choose_target` and `has_three_fan_target`

`choose_target` iterates `[default, dui_dui_hu, hun_yi_se, qing_yi_se]`,
computes `est_fan` and a per-target fitness from `compute_features`, and
picks the highest `(fitness × personality_weight)` among targets with
`est_fan >= 3` (default always passes). It returns `(target, est_fan)`.

`has_three_fan_target_hypothetical(rest, sets_after)` is the call gate:
swap in a hypothetical post-call hand, run `choose_target`, return true
if the chosen target's est_fan ≥ 3.

### `estimate_fan_for_target`

Synthesizes a `WinShape` and `ScoreResult` for the target, routes it
through `effect_runner.apply_score_modifiers` so AI-owned boons get
their say, and returns the result's total_fan. Now also includes:

- **Realized fan modifiers** counted from triplets/pengs/kongs (not
  pairs): Dragon Pung (+1 per dragon triplet), Seat Wind Pung,
  Round Wind Pung. So a peng of `fa_cai` correctly bumps est_fan by 1.
- **Feasibility gates** (Fix B from this session) — return 0 when the
  target's win shape is impossible from already-committed open sets.

### `pick_best_discard`

Ranks candidate discards by:
1. live ting after the discard (asc) — primary; never go dead just to
   satisfy a target.
2. **discard_priority** (desc) — target-aware. Drop "fight the target"
   tiles before "structural keepers." For dui_dui_hu, sequence-only
   singletons get priority 100 and pairs/triplets get 0; for
   qing_yi_se, honors and off-suit get high priority; for hun_yi_se,
   off-suit non-honor gets high priority. default is target-blind.
3. tile-value (asc) — drop low-value tiles for the chosen target.
4. tile_id (asc) for determinism.

Tile values come from two tables: `SEQUENCE_VALUE` (terminal=1,
edge=2, near=3, mid=4, honors=0) for sequence-leaning targets, and
`TRIPLET_VALUE` (honors and dragons high, mids medium) for dui_dui_hu.
Seat/round wind get +1 in TRIPLET_VALUE.

### `compute_features` (after Fix A this session)

For each hand:

- pair_count / triplet_count counted from concealed
- **Open peng/kong adds +1 to triplet_count** (Fix A)
- open_chi_count tracked separately (chis don't count as triplets)
- committed_suits, has_committed_honor exposed for feasibility gates
- max_suit / off_suit / honor_count include open-set tiles

## What changed this session

### Target-aware discards (Fix C)

`pick_best_discard` now uses a `discard_priority` secondary rank key
that follows through on the chosen target. Pre-fix the AI would peng
for dui_dui_hu and then drop sequence material in random order; the
hand reached "ting in shape" with dead waits and no win. Post-fix the
AI consistently peels off sequence singletons after committing to
dui_dui_hu (and off-suit/honors after committing to qing_yi_se /
hun_yi_se). Empirical impact: Hu rate 0/10 → 6/10.

### Fix A — open sets credited as triplets

`compute_features` now counts each open peng/kong as `triplet_count +=
1`. Before the fix, a peng matched a concealed pair and "ate" it: the
pair left concealed and the new triplet went to `sets`, but `triplet_count`
only saw concealed kinds with ≥3 copies. Net effect: dui_dui_hu fitness
*dropped by 2* per peng (lost pair-fitness with no triplet credit),
ties with default's flat 6.0, default wins iteration order, est_fan=1,
peng rejected.

Concrete case: seed 42 step 253. p1 has `4T 5T 8T 8T 9T 9T 3W 4W 5W 7W
5B 7B 7B` and is offered a peng of 8T. Pre-fix: dui_dui_hu fitness
post-peng = `2*2 + 0*3 = 4`, default = 6, default wins, est_fan=1,
peng rejected. Post-fix: `2*2 + 1*3 = 7`, dui_dui_hu wins, est_fan=3,
peng accepted.

### Fix B — target feasibility gates

`estimate_fan_for_target` now returns 0 when the target's win shape is
structurally impossible from the open sets already committed:

- `dui_dui_hu` with any open chi → 0 (pung-only forbids sequences)
- `qing_yi_se` with a committed honor or 2+ committed suits → 0
- `hun_yi_se` with 2+ committed suits → 0

`default` is intentionally not gated — it's the safety-net target that
always passes the OR clause in `choose_target`.

Concrete case: seed 42 step 407 (pre-fix order). p1 had a viable
dui_dui_hu trajectory, was offered a chi of 3T. Pre-fix:
`target_base_fan("dui_dui_hu") = 3` regardless of open chis, so
post-chi est_fan=3, has_3fan=true, chi accepted, hand died on the
next turn. Post-fix: dui_dui_hu gated to 0, default wins fitness,
est_fan=1, has_3fan=false, chi rejected.

### Chi-simulation tile fix

`ai.decide_reaction` was passing `tiles = {}` for the simulated chi
set. `compute_features` couldn't tell what suit the chi committed to,
so `committed_suits` was empty and the qing_yi_se / hun_yi_se gates
miscounted. Now the simulation populates `tiles = { pair_a, pair_b,
discarded }` so feasibility checks see the real committed suit.

### Display fixes (orthogonal)

`src_tl/scenes/table_scene.tl`: concealed hands now display in
mahjong order (tiao 1-9 → wan 1-9 → bing 1-9 → E S W N → F H B);
hand/sets/discards/log lines wrap at panel width instead of
overflowing into adjacent panels.

## What seed 42 looks like now

p4 builds dui_dui_hu cleanly through three pengs and finishes on a
discard:

- **Opp 1** (step 45): pengs 1W. Hand had four pairs — strong
  dui_dui_hu fitness. Post-peng triplet_count=1 (Fix A) keeps fitness
  ≥ default. Accepted.
- **Opp 6** (step 107): pengs 4T. Second triplet locked in.
- **Opp 9** (step 170): pengs 8W. Third triplet locked in.
- **Opp 13** (step 218): sees p1 discard 5T, declares Hu. Hand
  resolves to 3 pengs + 5T-5T-5T pung + 3W-3W pair = 4 triplets +
  pair = dui_dui_hu (3 fan, valid).

p1's pivotal call — the chi at the old step 407 that killed their
hand — no longer exists in this branch's deal flow because earlier
calls landed differently. p1 ends in TING with a partly playable hand
when the deal closes.

## Open problems, ranked

### 1. Live-ukeire reachability on calls

The current call gate accepts when post-call has a 3-fan target. It
doesn't check whether the AI's projected waits are *alive*. A peng can
still land the AI in a shape where the only completions have live
count 0. The gate should require post-call ukeire ≥ K live tiles for
the projected shape so the AI doesn't peng into an already-dead wait.

Smaller scope than the discard fix that just landed; should reduce
the "ting in shape but no live tile" failure mode visible in the
remaining wall-exhaustion seeds.

### 2. Qi Dui (seven pairs) isn't a target

`docs/INITIAL-DESIGN.md` lists Qi Dui (七對, 4 fan) as a valid hand
pattern, but `choose_target` only considers default / dui_dui_hu /
hun_yi_se / qing_yi_se. A concealed hand with 5–6 pairs that's
naturally on a Qi Dui trajectory currently targets dui_dui_hu (which
needs triplets, not pairs) and shapes wrong.

Adding Qi Dui as a target requires:
- A `target_base_fan("qi_dui") = 4` entry.
- Feasibility gate: any open set kills Qi Dui (concealed-only).
- Fitness based on `pair_count`.
- Discard priority: drop singletons (anything not paired).

### 3. Default's flat 6.0 fitness creates ties

`target_fitness("default") = 6.0` deterministically. dui_dui_hu's
fitness can equal 6.0 exactly (3 pairs, no triplets, no honor pairs),
and the iteration order makes default win. Fix A made this rarer (open
sets bump triplet_count) but ties still happen. Either:

- Add a small bonus to non-default targets when est_fan ≥ 3 to break
  ties in favor of the structurally specific path, or
- Replace default's flat 6.0 with a feature-based score (e.g., count
  sequence-friendly tiles), or
- Just use `>=` instead of `>` and prefer non-default in ties.

This is purely a tiebreak fix; impact varies by seed.

### 4. AiPersonality is mostly inert

The `AiPersonality` record has `target_weights` and `call_appetite` but
M1 only ships `NEUTRAL_PERSONALITY`. Opponent packages (Triplet Hunter,
Defensive Wall, Fast Hand from `INITIAL-DESIGN.md`) become trivial
once we want to ship them — they're just different weights and a
call_appetite multiplier.

## What I'd do next session

In order:

1. **Audit per-seat decisions with mahjong-expert review** — one
   agent per seat for seed 42, briefed on HK rules + per-step trace.
   The user requested this before pivoting to the discard fix; we
   have the trace plumbing (`/tmp/s06_call_log.lua`,
   `/tmp/s06_p1_trace.lua`) — just generalize the per-seat trace.
   Goal: surface remaining systematic gaps the playtest stats can't
   show.

2. **Live-ukeire reachability** as a second-order gate refinement.
   Reduces the "ting in shape but dead in waits" failure mode.

3. **Qi Dui as a target** — concealed-only, base 4 fan. Helps hands
   that are naturally pair-heavy and don't fit dui_dui_hu's open-set
   pattern.

4. **Default's tiebreak** — one-liner (use `>=` in
   `choose_target`'s tiebreak); fold into whichever of the above
   we're touching.

5. **Land S06**, write the slice completion notes in
   `docs/MILESTONE-1-PLAN.md` (already partly done at commit `c7c7dc6`,
   needs an update for what changed since).

## Files of interest

- `src_tl/game/ai.tl` — decision module entry points, gate logic
- `src_tl/game/ai_strategy.tl` — heuristic kernel (target picker, fan
  estimator, post-call ting, ukeire, discard ranking)
- `src_tl/game/ting_distance.tl` — `ting_distance_standard`,
  `ting_distance_standard_live`, combined variants
- `spec_tl/ai_strategy_spec.tl` — unit tests for the heuristic kernel
- `docs/playtest-logs/seed42-call-decisions.md` — per-opportunity log
  for seed 42 (pre-fix; can be regenerated with `lua
  /tmp/s06_call_log.lua 42`)
- `/tmp/s06_call_log.lua` — call-decision log generator
- `/tmp/s06_p1_trace.lua` — per-seat hand-evolution trace generator
  (currently hardcoded for FOCUS=1 via arg, easy to generalize)
- `/tmp/s06_playtest.lua` — headless 10-seed playtest driver
