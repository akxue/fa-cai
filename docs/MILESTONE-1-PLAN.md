# facai Milestone 1 Plan

> Status: working engineering contract for Milestone 1. This document translates the broader design into the first playable build slice, including architecture, tooling, rules decisions, milestone breakdown, and acceptance scope. It should become the source material for a Milestone 1 PRD, architecture doc, and implementation tickets.

---

## Product Goal

facai should become a Steam-quality, flexible, bespoke roguelike mahjong game. Milestone 1 is not a disposable toy prototype; it is the first build slice of the real game, scoped small enough to reach a playable vertical slice quickly.

The architecture should support the long-term vision: more boons, relics, classes, boss auras, opponent identities, ratings, unlocks, and rule-bending effects. Milestone 1 exists to sequence work, not to make short-term architecture choices that block the end vision.

Milestone 1 is the first implementation slice of the broader Phase 0 prototype described in `docs/INITIAL-DESIGN.md`. Phase 0 still describes the larger five-round prototype target; this plan describes the one-round build needed first.

---

## Engine and Tooling

### Engine

Use **LÖVE** as the game runtime.

Rationale:

- facai wants a distinct, tactile, custom tile-table feel.
- The game is 2D, rules-heavy, and UI-heavy rather than physics-heavy.
- LÖVE supports a code-first workflow well suited to a developer-led project.
- The team is comfortable owning a small internal UI/game framework.

### Language

Author game code in **Teal**, compiled to Lua for LÖVE.

Rationale:

- AI agents will write much of the code.
- Types and tests should guide agents and prevent table-shape drift.
- Raw Lua is too permissive for a long-lived agent-coded rules project.

### Testing

Use **busted** as the test framework.

Prefer authoring specs in Teal where practical, then compile them to Lua before running busted. If busted declarations become too cumbersome, keep fixtures/helpers in Teal and allow thin Lua spec wrappers.

### Commands

Use a `Makefile` and `tlconfig.lua`.

Expected commands:

```sh
make check   # Teal typecheck
make build   # Generate Lua from Teal
make test    # Typecheck, build, run busted specs
make run     # Build and launch LÖVE
make clean   # Remove generated Lua
```

Generated Lua should not be committed during development.

---

## Repository Shape

```text
src_tl/
  app/
    scene_stack.tl
    input.tl
    settings.tl
    save.tl
  core/
    types.tl
    rng.tl
    ids.tl
  game/
    tiles.tl
    wall.tl
    hand_validator.tl
    scorer.tl
    calls.tl
    deal_engine.tl
    deal_invariants.tl
    ai.tl
    run_state.tl
  content/
    boons.tl
    hand_patterns.tl
    opponent_packages.tl
  effects/
    effect_types.tl
    effect_registry.tl
    effect_runner.tl
    boons/
      current.tl
      still_water.tl
      dragon_weight.tl
      open_eyes.tl
      third_eye.tl
      fresh_start.tl
      momentum.tl
  ui/
    layout.tl
    theme.tl
    tile_view.tl
    button.tl
    card.tl
    panel.tl
    tooltip.tl
    log_view.tl
  scenes/
    start_scene.tl
    boon_select_scene.tl
    table_scene.tl
    reward_scene.tl
    result_scene.tl
  main.tl

spec_tl/
  support/
    busted.d.tl
    hand_notation.tl
    assertions.tl
  wall_spec.tl
  hand_validator_spec.tl
  scorer_spec.tl
  calls_spec.tl
  effects_spec.tl

src/   # generated Lua, ignored
spec/  # generated Lua specs, ignored
```

---

## Naming Conventions

- Files/modules: `snake_case`
- Functions: `snake_case`
- Variables/fields: `snake_case`
- Enum/string values: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Record/type names: `PascalCase`

Examples:

```lua
record TileKind
  kind_id: TileKindId
  is_honor: boolean
end

function make_full_tile_set(): {Tile}
```

---

## Core Vocabulary

Use these terms consistently in code and docs:

