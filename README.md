# facai

facai (發財) is a solo roguelike mahjong game concept. The player races three AI opponents to complete a valid Hong Kong mahjong hand, then builds momentum across a short tournament by collecting rule-bending boons.

The current repository is in the design/planning stage. It contains the initial game design document and Milestone 1 build plan. It does not yet include a playable prototype or build system.

## Concept

Each run is a five-round tournament:

- Start with 3 lives
- Choose 1 starter boon before Round 1
- Play one mahjong hand against 3 AI opponents
- Win the hand to advance
- Lose the hand, exhaust the Wall, or let an opponent Hu first to lose 1 life and retry the same round
- Choose another boon after clearing Rounds 1-4
- Clear Round 5 before running out of lives

The core idea is to preserve recognizable mahjong decisions while letting each run become strange through accumulated boons.

## Phase 0 Scope

Phase 0 is intended to validate the core loop:

- Solo play
- Standard 136-tile Wall
- Hong Kong mahjong actions: Chi, Peng, Gang, Hu, and Zi Mo
- Fixed 3 fan minimum for every player
- Five tournament rounds
- Three lives
- Small curated boon pool
- Three AI opponents with escalating visible packages
- Hand results shown as ratings instead of point totals

Deferred features include art, classes, overworld routing, relics, boss auras, co-op, and opponent-affecting boons.

## Repository Structure

```text
.
├── AGENTS.md
├── CLAUDE.md
├── .github/
│   └── pull_request_template.md
├── docs/
│   ├── AGENT-ROLES.md
│   ├── DECISIONS.md
│   ├── DEVELOPMENT-WORKFLOW.md
│   ├── INITIAL-DESIGN.md
│   └── MILESTONE-1-PLAN.md
└── README.md
```

## Documentation

Start with [docs/INITIAL-DESIGN.md](docs/INITIAL-DESIGN.md). It covers:

- Game pitch and design goals
- Phase 0 prototype scope
- Tournament structure
- Core mahjong terms
- Fan-to-rating conversion
- Boon system
- Opponent packages
- Deferred features
- Open questions

Then read [docs/MILESTONE-1-PLAN.md](docs/MILESTONE-1-PLAN.md). It covers the first playable build slice:

- Engine and tooling
- Repository shape
- Domain model
- Rules/scoring implementation decisions
- Effect system
- Milestone 1 slices, tasks, and acceptance scope

Durable architecture, rules, and workflow decisions are tracked in [docs/DECISIONS.md](docs/DECISIONS.md).

Agent-facing guidance lives in [AGENTS.md](AGENTS.md). Codex reads that file directly; [CLAUDE.md](CLAUDE.md) imports it so Claude Code uses the same shared instructions. Dedicated agent responsibility lanes are described in [docs/AGENT-ROLES.md](docs/AGENT-ROLES.md).

Development should happen through small PRs with human review. See [docs/DEVELOPMENT-WORKFLOW.md](docs/DEVELOPMENT-WORKFLOW.md) for branch, PR, review, and future CI expectations.

## Status

This project is not yet implemented. There are currently no dependencies to install, tests to run, or executable commands.

## Working Notes

The broader Phase 0 prototype should answer one question:

> Is racing three opponents to Hu, under the minimum fan rule, with an accumulating boon stack, fun enough to keep playing?

Milestone 1 is the first slice toward that answer: Round 1 only, one starter boon, vanilla opponents, and a reward screen after the player wins.
