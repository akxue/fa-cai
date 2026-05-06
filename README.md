# facai

facai (發財) is a solo roguelike mahjong game. The player races three AI opponents to complete a valid Hong Kong mahjong hand, then builds momentum across a short tournament by collecting rule-bending boons.

## Requirements

- **LÖVE 11.5** — download from [love2d.org](https://love2d.org/)
- **Lua 5.4** — `brew install lua@5.4`
- **LuaRocks** — `brew install luarocks`
- **Teal** (Teal compiler) — `luarocks --lua-dir $(brew --prefix lua@5.4) --tree $(brew --prefix lua@5.4) install tl`
- **busted** (test runner) — `luarocks --lua-dir $(brew --prefix lua@5.4) --tree $(brew --prefix lua@5.4) install busted`

After installing, add Lua 5.4 binaries to your PATH:

```sh
export PATH="/opt/homebrew/opt/lua@5.4/bin:$PATH"
```

Add that line to your shell config (`~/.zshrc` or `~/.bashrc`) to make it permanent.

## Commands

```sh
make check     # Teal typecheck
make build     # Compile Teal → Lua
make test      # Build and run busted specs
make run       # Build and launch LÖVE — title screen → boon select → Round 1
make playtest  # Headless AI-vs-AI harness (10 deterministic seeds)
make clean     # Remove generated Lua
```

## Repository Structure

```text
src_tl/      # authored Teal source
  app/       # LÖVE integration, scene stack, input, settings, save
  core/      # dependency-free types, ids, RNG, tiny utilities
  game/      # deterministic rules engine and deal/run state
  content/   # typed static content definitions
  effects/   # typed effect system and boon modules
  ui/        # LÖVE drawing/input widgets and layout helpers
  scenes/    # LÖVE-facing screens composed from app/ui/game
  main.tl    # LÖVE entry point
spec_tl/     # authored Teal specs
  support/   # busted declarations and test helpers
src/         # generated Lua — not committed
spec/        # generated Lua specs — not committed
types/       # Teal type declarations for external libraries
docs/        # design, plans, and agent guidance
```

## Documentation

- [docs/INITIAL-DESIGN.md](docs/INITIAL-DESIGN.md) — game design and Phase 0 scope
- [docs/MILESTONE-1-PLAN.md](docs/MILESTONE-1-PLAN.md) — Milestone 1 slice breakdown and architecture
- [docs/DECISIONS.md](docs/DECISIONS.md) — durable architecture and rules decisions
- [AGENTS.md](AGENTS.md) — agent-facing coding guidance

## Status

Milestone 1 in progress. Slices S00–S08 are complete (toolchain, core types, rules engine, effects, AI, playable Round 1 UI). S09 (integration + playtest pass) is the active slice.