- **Run:** whole tournament attempt
- **Round:** tournament gate, 1-5
- **Deal:** one mahjong deal/attempt inside a round
- **PlayerHand:** one player's concealed tiles and declared sets
- **TileSet:** Chi/Peng/Kong group
- **Known Wall:** wall tiles that are still physically in the Wall but are known to the player through an information effect
- **Concealed / Men Qian:** no open TileSets; a winning discard can still be the incoming tile for a concealed win

Avoid using `hand` to mean a deal.

---

## Static Data and Saves

No database is needed for Phase 0.

Static game content should live in typed Teal modules:

- boons
- hand pattern metadata
- opponent packages
- tuning constants

Future player save data should use files through `love.filesystem`, for example:

```text
settings.json
profile.json
current_run.json
```

Postgres is not appropriate unless facai later becomes an online service. SQLite is not needed in Phase 0.

---

## Domain Model

### Tile Names

Use explicit tile kind IDs in code:

```text
tiao_1 ... tiao_9
wan_1 ... wan_9
bing_1 ... bing_9
east
south
west
north
fa_cai
hong_zhong
bai_ban
```

Use physical tile objects in runtime state:

```lua
record Tile
  tile_id: TileId      -- e.g. "tiao_1_a"
  kind_id: TileKindId  -- e.g. "tiao_1"
end
```

Physical copy suffixes should be readable:

```text
tiao_1_a
tiao_1_b
tiao_1_c
tiao_1_d
```

Rules/scoring should usually operate on `kind_id` counts. Movement and conservation should operate on physical `tile_id`s.

### Player Hand and Tile Sets

```lua
type TileSetKind = "chi" | "peng" | "kong"
type SetVisibility = "open" | "concealed"

record TileSet
  kind: TileSetKind
  visibility: SetVisibility
  tiles: {Tile}
  called_from: integer -- -1 for concealed/self
end

record PlayerHand
  concealed_tiles: {Tile}
  sets: {TileSet}
end
```

A concealed Kong should become a concealed `TileSet`, not remain loose in the hand.

### Run and Deal

Dealer rotation should be modeled in state but fixed/deferred behaviorally in Milestone 1.

Milestone 1 defaults:

- dealer = player
- round wind = east

```lua
record RunState
  round_index: integer
  lives: integer
  active_effects: {ActiveEffectState}
  previous_win_rating: Rating?
  rng: RngState
end

record DealState
  players: {PlayerState}
  wall: WallState
  phase: DealPhase
  current_player: integer
  dealer: integer
  round_wind: Wind
  pending_discard: PendingDiscard?
  pending_added_kong: PendingAddedKong?
  known_wall_tile_ids: {TileId}
  effect_states: {ActiveEffectState}
  rng: RngState
end
```

Run loop defaults:

- Start a tournament run with 3 lives.
- To advance a round, the player must win a deal.
- Losing a deal costs 1 life and retries the same round.
- At 0 lives, the run ends.
- Milestone 1 only implements Round 1; after a Round 1 win, showing the reward screen is enough.

---

## Wall Model

The Wall is an ordered list of currently undrawn physical tiles.

```lua
record WallState
  tiles: {Tile}
end
```

Rules:

- Normal draw removes from the front: `tiles[1]`.
- Kong supplement draw removes from the back: `tiles[#tiles]`.
- Reveals inspect from the front without mutation.
- Fresh Start returns selected physical tiles to the remaining Wall, then reshuffles the remaining Wall.
- Wall remaining count is `#wall.tiles`.
- Replay/debug uses seed + action log, not original-wall indices.

The full physical tile invariant is:

```text
Wall
+ all player concealed tiles
+ all player TileSets
+ all player discards
+ pending discard, if any
= 136 unique physical tiles
```

In Milestone 1, `pending_added_kong` should reference the fourth tile by `tile_id`; the physical tile remains in the declarer's concealed tiles until the Qiang Gang window resolves.

Build `deal_invariants.validate_tile_conservation(deal)` early.

---

## Known Wall

Known Wall tiles are still physically in the Wall. They are simply known to the player because of an information effect.

```lua
record DealState
  known_wall_tile_ids: {TileId}
end
```

