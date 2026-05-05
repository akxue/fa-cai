# Decisions

This file records durable decisions that should survive beyond one task or PR.

Keep entries short. Prefer one decision per entry. If a later decision replaces an earlier one, add a new entry and mark the old one as superseded instead of rewriting history.

## Format

```md
## D000: Short Decision Title

Status: accepted | superseded | proposed

Context:
- What problem forced the decision?

Decision:
- What are we doing?

Reason:
- Why is this the right tradeoff now?

Implications:
- What should future agents remember?
```

## D001: Build With LÖVE And Teal

Status: accepted

Context:
- facai should be a flexible, bespoke 2D roguelike mahjong game with a distinct feel.
- Much of the code will be written by AI agents, so typing and tests matter.

Decision:
- Use LÖVE as the runtime and Teal as the authored language.

Reason:
- LÖVE gives the project a lightweight code-first game runtime.
- Teal adds type pressure that helps agents avoid silent Lua table-shape drift.

Implications:
- Authored source lives in `src_tl/`.
- Generated Lua lives in `src/` and must not be committed.
- Tooling should make typecheck/build/test commands boring and repeatable.

## D002: Core Rules Must Not Depend On LÖVE

Status: accepted

Context:
- facai's hardest problems are deterministic rules, scoring, effects, AI, and tile conservation.
- Those systems need fast tests and reproducible seeded behavior.

Decision:
- `core`, `game`, `content`, and `effects` must not import or call LÖVE APIs.

Reason:
- Keeping LÖVE at the app/UI shell makes rules portable, testable, and easier for agents to reason about.

Implications:
- Randomness in core rules goes through `core/rng.tl`.
- Save/load goes behind app adapters.
- UI and scenes dispatch actions into the engine instead of mutating rules state directly.

## D003: Use A Lightweight Milestone/Slice/Task Workflow

Status: accepted

Context:
- Agent-coded projects become unreliable when broad requests turn directly into large edits.
- facai needs human-in-the-loop review without heavyweight project management.

Decision:
- Use `docs/MILESTONE-1-PLAN.md` as the canonical Milestone 1 source of truth.
- Organize work as Milestone 1 -> Slice -> Task.
- Each implementation PR should reference the slice/task it addresses.

Reason:
- Small accepted slices give agents enough context to work safely and give humans a clear review surface.

Implications:
- Do not start implementation from a broad request unless the user explicitly asks to skip planning.
- If a change creates a durable architecture or rules decision, update this file.

## D004: Use PRs As The Human Review Gate

Status: accepted

Context:
- The user wants human-in-the-loop control over agent changes and future GitHub Actions verification.

Decision:
- Development should happen through focused branches and PRs.
- Code changes should not be merged without human review.

Reason:
- PRs create a durable checkpoint for design intent, rules correctness, architecture boundaries, tests, and CI.

Implications:
- Branches should be small and named by task area.
- PRs should include scope, changed files, verification, screenshots/clips for UI, and open questions.
- CI should be added only after local `make check` and `make test` exist.

## D005: Effects Produce Commands; The Engine Applies; The Runner Is The Only Score Modifier Hook

Status: accepted

Context:
- Boons (and later relics, classes, opponent packages, boss auras, challenge modifiers) need to extend rules without forking core engine code.
- Score modifiers are the most invasive hook: a careless implementation could let boons bypass the 3-fan minimum or change Hu shape validation.

Decision:
- Effect modules implement read-only query hooks (`on_score`, `collect_opening_modifiers`, `collect_available_actions`) and lifecycle hooks that return typed `EffectCommand` values (`on_after_draw`, `on_after_peng`, `on_opening_deal_complete`, `on_use_action`).
- The engine deep-copies the deal, the runner applies commands to that copy, and the engine returns the new state.
- For scoring, the scorer always runs first and chooses the best win shape; only then does `effect_runner.apply_score_modifiers` append boon `ScoreReason`s and recompute `total_fan` / `valid_hu` using the same rule the scorer uses (`is_limit or total_fan >= 3`).

Reason:
- Effects cannot mutate core state directly, so they cannot violate invariants.
- Hu shape validation runs before any boon contribution, so boons cannot legalize a non-Hu hand.
- The 3-fan minimum is re-evaluated after boon fan, so a boon that adds fan to a hand still needs the hand to clear the threshold; nothing about the runner shortcuts this.

