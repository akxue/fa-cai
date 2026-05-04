# AGENTS.md

This file is the shared project brief for AI coding agents working on facai. Keep it short, operational, and biased toward rules an agent can follow while editing code.

Read this file first, then read:

- `docs/INITIAL-DESIGN.md` for the game vision and broader Phase 0 target.
- `docs/MILESTONE-1-PLAN.md` for the current build scope and architecture decisions.
- `docs/DECISIONS.md` for durable architecture, rules, and workflow decisions.
- `docs/AGENT-ROLES.md` when splitting work across specialized agents.
- `docs/DEVELOPMENT-WORKFLOW.md` for branch, PR, review, and CI expectations.

## Mahjong Variant

facai implements **Hong Kong mahjong** (廣東麻雀). This is not Japanese mahjong. Do not implement or reference:

- Riichi / Reach declarations
- Furiten
- Japanese hand patterns (tanyao, ippeiko, and any yaku not listed in `docs/INITIAL-DESIGN.md`)
- Han/fu point calculation
- Japanese tile names (man/pin/sou)
- Dora indicators
- Any rule or concept specific to Japanese competitive mahjong

The valid reference for rules is the hand pattern list and scoring system in `docs/INITIAL-DESIGN.md`. If you are uncertain whether a concept applies to HK mahjong, check that list. If it is not there, do not implement it.

The term for a hand one tile from a valid Hu is **ting** (聽牌). Do not use "tenpai" in code or docs. The measure of how many tiles a hand needs to reach ting is **ting distance**. Do not use "shanten" in code or docs.

## Project Snapshot

facai is a solo roguelike mahjong game built with LÖVE + Teal. The player races three AI opponents to a valid Hong Kong mahjong Hu, using boons to bend scoring, information, and timing.

Milestone 1 is a one-round vertical slice, not the full five-round tournament:

- Choose 1 starter boon from 3 curated offers.
- Play Round 1 against 3 vanilla AI opponents.
- Win the deal to see a reward screen.
- Lose a deal to lose 1 life and retry Round 1.
- Stop at a readable dev/playtestable slice before Round 2+ and full opponent packages.

## Source Of Truth

- Product/game design: `docs/INITIAL-DESIGN.md`
- Milestone 1 engineering plan: `docs/MILESTONE-1-PLAN.md`
- Durable decisions: `docs/DECISIONS.md`
- Agent responsibility model: `docs/AGENT-ROLES.md`
- Development workflow: `docs/DEVELOPMENT-WORKFLOW.md`

If these docs disagree, do not guess silently. Prefer the more specific milestone plan for implementation details, then flag the inconsistency in your final response.

## Tooling Direction

The intended stack is:

- Runtime: LÖVE
- Language: Teal, compiled to Lua
- Tests: busted
- Build orchestration: `Makefile` + `tlconfig.lua`

Expected commands once the toolchain exists:

```sh
make check
make build
make test
make run
make clean
```

Until those commands exist, do not invent successful verification. Say what could not be run.

## Planning Gate

Do not begin implementation from a broad request. Before code changes, identify:

- the Milestone 1 slice and task from `docs/MILESTONE-1-PLAN.md`
- the acceptance criteria
- likely owned files/modules
- verification commands
- whether `docs/DECISIONS.md` needs a new or updated entry

Begin implementation only when the user accepts the plan, the task is already clearly defined in an accepted slice, or the user explicitly asks to skip planning and start building.

If the user is asking for planning, review, design discussion, or questions, do not start gameplay implementation.

## Repository Layout Target

Planned source layout:

```text
src_tl/
  app/       # LÖVE integration, scene stack, input, settings, save adapter
  core/      # dependency-free types, ids, RNG, tiny utilities
  game/      # deterministic rules engine and run/deal state
  content/   # typed static content definitions
  effects/   # typed effect system and boon modules
  ui/        # LÖVE drawing/input widgets and layout helpers
  scenes/    # LÖVE-facing screens composed from app/ui/game
src/          # generated Lua, ignored
spec_tl/      # authored Teal specs/helpers
spec/         # generated Lua specs, ignored
docs/         # design, plans, and agent guidance
```

Generated Lua in `src/` and generated specs in `spec/` must not be committed.

## Dependency Boundaries

Keep the rules engine portable and deterministic. LÖVE is the runtime shell, not the foundation of every module.

Allowed dependencies by area:

- `src_tl/core/`: must not import `love`, `game`, `content`, `effects`, `ui`, `scenes`, or `app`.
- `src_tl/game/`: must not import `love`, `ui`, `scenes`, or `app`; may import `core`, `content`, and stable effect interfaces.
- `src_tl/content/`: may import `core` types only; must not import `game`, `effects`, `ui`, `scenes`, `app`, or `love`.
- `src_tl/effects/`: may import `core`, stable game types, and `content`; must not import `love`, `ui`, `scenes`, or `app`.
- `src_tl/ai/` if split out later, or `src_tl/game/ai.tl` in Milestone 1: may inspect game state and emit `DealAction`s; must not mutate state directly or import `love`.
- `src_tl/ui/`: may import `love`, `core` view types, and read-only presentation helpers; must not own game rules.
- `src_tl/scenes/`: may import `love`, `app`, `ui`, and game/effects public APIs; scenes orchestrate user flow but must not implement rules.
- `src_tl/app/`: may import `love`; owns runtime adapters such as input, settings, save files, and scene stack.
- `src_tl/main.tl`: may define LÖVE callbacks and wire the app together.
- `spec_tl/`: may import any module needed for tests, but rules tests should avoid `love`.