Rules:

- Third Eye sets Known Wall to the next 5 normal front-Wall tiles.
- Open Eyes sets Known Wall to the next 3 normal front-Wall tiles.
- Drawing a known tile removes it from `known_wall_tile_ids`.
- Fresh Start reshuffles the Wall, so it clears `known_wall_tile_ids`.
- Known Wall tracks normal front-Wall tiles only in Milestone 1.
- Known information persists in the UI; the player should not need to memorize peeked tiles.

---

## RNG and Determinism

Core game logic must not use `math.random` or import `love.math`.

Implement deterministic RNG in `core/rng.tl`.

Expected API:

```lua
record RngState
  state: integer
end

function from_seed(seed: integer): RngState
function next_u32(rng: RngState): RngIntResult
function next_int(rng: RngState, min_value: integer, max_value: integer): RngIntResult
function shuffle_tiles(rng: RngState, tiles: {Tile}): RngShuffleTilesResult
```

Use a small deterministic PRNG such as xorshift32. Guard against zero seed.

RNG state should be explicit:

- `RunState.rng` for run-level randomness, including boon offers and deal seed generation.
- `DealState.rng` for wall shuffle, AI tie-breaks, and Fresh Start reshuffle.

Debug UI should show run seed and deal seed.

---

## Deal State Machine

Use these phases:

```lua
type DealPhase =
  "opening_actions"
  | "awaiting_draw"
  | "awaiting_action"
  | "reaction_window"
  | "deal_over"
```

Opening flow:

1. Deal 13 tiles to each player.
2. Apply opening modifiers, such as Momentum, to the owning player.
3. Fresh Start may swap 0-3 tiles.
4. Player trims to 13 if needed.
5. Normal play begins.

Turn flow:

- During `awaiting_draw`, current player draws normally.
- During `awaiting_action`, current player may Hu, declare concealed/added Kong, or discard.
- After any Kong, draw a supplement tile from the back of the Wall, then return to `awaiting_action`.
- Multiple Kongs in one turn are allowed.
- Wall exhaustion during normal or supplement draw ends the deal as a loss if no one Hu.

Reaction windows:

- A discard creates a reaction window.
- An added Kong creates a reaction window for Qiang Gang.
- Concealed Kong does not create a reaction window.
- Open Kong from discard does not create another reaction window beyond the original discard claim.

---

## Pending Zones

Use explicit pending zones for clean tile conservation.

### Pending Discard

When a tile is discarded:

1. Remove it from the discarder concealed tiles.
2. Store it as `pending_discard`.
3. Open reaction window.
4. If unclaimed, move it to the discarder discard pile.
5. If claimed for Chi/Peng/Kong, move it into caller's `TileSet`.
6. If used for Hu, score with it as the incoming tile and end the deal.

### Pending Added Kong

For Qiang Gang:

1. Player declares added Kong from an existing open Peng.
2. The fourth tile remains in their concealed tiles while the reaction window opens.
3. Other players may Hu by Qiang Gang.
4. If no one claims Hu, move the tile into the existing Peng, converting it to Kong.
5. Draw supplement from back.

---

## Calls and Kong

Rules:

- Only the next player in turn order may Chi a discard.
- Chi cannot be called on honor tiles.
- Any other player may Peng if they have two matching concealed tiles.
- Any other player may open Kong if they have three matching concealed tiles.
- Concealed Kong can be declared only on your own turn after drawing, before discarding.
- Added Kong can be declared only on your own turn if you have an open Peng and the fourth matching tile in concealed tiles.
- Concealed Kong preserves Concealed / Men Qian.
- Chi, Peng, and open Kong break Concealed / Men Qian.
- Added Kong is open because the original Peng was open.
- Any Kong immediately draws a supplement tile from the back of the Wall.
- Gang Shang applies if the player wins on the supplement tile.
- Qiang Gang only applies to added Kong.
- Concealed Kong and open Kong from discard cannot be robbed in Phase 0.

Reaction priority:

