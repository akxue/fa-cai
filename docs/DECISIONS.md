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
