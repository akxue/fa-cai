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