1. Human Hu prompt appears if legal.
2. If human accepts, human wins.
3. If human passes or cannot Hu, AI Hu resolves; nearest next AI wins.
4. If no Hu, Kong/Peng beat Chi.
5. Only next player can Chi.
6. Nearest next player wins non-Hu AI conflicts.
7. No multi-winner handling in Milestone 1.

---

## Hand Validation and Scoring

### Validation

The validator returns all valid win shapes, not just one.

Supported `WinShapeKind`s:

```lua
"standard_four_sets_pair"
"seven_pairs"
"thirteen_orphans"
"nine_gates"
```

Standard shape:

- `4 TileSets + 1 pair`
- Existing open/concealed sets count toward the 4 sets.
- Remaining concealed tiles plus incoming tile must decompose into the missing sets plus pair.

Special shapes:

- Seven Pairs: no open sets; 14-tile winning material forms seven pairs.
- Thirteen Orphans: no open sets; 14-tile winning material contains all terminals/honors plus one duplicate.
- Nine Gates: no open sets; 14-tile winning material is one suit in the completed `1112345678999 + any same-suit duplicate` shape.
- Do not distinguish true Nine Gates in Phase 0.

### Scoring

Scoring pipeline:

1. Validator finds all `WinShape`s.
2. Base scorer evaluates each shape.
3. Base scorer emits structured `ScoreFacts`.
4. Effect runner collects score modifiers after base scoring.
5. Base reasons + effect reasons combine.
6. Limit hand means `rating = Legend`, `valid_hu = true`.
7. Non-limit hands sum fan and require `fan >= 3`.
8. Best result is chosen across candidates.
9. Normal UI shows best result.
10. Inspector Mode can show all candidates.

Compatible non-limit patterns stack.

Limit hands:

- Use `is_limit = true`; do not fake huge fan numbers.
- Automatically satisfy the minimum.
- Still show non-limit fan reasons as explanatory detail.

Score reason categories:

```lua
"hand_pattern"
"modifier"
"boon"
"limit"
```

Rating is derived only at the end.

Milestone 1 uses the initial non-limit fan-to-rating curve from `docs/INITIAL-DESIGN.md`. Tune after playtesting if the curve makes ordinary wins feel too flat or limit hands feel insufficiently distinct.

### Pattern Decisions

- Ping Hu requires suited tiles only, no honors.
- Ping Hu must be a standard shape made of four Chi plus a non-honor pair.
- Ping Hu can stack with Qing Yi Se.
- Seven Pairs can include honors and mixed suits.
- Seven Pairs can stack with Hun Yi Se or Qing Yi Se.
- Hun Yi Se = exactly one numbered suit plus one or more honors.
- Qing Yi Se = exactly one numbered suit and no honors.
- Xiao San Yuan = two dragon Peng/Kong plus pair of third dragon.
- Da San Yuan = all three dragon Peng/Kong, Limit.
- Xiao Si Xi = three wind Peng/Kong plus pair of fourth wind.
- Da Si Xi = all four wind Peng/Kong, Limit.
- Zi Yi Se supports any complete all-honor shape, including Seven Pairs.
- Si Gang = four Kongs, Limit.
- Kongs count as triplets for dragon/wind/pattern checks.
- Round wind is fixed East in Milestone 1 but represented in state.

---

## Effect System

Use a typed modular effect system with query/command lifecycle.

Effects represent boons now and may later represent relics, classes, boss auras, opponent effects, and challenge modifiers.

Principles:

- Effects live in separate modules.
- Effects implement fixed typed lifecycle/query functions.
- Effects do not mutate core state directly.
- Query handlers return typed query results.
- Lifecycle/action handlers may return typed commands.
- The engine applies commands and preserves invariants.
- Content metadata is separate from behavior.
- Effects can eventually override rare rules only through explicit typed query points.

### Active Effect State

```lua
type EffectSourceKind =
  "boon"
  | "opponent_package"
  | "relic"
  | "class"
  | "boss_aura"
  | "challenge"

record ActiveEffectState
  active_effect_id: string
  effect_id: EffectId
  source_kind: EffectSourceKind
  source_id: string
  owner_player_index: integer?
  counters: {string: integer}
  used_this_deal: boolean
end
```

