# Development Workflow

facai should be developed through small pull requests with human review.

The goals are:

- keep a human-in-the-loop review point for game feel, architecture, and rules correctness
- make agent changes easy to inspect
- let GitHub Actions enforce typechecks and tests once the toolchain exists
- avoid large unreviewable batches of generated or unrelated changes

## Delivery Loop

Use this lightweight loop for implementation work:

```text
Clarify request
-> identify slice/task
-> confirm acceptance criteria and verification
-> human accepts plan
-> create focused branch
-> implement
-> run checks/tests
-> self-review
-> open PR
-> human review
-> merge
-> record durable decisions/learnings when needed
```

For Milestone 1, the canonical slice/task breakdown lives in `docs/MILESTONE-1-PLAN.md`.

Do not turn broad planning or design questions into implementation work unless the user explicitly asks to build.

## Branches

Use short task branches:

```text
agent/<area>-<short-task>
human/<area>-<short-task>
docs/<short-task>
```

Examples:

```text
agent/tooling-teal-busted
agent/rules-wall-state
docs/milestone-1-clarity
```

Prefer one concern per branch. If a task grows into multiple areas, split it before opening a PR.

Each implementation branch should map to one Milestone 1 slice and one or more tasks.

## Pull Requests

Every implementation PR should include:

- the Milestone 1 slice/task reference
- a focused summary of the change
- the files or modules changed
- tests/checks run
- anything intentionally not tested
- screenshots or short clips for UI changes once UI exists
- open questions for human review
- whether `docs/DECISIONS.md` was updated or why it was not needed

Keep PRs small enough that a reviewer can understand the full behavioral change in one sitting.

## Review Expectations

Human review should focus on:

- design intent and game feel
- mahjong rule correctness
- architecture boundaries from `AGENTS.md`
- readability and future agent maintainability
- test coverage for rules-heavy changes

Agent review should focus on:

- bugs and regressions
- illegal imports or boundary drift
- missing tests
- generated files committed by mistake
- docs that no longer match behavior

facai-specific review checks:

- tile conservation still holds
- deterministic seed/replay behavior is preserved
- `core`, `game`, `content`, and `effects` do not import LÖVE
- Hong Kong mahjong terminology is used; Japanese-only rules or terms do not slip in
- rules-heavy behavior has focused tests
- generated Lua/spec files are not committed
- durable decisions are recorded in `docs/DECISIONS.md`

## Continuous Integration

Do not add a GitHub Actions workflow that fails before the toolchain exists.

Once `Makefile`, `tlconfig.lua`, and busted are set up, add `.github/workflows/ci.yml` with at least:

```sh
make check
make test
```

Later CI can add:

- generated-file cleanliness checks
- import-boundary checks
- lint/format checks if the project adopts a formatter
- packaged LÖVE build checks

## Merge Rules

Before merging:

- CI should pass once CI exists.
- At least one human should review code changes.
- Rules/engine changes should include tests or explain why tests are not possible yet.
- Generated Lua in `src/` and generated specs in `spec/` must not be committed.

## Agent PR Discipline

Agents should:

- work in narrowly scoped changes
- cite the slice/task they are implementing
- avoid rewriting unrelated docs/code
- leave unrelated worktree changes untouched
- call out any source-of-truth conflict between docs
- never claim tests passed unless they actually ran