Implications:
- Adding a new effect requires: a metadata record in `content/`, a behavior module in `effects/boons/` (or a future folder for non-boon effects), and registration in the boons init.
- New command kinds extend the typed envelope and the dispatcher in `effect_runner.apply_commands`. They must also have a builder function so call sites stay typed.
- Reshuffling the wall invalidates Known Wall information, so `replace_concealed_tiles` with `reshuffle_wall=true` clears `known_wall_tile_ids`.
- AI-only effects in future slices follow the same pattern; the runner already filters by owner via `has_owner` and `owner_player_index`.

## D006: AI Is A Pure Decision Function; The Scene Drives Turn Pumping

Status: accepted

Context:
- The deal engine is a pure state machine driven by `DealAction`s. AI must use the same path as the human player.
- Either the engine could pump AI turns automatically, or an outer driver (the table scene) could call AI for non-human seats and dispatch the returned action.

Decision:
- AI lives in `src_tl/game/ai.tl` as pure decision functions: `decide_main(deal, player_index)` for the AI's own turn, `decide_reaction(deal, player_index)` for reaction windows.
- Both return `(DealAction, AiReasoning)`. The scene is responsible for calling AI when a non-human seat needs to act, dispatching the action through `engine.apply_action`, and surfacing the reasoning in the log/inspector.
- `deal_engine` knows nothing about AI.

Reason:
- Keeps the engine purely rules-driven and trivial to test in isolation.
- Reaction windows already require multi-seat polling that the engine handles via priority resolution; the scene already needs to coordinate which seats have/haven't responded, so it's the natural driver.
- Lets us swap AI implementations (vanilla, defensive, opponent packages) by replacing the function call, not by reshaping the engine.

Implications:
- AI must not import `love`, `ui`, `scenes`, or `app`, and must not read `known_wall_tile_ids` (player-only information).
- AI returns `DealAction`s only; never mutates `DealState` directly.
- `AiReasoning` is a structured record (tag, message, ting_before, ting_after) returned alongside the action; events stay free of subjective AI commentary.
- Future opponent packages plug into the same two functions or layer on top through composition; no engine changes required.

## D007: Generate Lua 5.1 With A `bit32` Polyfill

Status: accepted

Context:
- LÖVE 11.x ships LuaJIT 2.1, which only parses Lua 5.1 syntax. The `~`, `<<`, `>>`, `&` bitwise operators used by `core/rng.tl` are 5.3+ syntax and fail to load under LuaJIT.
- Lua 5.4 (used by `make test` via busted) dropped the `bit32` library entirely.
- LuaJIT ships `bit` (with the same function set under different naming) but not `bit32`; Teal generates `bit32.*` calls when targeting 5.1.

Decision:
- Set `gen_target = "5.1"` in `tlconfig.lua` so generated Lua is parseable by LuaJIT.
- Ship a hand-written `lua_compat/bit32.lua` polyfill that aliases LuaJIT's `bit` if available, and otherwise compiles a 5.3+-syntax implementation via `load()` to stay parseable under any Lua.
- `make build` copies the polyfill to `src/bit32.lua` so LÖVE's package path picks it up.
- `make test` adds `lua_compat/?.lua` to busted's lpath so Lua 5.4 also resolves `require("bit32")`.

Reason:
- One generated artifact set keeps the build tree simple — same code runs in tests and in LÖVE.
- The polyfill is a few lines; avoiding it would require maintaining two build targets or carrying a runtime dependency.

Implications:
- New runtime-only Lua compat shims belong in `lua_compat/` (committed); generated outputs in `src/` and `spec/` remain untracked.
- Anyone adding code that uses Lua 5.3-only features beyond bitwise ops (e.g., integer/float distinction, `goto`, `<close>`) must either ship a similar shim or stay within the 5.1 dialect.

## D008: Smart AI Is A Target-Pattern Heuristic With A Personality Parameter

Status: accepted

Context:
- The S05 vanilla AI minimized live-ting distance only. Playtesting (seed=42) showed AIs reaching ting on 1-fan hands they could never legally Hu under the 3-fan minimum, leading to wall exhaustion.
- Phase 0+ adds opponent packages (Pure Suit, Triplet Hunter, Dragon Chaser, Concealed Hand, Fast Hand, Legend Chaser) that are mostly AI behavior priors, not rule changes. Future modes may also give AIs real boons.
- The architecture must support both "smarter vanilla AI now" and "personality / package / boon-aware AI later" without a rewrite.

