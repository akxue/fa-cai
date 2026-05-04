# Agent Roles

This document describes useful responsibility lanes for AI agents working on facai.

These are not permanent team titles. They are coordination patterns: use them when work benefits from parallel review or clear ownership. A single agent can fill multiple roles on small tasks.

## Coordination Rules

- Start from `AGENTS.md`, `docs/INITIAL-DESIGN.md`, and `docs/MILESTONE-1-PLAN.md`.
- Tie implementation work to a Milestone 1 slice/task before editing.
- Check `docs/DECISIONS.md` before changing architecture, rules, workflow, or durable conventions.
- Assign one owner per file or module when making code changes.
- Avoid parallel edits to the same file unless one agent is explicitly integrating.
- Explorers answer bounded questions and should not make speculative architecture changes.
- Workers own concrete file sets and should list changed files in their final response.
- Reviewers look for bugs, inconsistencies, missing tests, and scope drift.
- When roles disagree, prefer the current milestone plan for implementation details and surface the disagreement to the user.

## Recommended Roles

### Rules Engine Agent

Owns deterministic mahjong rules.

Primary areas:

- hand validation
- scoring and ratings
- call legality
- reaction priority
- Kong flows
- tile conservation invariants

Default stance:

- Keep logic pure where possible.
- Return structured results and errors.
- Add focused tests for every scoring/rules edge case.

### Effects And Boons Agent

Owns boon behavior and the typed effect system.

Primary areas:

- effect query/command types
- effect registry/runner
- boon modules
- boon counters and score reasons
- Known Wall information effects

Default stance:

- Do not mutate core state directly.
- Do not add arbitrary hooks for one boon.
- If a boon needs a new hook, name the general lifecycle moment and add tests for ordering.

### AI Agent

Owns vanilla opponent behavior and later opponent packages.

Primary areas:

- draw/discard decisions
- Hu/call decisions
- discard heuristic explanations
- debug inspector reasoning

Default stance:

- AI must use the same `DealAction` path as the player.
- No defensive AI in Milestone 1.
- Prefer simple, readable heuristics over clever hidden logic.

### UI And UX Agent

Owns LÖVE scenes, input, debug UI, and table readability.

Primary areas:

- scene stack
- table scene
- tile rendering
- action prompts
- debug inspector
- reward screen

Default stance:

- Build the playable table, not a marketing page.
- Keep the Milestone 1 UI simple but inspectable.
- Never hide rules state needed for playtesting.

### Tooling And Build Agent

Owns project setup and developer workflow.

Primary areas:

- `Makefile`
- `tlconfig.lua`
- Teal declarations
- busted setup
- generated-file ignores
- README setup commands

Default stance:

- Make `make check`, `make build`, and `make test` boring and reliable.
- Do not commit generated Lua.
- Document any toolchain limitation clearly.

### Documentation Agent

Owns consistency between design and implementation docs.

Primary areas:

- `README.md`
- `AGENTS.md`
- `docs/INITIAL-DESIGN.md`
- `docs/MILESTONE-1-PLAN.md`
- future PRD/architecture docs

Default stance:

- Avoid duplicating canonical decisions.
- Make scope labels explicit: End Vision, Phase 0, Milestone 1.
- Flag contradictions rather than smoothing them over silently.

### Integration Reviewer

Owns the final pass before a task is considered done.

Primary areas:

- cross-module consistency
- test coverage
- source/generated file hygiene
- docs matching behavior
- git status review

Default stance:

- Findings first, ordered by severity.
- Verify commands when available.
- Call out residual risk and anything not run.

## Suggested Parallel Work Splits

Milestone 1 foundation slices can split cleanly into:

- Tooling And Build Agent: Makefile, Teal, busted, ignores.
- Rules Engine Agent: tile IDs, physical tile set, RNG, wall operations.
- Documentation Agent: README setup and doc consistency.

Milestone 1 rules slices can split cleanly into:

- Rules Engine Agent: validator, scorer, calls, invariants.
- Effects And Boons Agent: effect type skeleton and score modifier path.
- Integration Reviewer: edge-case tests and rules consistency.

Milestone 1 engine/debug slices can split cleanly into:

- Rules Engine Agent: deal state transitions and reaction windows.
- AI Agent: vanilla AI actions and reasoning output.
- UI And UX Agent: debug table and inspector.

Milestone 1 playable UI/integration slices can split cleanly into:

- UI And UX Agent: playable table, prompts, reward screen.
- Effects And Boons Agent: starter boons and active effects.
- Integration Reviewer: playtest flow and regression checks.