Forbidden dependency directions:

- Core/game/effects/content must never depend on UI, scenes, or app.
- Core/game/effects/content must never call `love.graphics`, `love.window`, `love.keyboard`, `love.mouse`, `love.filesystem`, or `love.math`.
- Randomness in core/game/effects/content must go through `core/rng.tl`, not `math.random` or `love.math`.
- Save/load must be isolated behind `app/save.tl`; rules modules should receive plain data records.

## Coding Standards

- Use `snake_case` for files, modules, functions, variables, fields, enum/string values.
- Use `PascalCase` for record/type names.
- Use `UPPER_SNAKE_CASE` for constants.
- Prefer typed records and explicit result records over loose table blobs.
- Prefer module tables with explicit exported functions over ambient globals.
- Keep module-level state out of `core`, `game`, `content`, and `effects`; pass state explicitly.
- Prefer pure functions for rules, scoring, validation, wall operations, and effect queries.
- Use arrays for ordered collections and maps only when lookup by ID is the main operation.
- Return sorted copies from helpers that sort caller-owned collections.
- Use explicit `ok/error` result records for recoverable illegal actions or parse failures.
- Reserve `error()`/assertions for programmer mistakes and impossible invariants.
- Keep Teal type definitions close to the module that owns the concept; promote to `core/types.tl` only when shared widely.
- Avoid broad utility modules until repeated use proves the need.
- Do not mutate state from AI or effect modules directly. Go through typed actions, queries, commands, and engine transitions.
- Preserve tile conservation: every physical tile must be accounted for exactly once.
- Use `Deal` for one mahjong attempt in engineering docs/code. Avoid using `hand` to mean a deal.
- Use `TileSet` for Chi/Peng/Kong groups in code. Player-facing text may still use familiar mahjong terms where helpful.

## LÖVE Integration Conventions

- Define LÖVE callbacks in `src_tl/main.tl` and delegate immediately into `app`.
- Use `love.load` for one-time initialization, `love.update(dt)` for frame updates, and `love.draw` for rendering.
- Do not load fonts/images or create heavyweight resources inside `love.draw`.
- Keep frame-time `dt` out of rules logic; animation/UI may use `dt`, deterministic deal transitions should not.
- Input callbacks should create high-level UI/game intents rather than mutating game state directly.
- UI code should render from state snapshots and dispatch actions through the scene/app layer.
- `love.filesystem` belongs behind save/settings adapters, not inside run/deal/rules modules.

## Game Architecture Rules

- Core rules come first; effects extend through typed query/command points.
- Effects must not bypass Hu shape validation or the 3 fan minimum in Milestone 1.
- Boon behavior should produce structured scoring reasons or events, not hidden side effects.
- AI must use the same `DealAction` path and validator/scorer as the player.
- Debug UI should expose enough state to diagnose rules bugs: seeds, wall count, pending reactions, score candidates, AI reasoning, and tile conservation.

## Testing Expectations

When code exists:

- Add tests alongside rules-heavy changes.
- Prefer pure functions for validation, scoring, calls, wall operations, RNG, and effect queries.
- Use compact test hand notation from `docs/MILESTONE-1-PLAN.md`.
- Run `make test` before finalizing source changes when available.
- If a check fails, report the failing command and the relevant error.

## Agent Workflow

Before editing:

- Read the relevant plan/design section, not just this file.
- Identify the owning module or doc before adding a new file.
- Check current `git status` and do not overwrite unrelated user changes.
- If working from GitHub, use a focused branch and expect to open a PR.

While editing:

- Keep file ownership narrow.
- Add or update tests for rules-heavy behavior.
- Update docs only when behavior, scope, or commands actually change.

Before finishing:

- Run the narrowest relevant check, then `make test` when available.
- Report commands run and anything that could not be verified.
- List changed files when the task involved edits.

## PR Workflow

- Prefer small PRs with one behavioral or documentation concern.
- Use branch names like `agent/rules-wall-state`, `agent/tooling-teal-busted`, or `docs/milestone-1-clarity`.
- Fill out `.github/pull_request_template.md`.
- Do not merge code changes without human review.
- Once CI exists, do not merge unless CI passes or the user explicitly accepts the failing state.
- Do not add a GitHub Actions workflow until the commands it runs exist locally.

## Documentation Rules

- Keep `README.md` human-facing and concise.
- Keep `AGENTS.md` agent-facing and concise.
- Put broad game design in `docs/INITIAL-DESIGN.md`.
- Put current build scope and architecture decisions in `docs/MILESTONE-1-PLAN.md`.
- Do not duplicate rule decisions across docs unless the second location clearly points to the canonical source.

## Change Discipline

- Keep changes scoped to the requested task.
- Do not rewrite design decisions without calling out the change.
- Do not commit generated files.
- Do not add new dependencies without explaining why they are needed.
- Do not bypass the PR/review workflow for implementation changes unless the user explicitly asks.
- Do not start building gameplay when the user is asking for planning, review, or design discussion.
- If the worktree has unrelated changes, leave them alone.