Decision:
- AI strategy lives in a new `src_tl/game/ai_strategy.tl` module. It picks one of four target patterns each turn — `dui_dui_hu`, `hun_yi_se`, `qing_yi_se`, or `default`. Targets are recomputed fresh each turn in v1; soft stickiness is deferred unless playtesting shows visible flapping.
- The discard heuristic ranks candidate discards by `(filtered_ting_distance, ukeire, target_alignment, tile_value)` where `filtered_ting_distance` treats targets whose pre-ting fan ceiling is < 3 as infinity.
- Two distinct fan calculations: `evaluate_hu` (existing) handles real Hu legality at ting using the validator + `scorer.score_hand` + `effect_runner.apply_score_modifiers` chain. A new `estimate_fan_for_target` handles pre-ting fan ceilings by constructing a synthetic `ScoreResult` from the target's implied structural facts and routing it through `effect_runner.apply_score_modifiers`. Both paths run boons through the runner, so AI-owned boons contribute uniformly whether the AI is at ting or several tiles away.
- `ai_strategy` accepts an `AiPersonality` parameter (target weights, call appetite, tile-value bias). Vanilla AI passes a `NEUTRAL` personality. Opponent packages and AI-owned-boon modes plug in through this same parameter.
- `ai.decide_main` and `ai.decide_reaction` retain their `(DealAction, AiReasoning)` contract. `AiReasoning` gains an optional `target` field surfaced in the inspector when set; non-target reasoning tags (`pass_reaction`, `zi_mo`, `hu_on_discard`) leave it unset.

Reason:
- Target-pattern heuristics are the well-established baseline for mahjong AI (riichi research; ukeire + yaku targeting + tile-value tables). They produce inspectable, explainable play without training a model.
- Routing projected fan through the effect runner makes the AI boon-aware now even though M1 vanilla AIs have no boons. When AIs gain boons in a later slice, no new wiring is needed.
- The personality parameter unifies "smarter vanilla AI" and "opponent packages" under one API. Packages become biased weights, not new code paths.

Implications:
- Adding an opponent package = construct a non-neutral `AiPersonality`. No engine or strategy-module changes.
- AI must continue to use only `DealAction`s; never mutates state directly.
- Hu legality and 3-fan minimum continue to flow through `evaluate_hu` / the runner — the strategy module never bypasses validation.
- Acceptance is partly manual: heuristic *quality* is validated by playing 5 seeds through the F1 scene, not by automated wins-per-game tests. Automated tests cover correctness (target selection on canonical inputs, ukeire arithmetic, `estimate_fan_for_target` ceilings, and a forward-compat synthetic-boon test that locks in the runner integration).
- Limit hands and Seven Pairs are not initial targets; vanilla AI will still happen to reach them when the hand naturally falls into shape, but won't pursue them deliberately.

## D009: Known Wall Is Per-Player State

Status: accepted

Context:
- `DealState.known_wall_tile_ids` was introduced as a deal-global flat list because in S04 only the player owned info boons (Third Eye, Open Eyes, Fresh Start). The "AI must not read `known_wall_tile_ids`" rule kept the singular shape working.
- S06 plans Smart AI infrastructure that opponent packages and future AI-owned info boons will plug into. AIs at that point will need their own per-seat known-wall view, and a deal-global list cannot represent four independent visibility states.
- Migrating later costs the same code change *plus* a re-test pass on every site that touched the field.

Decision:
- Move `known_wall_tile_ids` from `DealState` onto `PlayerState`. Each seat owns its own list.
- `RevealWallFrontCommand` writes to the *owning* player's list, using the active effect's `owner_player_index`.
- Fresh Start's reshuffle clears the *owning* player's list (not all players).
- Normal-draw bookkeeping removes the drawn tile id from the *drawer's* list only.
- The AI rule changes from "AI must not read `known_wall_tile_ids`" to "AI may read its own seat's `known_wall_tile_ids`". M1 vanilla AIs still read nothing because no AI owns an info effect yet.

Reason:
- Forward-compat for AI-owned info effects (boons or opponent packages) without a second migration.
- "The known wall" was only ever singular by accident of which seats had info boons in Phase 0 — a property of state ownership, not state shape.
- Migration cost is fixed; paying it now also pays for the test audit, which would otherwise come later.

Implications:
- Tile conservation invariant is unaffected — known-wall tiles are still in the wall regardless of visibility metadata.
- Tests that previously asserted on `d.known_wall_tile_ids` now assert on `d.players[player_index].known_wall_tile_ids`.
- Inspector still shows known wall size; in M1 only `players[1].known_wall_tile_ids` is non-empty.
- Future "shared known wall" effects, if they ever exist, would need to populate every owning player's list explicitly — there is no shared bucket to fall back on.

## D010: Rebuild AI As A Candidate-Record Pipeline (Post-S06)

Status: accepted