Deal-local counters live in `DealState.effect_states`. Persistent ownership/upgrades live in `RunState.active_effects`.

### Queries

Queries do not mutate state.

Examples:

```lua
collect_score_modifiers(ctx): {ScoreReason}
collect_available_actions(ctx): {EffectAction}
collect_draw_modifiers(ctx): {DrawModifier}
collect_opening_modifiers(ctx): OpeningModifiers
```

### Commands

Initial command vocabulary:

```lua
"increment_counter"
"set_counter"
"mark_used"
"reveal_wall_front"
"replace_concealed_tiles"
"add_log"
```

Effects should not issue generic draw commands in Milestone 1. Use constrained commands or queries.

### Effect Ordering

Effects have a priority.

- Default priority: `100`
- Lower priority runs earlier.
- Ties break by `effect_id`.
- Phase 0 effects can all use default priority.

Ordering exists for future deterministic behavior around transforms, cost changes, reveals, multipliers, and rare rule overrides.

---

## Milestone 1 Boons

Milestone 1 starter offers are sampled from the canonical starter set:

- Current
- Still Water
- Dragon's Weight
- Open Eyes
- Third Eye
- Fresh Start
- Momentum

The player chooses 1 starter boon from 3 offers before Round 1. Those 3 offers come from this curated set, not from the eventual full boon pool.

Milestone 1 reward offers may reuse this same canonical set, excluding already owned boons. Reward selection should update run state, but the selected reward does not need to feed into Round 2 because Round 2 is outside Milestone 1.

Momentum may have little or no effect in the one-round vertical slice. That is acceptable for dev/playtester Milestone 1; it should behave correctly according to `round_index`.

Initial boon behavior:

- Current counts all draws, including supplement draws.
- Current checks majority suit before adding the drawn tile.
- Tied majority suits all count.
- Still Water adds +1 fan on top of base Concealed / Men Qian.
- Dragon's Weight adds +1 fan per Dragon Peng/Kong on top of base Dragon Peng/Kong.
- Open Eyes sets Known Wall to next 3 front-Wall tiles after player completes Peng.
- Third Eye sets Known Wall to next 5 front-Wall tiles after opening deal.
- Fresh Start may swap 0-3 tiles after initial deal, before first draw/discard.
- Fresh Start returns selected tiles to Wall, reshuffles remaining Wall, draws the same number of replacements, clears Known Wall, marks used.
- Momentum contributes `round_index - 1` extra opening tiles through an opening modifier query.

---

## AI Scope

Milestone 1 AI is not defensive.

AI must:

- draw
- discard
- Hu using the same validator/scorer as the player
- react to discards with Hu/Peng/Kong/Chi where legal
- choose calls conservatively
- understand the 3 fan minimum enough to avoid nonsense calls

AI hidden information:

- AI concealed tiles are hidden in normal UI.
- Debug Inspector can reveal AI hands.

AI always Hu at 3+ fan in Milestone 1.

---

## Action Model

Use explicit typed action records, not one optional-field blob.

Every action includes `player_index`. AI and player both use the same `DealAction` path.

Illegal actions return typed errors, not crashes.

```lua
record DealTransition
  ok: boolean
  deal: DealState
  events: {DealEvent}
  error: string?
end
```

Structured `DealEvent`s are canonical. Simple debug log strings are acceptable in Milestone 1, but UI text should eventually render from structured events.

AI must use `DealAction`s and must not mutate state directly.

Effect commands are applied inside `deal_engine.apply_action`.

`apply_action` must be deterministic and return updated RNG state whenever randomness is involved.

---

## Debug UI

Build a tiny debug UI before the final table UI.

Normal Dev Mode should show:

- player hand
- AI concealed hands hidden
- AI open sets and discards
- legal player actions
- Wall count
- log
- current turn
- boons and counters
- Known Wall

Inspector Mode should show:

- AI concealed hands
- all score candidates/decompositions
- AI discard reasoning
- pending reactions
- run seed and deal seed
- tile conservation invariant result

