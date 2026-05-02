# facai

facai (發財) is a solo roguelike mahjong game concept. The player races three AI opponents to complete a valid Hong Kong mahjong hand, then builds momentum across a short tournament by collecting rule-bending boons.

The current repository is in the design stage. It contains the initial game design document and does not yet include a playable prototype or build system.

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
├── docs/
│   └── INITIAL-DESIGN.md
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

## Status

This project is not yet implemented. There are currently no dependencies to install, tests to run, or executable commands.

## Working Notes

The first engineering milestone should be a minimal playable prototype that answers one question:

> Is racing three opponents to Hu, under the minimum fan rule, with an accumulating boon stack, fun enough to keep playing?