Context:
- S06 shipped a working target-pattern heuristic (`target_fitness`, `discard_priority`, `SEQUENCE_VALUE` / `TRIPLET_VALUE` tables, `choose_target` lexicographic chain, `has_three_fan_target` gate). Final empirical state: Hu 6/10 on the standard 10-seed sweep, 195 tests passing.
- The S06 implementation accumulated patches (Fix A: open sets credited as triplets; Fix B: target feasibility gates; target-aware discards via `discard_priority`; the `post_call_ting` math fix; the chi-simulation tile-population fix). Each fix individually closes a real hole. Together they reveal that the underlying mechanism is a stack of magic numbers that should be derived, not declared.
- A four-agent mahjong-expert audit on seed 42 (one agent per seat, briefed on HK rules) surfaced systematic gaps the current architecture can't naturally express: visible depletion of needed tiles, fan-grounded probability of completion, post-call best-candidate evaluation, honor-singleton tiebreak by live count, target re-evaluation under board pressure. See `docs/playtest-logs/s06-ai-state.md`.
- Cross-project research (`docs/AI-RESEARCH-NOTES.md`) finds the same shape across mature mahjong AIs (tenhou-python-bot, Aleo, AlphaJong, Mortal): a candidate-record pipeline carrying structured metrics (target distribution, ting, ukeire, expected fan, visible depletion, danger), filtered by legality, ranked by personality-weighted utility. Every research learning we surveyed plugs into this pipeline at a known place; the current code can't absorb them without more ad-hoc plumbing.

Decision:
- Open `S07: AI Candidate Pipeline` as the next AI slice. Rebuild the heuristic kernel — `pick_best_discard`, the call gates' bodies, `target_fitness`, `discard_priority`, the magic-number tile-value tables, `choose_target`'s explicit branching, `has_three_fan_target` — as a single candidate-record pipeline.
- Keep all engine-facing helpers unchanged: `evaluate_hu`, `compute_live_counts`, `count_realized_modifiers`, `effect_runner.apply_score_modifiers`, the `ting_distance` family, `post_call_ting`, the chi-simulation tile-population fix.
- Land a checked-in playtest harness (`scripts/playtest.lua` + `make playtest`) as the slice's first commit so every subsequent change is measured against the S06 baseline (Hu 6/10) instead of vibes-tuned.
- Sequence: harness first (behavior-neutral); then candidate-record scaffold (behavior-neutral, ranking unchanged); then real probability-weighted `expected_fan` with visible-depletion penalty; then post-call-best-candidate gating; then kong replacement-draw expectation and personality-field plumbing.
- Defer threat-triggered defense, opponent target inference, MCTS / search, ML, and additional hand-pattern targets like Qi Dui to later slices.

Reason:
- The candidate-pipeline shape is the consensus across mature mahjong AI projects, irrespective of ruleset (HK / Japanese / Chinese Standard / Mahjong Soul). Bolting more patches onto the current heuristic loses access to that shape's compounding leverage; rebuilding around it lets every future improvement (defense, opponent packages, search, ML) land as a localized change to one box of the pipeline.
- Adding rare hand patterns (Qi Dui) treats symptoms; restructuring the priority list mechanism is the root fix. The user's post-audit pushback explicitly argued this point.
- Rebuilding *now* — before S08 (Playable Round 1 UI) — gives the UI's inspector a stable AI surface to render top-3 candidates against, instead of layering inspector code over a heuristic whose internal shape will change.
- A checked-in harness with the S06 baseline (Hu 6/10) makes the rebuild reversible at every step. Intermediate commits may dip below baseline; nothing merges to main until the slice tip matches or exceeds it.

Implications:
- The S07 slice plan reuses everything S06 built that's engine-facing. The throw-away is concentrated in `ai_strategy.tl`'s heuristic kernel (~400 lines of Teal); the infrastructure under it (~2000+ lines) carries forward.
- About half the existing `spec_tl/ai_strategy_spec.tl` and `spec_tl/ai_spec.tl` cases will be rewritten — they pin assertions against the old API (e.g., "given hand X with target T, discard Y"). The new cases assert against the candidate API ("given hand X, candidate Y outranks Z because"). Same coverage, less locked into one mechanism.
- `AiPersonality` gains `speed_bias`, `value_bias`, `call_appetite`, `kong_appetite`, `target_stickiness`, `safety_bias` fields plumbed through `rank_by_utility` in S07. M1 ships only `NEUTRAL_PERSONALITY`; opponent packages in later milestones become weight tweaks rather than new code paths.
- The `danger` field is reserved on `CandidateAction` from S07 onward but populated as 0. Defense lands later; the field stays plumbed so downstream code is stable.
- Future ML / search work uses the `CandidateAction` schema as its observation/action surface. We don't design it specifically for ML; we design it for the inspector and harness, and ML reuses it.