Use a keyboard toggle such as `F1` or backtick.

---

## Test Hand Notation

Use a compact internal notation for tests.

Suits:

```text
t = tiao
w = wan
b = bing
```

Honors:

```text
E = east
S = south
W = west
N = north
F = fa_cai
H = hong_zhong
B = bai_ban
```

Examples:

```text
123t 456w 789b 55t
3F 2H E S
```

Open sets use square brackets:

```text
[123t] = open Chi
[3H] = open Peng hong_zhong
[111t] = open Peng 1 tiao
[4B] = open Kong bai_ban
```

Concealed sets use curly braces:

```text
{4B} = concealed Kong bai_ban
```

Inference:

- 3 suited consecutive tiles = Chi
- 3 identical tiles = Peng
- 4 identical tiles = Kong
- Curly braces are only valid for concealed Kong
- Invalid combinations are parser errors

The parser assigns deterministic physical tile IDs like `tiao_1_a` and errors if a notation asks for more than four copies of a tile kind.

Start notation helpers in tests. They may move into dev/debug tooling later.

---

## Milestones

### Milestone 0: Foundation

Goal: make the project safe for AI-agent-coded development before gameplay UI.

Deliverables:

- LÖVE app boots to minimal debug screen.
- Teal build pipeline works.
- `tl check` runs cleanly.
- busted tests compile and run.
- Generated Lua is ignored.
- README documents install/build/test/run commands.
- `core/types.tl` defines the domain model.
- `core/rng.tl` implements deterministic RNG.
- `game/tiles.tl` creates the 34 tile kinds / 136 physical tiles.
- `game/wall.tl` supports seeded shuffle, front draw, back draw, reveal, return-and-shuffle.
- Test hand notation helper exists.
- Initial tests cover tiles, wall, RNG, and notation.

### Milestone 1A: Rules Engine

- PlayerHand / TileSet operations.
- Full win-shape validator.
- Full listed hand pattern detection.
- Scorer with ratings, reasons, 3 fan minimum, and all candidates.
- Call legality including Chi/Peng/Kong.
- Reaction priority.
- Tile conservation invariant checks.
- Tests for scoring, validation, calls, and invariants.

### Milestone 1B: Deal Engine + Debug UI

- Deal state machine.
- Draw/discard flow.
- Reaction windows.
- Kong supplement flow.
- Qiang Gang flow.
- Win/loss deal result.
- Vanilla AI.
- Debug UI to inspect game state.

### Milestone 1C: Playable Vertical Slice UI

- Starter boon scene.
- Table scene.
- Tile selection.
- Action prompts.
- Opponent panels.
- Discards and TileSets.
- Known Wall display.
- Boon counters.
- Scoring explanation.
- Reward screen after win.
- Lose life and retry Round 1.

### Milestone 1D: Boon Integration

- Current
- Still Water
- Dragon's Weight
- Open Eyes
- Third Eye
- Fresh Start
- Momentum
- Effect tests for scoring, information, counters, and active actions.

---

## Milestone 1 Definition

Milestone 1 is a one-round vertical slice, not the full five-round tournament.

It includes:

- start screen
- choose 1 starter boon from 3 offers
- play Round 1 against 3 vanilla AIs
- Draw, Discard, Chi, Peng, Kong, Hu, Pass
- all listed hand validation/scoring/rating
- 3 fan minimum
- win deal -> reward screen with 3 boon offers
- lose deal -> lose 1 life and retry Round 1
- run ends at 0 lives
- minimal readable UI
- debug inspector

It excludes:

- Round 2+
- full opponent packages
- defensive AI
- multiplayer
- animation polish
- tutorial
- Steam/export pipeline

---

## Open Follow-Ups

- Decide exact Teal and busted installation commands once toolchain is initialized.
- Decide whether to use LuaJIT or system Lua for generated test execution.
- Define the exact `ScoreFacts` record.
- Define exact `EffectCommand` record variants.
- Define detailed AI discard heuristic weights.
- Decide whether PRD and architecture docs should be split from this plan or generated from it.
