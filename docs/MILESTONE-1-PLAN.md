# facai Milestone 1 Plan

> Status: working engineering contract for Milestone 1. This document translates the broader design into the first playable build slice, including architecture, tooling, rules decisions, milestone breakdown, and acceptance scope. It should become the source material for a Milestone 1 PRD, architecture doc, and implementation tickets.

---

## Product Goal

facai should become a Steam-quality, flexible, bespoke roguelike mahjong game. Milestone 1 is not a disposable toy prototype; it is the first build slice of the real game, scoped small enough to reach a playable vertical slice quickly.

The architecture should support the long-term vision: more boons, relics, classes, boss auras, opponent identities, ratings, unlocks, and rule-bending effects. Milestone 1 exists to sequence work, not to make short-term architecture choices that block the end vision.

Milestone 1 is the first implementation slice of the broader Phase 0 prototype described in `docs/INITIAL-DESIGN.md`. Phase 0 still describes the larger five-round prototype target; this plan describes the one-round build needed first.

## Milestone Goal

Milestone 1 should produce a one-round playable vertical slice that proves the rules engine, boon/effect architecture, AI action path, and minimal LÖVE UI can all work together.

The player should be able to start a run, choose one starter boon, play Round 1 against three vanilla AI opponents, win to reach a reward screen, or lose lives and retry Round 1.

## Definition Of Done

Milestone 1 is done when:

- `make check`, `make build`, and `make test` exist and pass.
- The game launches in LÖVE through `make run`.
- A player can complete Round 1 from starter boon selection to win reward or run loss.
- Draw, discard, Chi, Peng, Kong, Hu, Pass, Zi Mo, Gang Shang, and Qiang Gang are implemented for Milestone 1 scope.
- Hand validation, scoring, rating, and 3 fan minimum work for all listed Milestone 1 patterns.
- The seven starter boons are implemented through the typed effect system.
- AI opponents use the same `DealAction` path as the player.
- Tile conservation passes at every deal transition in tests and debug UI.
- Debug UI exposes seeds, wall count, pending reactions, score candidates, AI reasoning, Known Wall, and invariant status.
- Generated Lua in `src/` and generated specs in `spec/` are ignored and not committed.

## Product Scope

In scope:

- Round 1 only
- 3 lives
- starter boon selection from curated offers
- vanilla AI opponents
- minimal readable LÖVE UI
- debug inspector
- reward screen after a Round 1 win
- deterministic rules engine and tests

Out of scope:

- Round 2+
- full five-round tournament completion
- full opponent scripted packages
- defensive AI
- multiplayer
- animation polish
- tutorial
- Steam/export pipeline

## Work Breakdown Rules

Use the hierarchy:

```text
Milestone 1
  Slice Sxx
    Task Txx
```

Each slice must be independently reviewable and should leave the repo in a working state. Each implementation PR should reference exactly one slice and one or more tasks from this plan.

Task statuses:

- `pending`: not started
- `in_progress`: active branch/PR exists
- `done`: merged and verified
- `blocked`: cannot continue without a decision or dependency

Before starting a task, confirm:

- the slice goal
- owned files/modules
- acceptance criteria
- verification commands
- whether `docs/DECISIONS.md` needs a new entry

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
    deal_types.tl
    hand_validator.tl
    ting_distance.tl
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
  ting_distance_spec.tl
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
- **Ting / Ting Pai (聽牌):** a hand that needs exactly one more tile to form a valid Hu. Use `ting` in code. Do not use `tenpai`.
- **Ting Distance:** the number of tiles needed to reach ting. −1 = already ting. 0 = one tile away from ting. Use `ting_distance` in code. Do not use `shanten`.
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
  deal_result: DealResult?  -- populated when phase = "deal_over", nil otherwise
end

record DealResult
  winner_player_index: integer?  -- nil = wall exhaustion, no winner
  won_by_zi_mo: boolean
  score_result: ScoreResult?     -- nil if wall exhaustion
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
- Boundary rule: if the Wall has fewer tiles remaining than an effect's requested reveal count, populate `known_wall_tile_ids` with all remaining front-Wall tiles. Never error on a short wall.

---

## RNG and Determinism

Core game logic must not use `math.random` or import `love.math`.

Implement deterministic RNG in `core/rng.tl`.

Expected API:

```lua
record RngState
  state: integer      -- must be non-zero; guard in from_seed
end

record RngIntResult
  value: integer
  rng: RngState       -- next state; callers must use this, not the input rng
end

record RngShuffleTilesResult
  tiles: {Tile}
  rng: RngState
end

function from_seed(seed: integer): RngState
-- Returns new state and next u32. Does NOT mutate the input.
function next_u32(rng: RngState): RngIntResult
-- Returns new state and integer in [min_value, max_value].
function next_int(rng: RngState, min_value: integer, max_value: integer): RngIntResult
-- Returns shuffled copy and new state. Input tiles are not mutated.
function shuffle_tiles(rng: RngState, tiles: {Tile}): RngShuffleTilesResult
```

All functions are pure — no input is mutated. Callers must replace their `rng` binding with
`result.rng` after every call. `DealState.rng` and `RunState.rng` are updated through the
transition return path, not direct mutation.

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

1. Deal 13 tiles to each player from the shuffled Wall.
2. Fire `collect_opening_modifiers` query across all active effects.
3. Apply extra tile deals in priority order (passive opening modifiers that expand the opening draw).
4. Player trims to 13 by discarding extras into an `opening_trim` zone — not the table discard pile. Tile conservation must account for `opening_trim` tiles.
5. Fire opening active effects in priority order (active opening effects that let the player make choices, such as swapping tiles).
6. Normal play begins.

Ordering rationale: passive opening modifiers (automatic tile additions) resolve before active opening effects (player-driven choices) so that any automatic hand expansion is visible before the player makes active opening decisions.

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
- Multiple Kongs in one turn: each added Kong opens its own Qiang Gang reaction window before its supplement draw. A concealed Kong declared during a turn (including after a supplement draw) does not open a Qiang Gang window. After all Kong declarations and reaction windows resolve, the player draws the final supplement tile and proceeds to `awaiting_action`. If the Wall has no supplement tiles when a Kong supplement is needed, the deal ends as wall exhaustion before the Kong resolves.

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

Score reason and result types:

```lua
type ScoreReasonCategory = "hand_pattern" | "modifier" | "boon" | "limit"

record ScoreReason
  category: ScoreReasonCategory
  label: string             -- human-readable, e.g. "Qing Yi Se" or "Zi Mo"
  fan: integer              -- 0 for limit entries
  is_limit: boolean
end

record ScoreResult
  win_shape_kind: WinShapeKind
  reasons: {ScoreReason}
  total_fan: integer        -- sum of reason.fan; irrelevant when is_limit = true
  is_limit: boolean
  rating: Rating
  valid_hu: boolean         -- true if is_limit or total_fan >= 3
end

type Rating = "C" | "B" | "A" | "S" | "SS" | "Legend"
```

The scorer returns `{ScoreResult}` — one per valid win shape candidate. The engine picks the best.

Rating is derived only at the end.

Milestone 1 uses the initial non-limit fan-to-rating curve from `docs/INITIAL-DESIGN.md`. Tune after playtesting if the curve makes ordinary wins feel too flat or limit hands feel insufficiently distinct.

### Pattern Decisions

- Ping Hu requires suited tiles only, no honors.
- Ping Hu must be a standard shape made of four Chi plus a non-honor pair.
- Ping Hu can stack with Qing Yi Se.
- Seven Pairs can include honors and mixed suits.
- Seven Pairs requires exactly seven distinct tile kinds — two pairs of the same tile are not valid. The validator must verify all seven pair `tile_kind_id`s are unique.
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

Command record types (all carry a `command_kind` discriminant; the engine dispatches on it):

```lua
type EffectCommandKind =
  "increment_counter"
  | "set_counter"
  | "mark_used"
  | "reveal_wall_front"
  | "replace_concealed_tiles"
  | "add_log"

record IncrementCounterCommand
  command_kind: string          -- "increment_counter"
  active_effect_id: string
  counter_key: string
  delta: integer
end

record SetCounterCommand
  command_kind: string          -- "set_counter"
  active_effect_id: string
  counter_key: string
  value: integer
end

record MarkUsedCommand
  command_kind: string          -- "mark_used"
  active_effect_id: string
end

record RevealWallFrontCommand
  command_kind: string          -- "reveal_wall_front"
  count: integer                -- tiles to add to known_wall_tile_ids
end

record ReplaceConcealedTilesCommand
  command_kind: string          -- "replace_concealed_tiles"
  player_index: integer
  tile_ids_to_remove: {TileId}  -- engine draws replacements from wall
  reshuffle_wall: boolean       -- when true, Wall is reshuffled after replacement draws
end

record AddLogCommand
  command_kind: string          -- "add_log"
  message: string
end

type EffectCommand =
  IncrementCounterCommand
  | SetCounterCommand
  | MarkUsedCommand
  | RevealWallFrontCommand
  | ReplaceConcealedTilesCommand
  | AddLogCommand
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

Milestone 1 AI is vanilla: no defensive play, no opponent modeling, no package behavior.

### Heuristic Algorithm

The AI uses a ting-distance-based heuristic. Ting distance is the number of tiles needed to reach ting (−1 = already ting, 0 = one tile away from ting). See Core Vocabulary.

**Discard selection:**
1. For each tile in the concealed hand, compute the ting distance of the remaining hand across all applicable win shapes (standard, seven pairs, thirteen orphans).
2. Discard the tile that minimizes ting distance after removal.
3. Tiebreak: prefer to discard honor tiles, then terminals, then by `tile_kind_id` for determinism.

**Hu decision:**
- Call the scorer on the current hand + incoming tile.
- If `score_result.valid_hu = true`, declare Hu immediately.

**Call decision (Chi / Peng / open Kong):**
1. Compute ting distance of the hand if the call is made.
2. Make the call only if: (a) ting distance decreases, AND (b) the resulting open hand can plausibly reach ≥ 3 fan. Use a simple fan-floor check: if current fan potential with open sets is below 2 and no honor tiles remain, pass.
3. Never call Chi if it would break a lower-ting-distance path already available.
4. Prefer Peng over Chi when both reduce ting distance equally.

**Concealed / added Kong decision:**
- Declare only if it does not increase ting distance.

**AI always Hus at 3+ fan.** Uses the same scorer call as the player.

### Ting Distance Calculator

Implement `game/ting_distance.tl`. Expose:

```lua
function ting_distance_standard(concealed_tiles: {Tile}, open_sets: {TileSet}): integer
function ting_distance_seven_pairs(concealed_tiles: {Tile}): integer
function ting_distance_thirteen_orphans(concealed_tiles: {Tile}): integer
-- Returns min across all applicable shapes.
function ting_distance(concealed_tiles: {Tile}, open_sets: {TileSet}): integer
```

`ting_distance.tl` must be pure and must not import `love` or `ai.tl`. Add `spec_tl/ting_distance_spec.tl` in `S02` alongside validation tests.

### Debug Output

For each AI discard, emit an `AddLogCommand` with:
- the discarded tile
- the ting distance before and after
- the win shape target

### Hidden Information

AI concealed tiles are hidden in normal Dev Mode. The debug inspector reveals them. AI must not read `known_wall_tile_ids` — that field is player-only information.

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

Action types (define in `game/deal_types.tl`):

```lua
type DealActionKind =
  "draw"
  | "discard"
  | "declare_hu"
  | "declare_chi"
  | "declare_peng"
  | "declare_open_kong"
  | "declare_concealed_kong"
  | "declare_added_kong"
  | "pass_reaction"
  | "use_effect_action"

record DrawAction
  kind: string          -- "draw"
  player_index: integer
end

record DiscardAction
  kind: string          -- "discard"
  player_index: integer
  tile_id: TileId
end

record DeclareHuAction
  kind: string          -- "declare_hu"
  player_index: integer
  incoming_tile_id: TileId?  -- nil for Zi Mo (tile is already in concealed_tiles)
end

record DeclareChiAction
  kind: string          -- "declare_chi"
  player_index: integer
  tile_id: TileId            -- the discarded tile being claimed
  other_tile_ids: {TileId}   -- the two concealed tiles completing the Chi
end

record DeclarePengAction
  kind: string          -- "declare_peng"
  player_index: integer
  tile_id: TileId
end

record DeclareOpenKongAction
  kind: string          -- "declare_open_kong"
  player_index: integer
  tile_id: TileId
end

record DeclareConcealedKongAction
  kind: string          -- "declare_concealed_kong"
  player_index: integer
  tile_kind_id: TileKindId   -- the four concealed tiles of this kind
end

record DeclareAddedKongAction
  kind: string          -- "declare_added_kong"
  player_index: integer
  tile_id: TileId            -- the fourth tile being added to an open Peng
end

record PassReactionAction
  kind: string          -- "pass_reaction"
  player_index: integer
end

record UseEffectAction
  kind: string          -- "use_effect_action"
  player_index: integer
  active_effect_id: string
  payload: any?              -- effect-specific params; effects validate this
end

type DealAction =
  DrawAction
  | DiscardAction
  | DeclareHuAction
  | DeclareChiAction
  | DeclarePengAction
  | DeclareOpenKongAction
  | DeclareConcealedKongAction
  | DeclareAddedKongAction
  | PassReactionAction
  | UseEffectAction
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

## Milestone 1 Slices

### S00: Toolchain And Repo Skeleton

Status: `pending`

Goal: make the project safe for AI-agent-coded development before gameplay implementation.

Why this comes now: every later slice depends on boring, repeatable typecheck/build/test commands.

Owned areas:

- `Makefile`
- `tlconfig.lua`
- `.gitignore`
- `src_tl/`
- `spec_tl/`
- `README.md`

Tasks:

- `T01`: Add Teal, LÖVE, and busted project scaffolding.
- `T02`: Add `make check`, `make build`, `make test`, `make run`, and `make clean`.
- `T03`: Add initial source/spec directory skeletons.
- `T04`: Add Teal declarations or wrappers needed for busted/LÖVE.
- `T05`: Verify generated Lua/spec outputs are ignored.
- `T06`: Update README with real install/build/test/run commands.

Acceptance criteria:

- LÖVE app boots to a minimal debug screen.
- `make check` runs successfully.
- `make build` generates Lua into ignored output directories.
- `make test` runs busted successfully.
- No generated Lua/spec files are committed.

Verification:

```sh
make check
make build
make test
make run
git status --short
```

Out of scope:

- gameplay rules
- polished UI
- full content definitions

Completion summary:

- Fill this in when the slice is merged.

### S01: Core Tiles, RNG, Wall, And Notation

Status: `pending`

Goal: establish deterministic physical tile movement and test notation.

Why this comes now: every rules, AI, effect, and UI slice depends on tile identity, wall behavior, and deterministic randomness.

Dependencies:

- `S00`

Owned areas:

- `src_tl/core/types.tl`
- `src_tl/core/rng.tl`
- `src_tl/core/ids.tl`
- `src_tl/game/tiles.tl`
- `src_tl/game/wall.tl`
- `spec_tl/support/hand_notation.tl`
- `spec_tl/wall_spec.tl`

Tasks:

- `T01`: Define `TileKindId`, `TileId`, `Tile`, and core identity types.
- `T02`: Generate the 34 tile kinds and 136 physical tiles.
- `T03`: Implement pure deterministic xorshift32 RNG.
- `T04`: Implement Wall shuffle, front draw, back supplement draw, reveal, return-and-shuffle.
- `T05`: Implement compact test hand notation parser.
- `T06`: Add tests for tile generation, RNG determinism, wall behavior, notation parsing, and over-copy errors.

Acceptance criteria:

- All 136 physical tiles are unique and map to valid tile kinds.
- Wall operations preserve physical tile identity.
- Normal draws come from the front and supplement draws come from the back.
- Shuffles are deterministic by seed.
- Notation helpers reject impossible tile counts.

Verification:

```sh
make test
```

Out of scope:

- deal engine
- scoring
- UI

Completion summary:

- Fill this in when the slice is merged.

### S02: Hand Validation, Scoring, And Calls

Status: `pending`

Goal: prove that Hong Kong mahjong Hu validation, pattern scoring, ratings, and call legality work without UI or AI.

Why this comes now: the deal engine should call trusted rule modules rather than mix validation/scoring into state transitions.

Dependencies:

- `S01`

Owned areas:

- `src_tl/game/deal_types.tl`
- `src_tl/game/hand_validator.tl`
- `src_tl/game/ting_distance.tl`
- `src_tl/game/scorer.tl`
- `src_tl/game/calls.tl`
- `src_tl/game/deal_invariants.tl`
- `src_tl/content/hand_patterns.tl`
- `spec_tl/hand_validator_spec.tl`
- `spec_tl/ting_distance_spec.tl`
- `spec_tl/scorer_spec.tl`
- `spec_tl/calls_spec.tl`

Tasks:

- `T01`: Define `DealAction`, `PlayerHand`, `TileSet`, win shape, scoring, and event records.
- `T02`: Implement standard four-sets-pair validation.
- `T03`: Implement Seven Pairs, Thirteen Orphans, and Nine Gates validation.
- `T04`: Implement ting distance for standard, seven-pairs, and thirteen-orphans paths.
- `T05`: Implement listed hand pattern detection and fan/rating scoring.
- `T06`: Return all valid score candidates and choose the best result.
- `T07`: Implement Chi/Peng/Kong legality helpers.
- `T08`: Implement tile conservation invariant checks.
- `T09`: Add rules tests for validation, scoring, calls, and invariants.

Acceptance criteria:

- Validator returns all supported win shapes.
- Scorer enforces 3 fan minimum unless the result is a limit hand.
- Limit hands use `is_limit`, not fake fan totals.
- Call helpers enforce Chi/Peng/Kong constraints.
- Tests cover representative legal and illegal hands for every supported win shape.

Verification:

```sh
make test
```

Out of scope:

- turn sequencing
- AI
- effects/boons
- UI prompts

Completion summary:

- Fill this in when the slice is merged.

### S03: Deal Engine And Reaction Flow

Status: `pending`

Goal: implement deterministic deal state transitions from opening deal through win, wall exhaustion, reactions, and Kong flows.

Why this comes now: the engine is the integration point between rules, AI, effects, and UI.

Dependencies:

- `S02`

Owned areas:

- `src_tl/game/deal_engine.tl`
- `src_tl/game/deal_types.tl`
- `src_tl/game/deal_invariants.tl`
- `src_tl/game/run_state.tl`
- deal engine specs

Tasks:

- `T01`: Implement opening deal and `opening_actions` phase.
- `T02`: Implement draw/discard flow.
- `T03`: Implement discard reaction windows and priority resolution.
- `T04`: Implement concealed, open, and added Kong flows.
- `T05`: Implement Qiang Gang and Gang Shang flags.
- `T06`: Implement wall exhaustion and `DealResult`.
- `T07`: Ensure every transition validates or can report tile conservation.
- `T08`: Add deterministic transition tests for normal wins, opponent wins, wall exhaustion, and Kong cases.

Acceptance criteria:

- A complete deal can progress from opening to win or wall exhaustion through `DealAction`s.
- Illegal actions return typed errors.
- Tile conservation holds across draw, discard, claim, Kong, Hu, and wall exhaustion transitions.
- RNG state is updated only through transition return values.

Verification:

```sh
make test
```

Out of scope:

- AI decision quality
- LÖVE table UI
- boon behavior

Completion summary:

- Fill this in when the slice is merged.

### S04: Effect System And Starter Boons

Status: `complete`

Goal: add the typed effect architecture and implement the seven Milestone 1 starter boons through it.

Why this comes now: boons are central to the roguelike identity and should integrate through typed hooks before UI polish.

Dependencies:

- `S03`

Owned areas:

- `src_tl/effects/effect_types.tl`
- `src_tl/effects/effect_registry.tl`
- `src_tl/effects/effect_runner.tl`
- `src_tl/effects/boons/`
- `src_tl/content/boons.tl`
- `spec_tl/effects_spec.tl`

Tasks:

- `T01`: Define effect metadata, active effect state, query types, and command types.
- `T02`: Implement deterministic effect ordering.
- `T03`: Wire score modifier, opening modifier, wall reveal, tile replacement, counter, and log commands.
- `T04`: Implement Current, Still Water, and Dragon's Weight.
- `T05`: Implement Open Eyes and Third Eye Known Wall behavior.
- `T06`: Implement Fresh Start tile replacement and wall reshuffle.
- `T07`: Implement Momentum opening modifier.
- `T08`: Add tests for scoring modifiers, Known Wall, counters, command application, and ordering.

Acceptance criteria:

- Effects do not mutate deal/run state directly.
- Effects cannot bypass Hu shape validation or the 3 fan minimum.
- All seven starter boons are available as typed content and behavior modules.
- Fresh Start clears Known Wall and preserves tile conservation.

Verification:

```sh
make test
```

Out of scope:

- full boon pool
- opponent packages
- rare rule-canceling effects

Completion summary:

- Typed effect query/command architecture in `src_tl/effects/` (effect_types, effect_registry, effect_runner, boons/) with deterministic ordering by `(priority, effect_id)`.
- Six command kinds wired through `effect_runner.apply_commands`: `increment_counter`, `set_counter`, `mark_used`, `reveal_wall_front`, `replace_concealed_tiles`, `add_log`.
- Seven starter boons implemented: Current, Still Water, Dragon's Weight, Open Eyes, Third Eye, Fresh Start, Momentum.
- New `opening_actions` phase + `confirm_opening`, `discard_opening_surplus`, `use_effect_action` action handlers.
- Scoring routed through `effect_runner.apply_score_modifiers` at all three sites (Zi Mo, Hu on discard, Qiang Gang); the runner iterates every win-shape candidate post-boon and re-evaluates `valid_hu = is_limit or total_fan >= 3`. Pre-claim Hu validation in the reaction window is also boon-aware.
- DECISIONS entry D005 captures the runner-as-only-score-integration-point model.
- `make test` passes 152 / 0 / 0 (29 new tests in `spec_tl/effects_spec.tl`).
- Merged via PR #5.

### S05: Vanilla AI And Debug Inspector

Status: `complete`

Goal: make the deal playable without multiplayer by adding vanilla AI decisions and a minimal debug UI for rule inspection.

Why this comes now: AI and inspector output expose whether the engine is playable before building the final table experience.

Dependencies:

- `S03`
- `S04` for boon state visibility in the inspector

Owned areas:

- `src_tl/game/ai.tl`
- `src_tl/ui/`
- `src_tl/scenes/table_scene.tl`
- AI/debug specs as needed

Tasks:

- `T01`: Implement legal AI Hu decision using the scorer.
- `T02`: Implement ting-distance discard heuristic.
- `T03`: Implement conservative Chi/Peng/open Kong decisions.
- `T04`: Implement concealed/added Kong decisions.
- `T05`: Emit AI reasoning events/log entries.
- `T06`: Build debug table view with player hand, hidden AI hands, discards, open sets, wall count, and log.
- `T07`: Add inspector toggle showing AI concealed hands, score candidates, pending reactions, seeds, Known Wall, and invariant result.

Acceptance criteria:

- AI uses `DealAction`s and never mutates state directly.
- AI concealed tiles are hidden in normal Dev Mode and visible in Inspector Mode.
- AI does not read player-only `known_wall_tile_ids`.
- Debug UI can play through a complete deal and inspect failures.

Verification:

```sh
make test
make run
```

Out of scope:

- defensive AI
- opponent personalities/packages
- animation polish

Completion summary:

- Vanilla AI module in `src_tl/game/ai.tl` with two pure entry points: `decide_main(deal, player_index)` for own-turn decisions (zi mo → added kong → concealed kong → ting-distance discard) and `decide_reaction(deal, player_index)` for reaction windows (hu → open kong → peng → chi → pass, gated by no-ting-regression). Hu legality flows through the engine's same scorer + `effect_runner.apply_score_modifiers` path so the 3-fan minimum and boon modifiers apply uniformly.
- `AiReasoning` record returned alongside every action carries `tag`, `message`, `ting_before`, `ting_after` for the inspector / log.
- Debug table scene in `src_tl/scenes/table_scene.tl`: spectator-mode rendering, cardinal layout (East/dealer at bottom), F1 inspector overlay, T toggles step mode, S advances one engine action, R restarts with the same seed. Tile-conservation invariant is checked after every transition; failures land in the log.
- Inspector reveals AI hands, ting per seat (live-aware), score candidates near ting (iterating all win shapes, with correct men-qian detection that respects concealed kongs), deal seed, conservation result, active-effect counters, and Known Wall size.
- Live-aware ting distance (`ting_distance_live`) prunes paths whose required completing tiles are no longer drawable (already in own concealed, any open set, any discard pile, or pending discard). Threaded through the AI's discard heuristic, kong evaluation, and reaction logic. Friendly ting labels (`TING` / `Nt away` / `dead`) replace raw integers in the inspector.
- Debug scene exercises the S04 boon system end-to-end by seeding a `RunState` with Fresh Start, Third Eye, and Momentum at `round_index = 3`. Opening_actions phase fires, Known Wall populates, dealer surplus appears, and Fresh Start is interactively usable: 1-0 toggle tile selection, U use, X trim surplus, C confirm. Phase-gated so global keys (T/S/R/F1/ESC) stay live.
- Engine cleanup: `PendingAddedKong` snapshots the tile object at declaration time (new `tile: Tile` field) instead of forcing the qiang-gang resolution path to look the tile back up by id. Eliminates the "tile lost / not found" defensive error branches in `apply_qiang_gang`, `handle_hu`, and the AI's qiang-gang branch.
- Tooling: `tlconfig.lua` `gen_target = "5.1"` so generated Lua parses under LuaJIT (LÖVE's runtime); `lua_compat/bit32.lua` polyfill aliases LuaJIT's `bit` (and falls back to a 5.3+ implementation via `load()` for non-LuaJIT runtimes). Captured as D007.
- DECISIONS entries: D006 (AI is a pure decision function; the scene drives turn pumping), D007 (5.1 codegen + bit32 polyfill).
- `make test` passes 172 / 0 / 0 (16 AI tests + 4 live ting tests in addition to S04's 152).
- Merged via PRs #6 (Stage A: AI module) and #7 (Stage B: scene + inspector + tooling + live-ting).
- Known limitation surfaced by playtesting: the ting-only heuristic doesn't reason about fan, so vanilla AIs frequently reach ting on hands that can't clear the 3-fan minimum and exhaust the wall. A follow-up "Smart AI" slice will replace `pick_best_discard` and the reaction logic with target-pattern strategy (Dui Dui Hu / Hun Yi Se / Qing Yi Se / default). Surrounding infrastructure (engine integration, inspector, live ting, scene driver) carries forward unchanged.

### S05 Integration Gate

Before starting `S06`, the following must be demonstrable through the debug UI:

- [ ] A complete deal plays from opening to win or wall exhaustion without crashing.
- [ ] Tile conservation invariant passes at every deal transition.
- [ ] AI discards and calls are visible in the log with ting distance reasoning.
- [ ] At least one AI player can successfully declare Hu against the player.
- [ ] Wall exhaustion ends the deal as a loss.
- [ ] Run seed and deal seed are visible in the inspector.

If any of these fail, stay in `S05` until resolved. Do not start the playable table slice with a broken deal engine.

### S06: Smart AI (Target-Pattern Heuristic)

Status: `pending`

Goal: replace the ting-only vanilla AI with a target-pattern strategy that respects the 3 fan minimum, choosing among `dui_dui_hu`, `hun_yi_se`, `qing_yi_se`, and `default`. Migrate Known Wall to per-player state so future AI-owned info effects (boons, opponent packages) need no schema change.

Why this comes now: the S05 vanilla AI minimized live-ting only. Playtesting (seed=42) showed AIs reach ting on 1-fan paths and exhaust the wall because the heuristic doesn't reason about whether the chosen path can clear the 3-fan minimum. The target-aware heuristic also lays the groundwork for opponent packages in later milestones — a "package" is just a non-neutral `AiPersonality`.

Dependencies:

- `S05`

Owned areas:

- `src_tl/game/ai.tl`
- `src_tl/game/ai_strategy.tl` (new)
- `src_tl/game/deal_types.tl` (Known Wall migration)
- `src_tl/game/deal_engine.tl` (Known Wall migration)
- `src_tl/effects/effect_runner.tl` (Known Wall migration)
- `src_tl/scenes/table_scene.tl` (inspector target line)
- `spec_tl/ai_strategy_spec.tl` (new)
- `spec_tl/ai_spec.tl`, `spec_tl/effects_spec.tl`, `spec_tl/deal_engine_spec.tl`

Tasks (single combined PR):

Known Wall per-player migration (no runtime behavior change for the player; spec fixtures update mechanically):

- `T01`: Move `known_wall_tile_ids` from `DealState` onto `PlayerState`.
- `T02`: Update `RevealWallFrontCommand` dispatch to write to the owning player's list (uses the active effect's `owner_player_index`).
- `T03`: Update Fresh Start's reshuffle clear to target the owning player's list.
- `T04`: Update normal draw to remove the drawn tile id from the drawer's list only.
- `T05`: Update inspector to read `players[i].known_wall_tile_ids` (shows player-1 only in M1).
- `T06`: Relax the AI rule to "AI may read its own seat's `known_wall_tile_ids`" (forward-compat-only — M1 vanilla AIs do not exercise this).
- `T07`: Update specs that reference the field directly to use the per-player view.
- `T07a`: Migration completeness check — `rg known_wall_tile_ids src_tl spec_tl` returns only per-player references; no leftover `deal.known_wall_tile_ids` reads.

Target-pattern heuristic:

- `T08`: Define `TargetKind` enum (`dui_dui_hu`, `hun_yi_se`, `qing_yi_se`, `default`) and `AiPersonality` record (target weights, call appetite, tile-value bias). Hardcode `NEUTRAL` personality for vanilla AIs.
- `T09`: Define tile-value tables in `ai_strategy.tl` (tiebreakers when ting and ukeire are equal):
  - `sequence_value`: terminal=1, edge(2,8)=2, near(3,7)=3, mid(4,5,6)=4, honors=0.
  - `triplet_value`: non-yakuhai-honor=1, suited terminal=2, suited mid=3, dragon=4, seat/round wind=4.
  - The active table is selected by target (sequence-leaning targets use `sequence_value`; triplet-leaning targets use `triplet_value`).
- `T10`: Implement target evaluator: composition features (honor count, max same-suit count, pair count) → per-target score.
- `T11`: Implement ukeire computation alongside ting distance.
- `T12`: Implement `estimate_fan_for_target(deal, player_index, target): integer` — pre-ting fan ceiling for a constructed-hypothetical completion of `target`. Builds a synthetic `ScoreResult` capturing the structural facts the target implies (e.g., dui_dui_hu → all triplets; hun_yi_se → one suit + honors; qing_yi_se → one suit no honors; default → standard four-sets-pair) plus obvious modifiers (men_qian if no open sets, dragon_pung per dragon-pair-or-better). Routes the synthetic result through `effect_runner.apply_score_modifiers` so future AI-owned boons contribute. Returns the resulting fan total. This is the boon-aware filter — discards/calls/kong that would lock the AI to a sub-3-fan target are rejected.
- `T13`: `evaluate_hu` (existing) continues to handle real Hu legality at ting; it is unchanged. The strategy module distinguishes pre-ting (use `estimate_fan_for_target`) from at-ting (use `evaluate_hu`).
- `T14`: Implement target-aware `pick_best_discard`: rank candidate discards by `(filtered ting toward best target, ukeire, target alignment, tile-value)`. Filtered ting treats targets whose `estimate_fan_for_target` < 3 as infinity.
- `T15`: Implement target-aware reaction logic: calls allowed only if they don't regress projected fan and the resulting target's `estimate_fan_for_target` ≥ 3. Default target stays concealed unless a call clears 3 fan.
- `T16`: Implement target-aware concealed/added Kong evaluation. Use target-filtered ting (same filter as discard), not raw ting. Reject Kong declarations that lock the AI to a sub-3-fan path.
- `T17`: Inspector adds a per-AI-seat line: `target=hun_yi_se ting=1 ukeire=8 est_fan=5`. Render conditionally — `pass_reaction`, `zi_mo`, and `hu_on_discard` reasoning have no target line.
- `T18`: Tests cover:
  - Target selection on canonical hand shapes (honor-heavy → hun_yi_se; pair-heavy → dui_dui_hu; single-suit-heavy → qing_yi_se; mixed → default).
  - Ukeire arithmetic on representative hands.
  - `estimate_fan_for_target` returns the expected ceiling for each target shape.
  - Discard heuristic rejects a tile whose removal would lock the AI to a sub-3-fan target.
  - Concealed Kong rejected when it would lock to a sub-3-fan path.
- `T19`: Forward-compat boon test — construct an AI seat with a synthetic `+2 fan` score modifier owned by that seat; verify `estimate_fan_for_target` reflects the contribution. Locks in that the runner is wired even though M1 vanilla AIs have no real boons.
- `T20`: Manual playtest acceptance:
  - Run 5 seeds: 42, 1, 100, 12345, plus one chosen at the time of testing.
  - For each: run to completion in F1 scene. Record outcome (Hu by which seat, or wall exhaustion).
  - If wall exhaustion: confirm via inspector that all four seats are genuinely 3-fan-unreachable from their final hands.
  - Success: ≥3 of 5 terminate via Hu, OR exhaustion is justified by inspector for all seats. Capture the seed/outcome list in the slice completion summary.

Acceptance criteria:

- Each AI exposes a `target` value in `AiReasoning` (except for non-target reasoning tags like `pass_reaction` / `zi_mo` / `hu_on_discard`).
- AI does not commit to a target whose `estimate_fan_for_target` is below 3 — the heuristic prefers a worse-ting path that can clear the threshold over a better-ting path that cannot.
- Wall exhaustion on the playtest seeds is either rare, or justified by inspector when it happens.
- Per-player Known Wall: each `PlayerState` has its own `known_wall_tile_ids`. M1 vanilla AIs see empty lists since no AI owns an info effect yet. The forward-compat boon test (`T19`) exercises the runner-pathed projected-fan path.
- All existing tests pass; new tests cover target selection, ukeire, `estimate_fan_for_target`, and the boon-aware path.
- AI turns feel snappy in the F1 scene (no visible stall). No automated perf assertion in M1.

Verification:

```sh
make test
make run
```

Out of scope:

- Defensive AI.
- Opponent packages (handled in a later slice; `AiPersonality` is the extension point).
- AI-owned active boon decisions (`decide_active_boon`).
- Limit hand and Seven Pairs targets.
- Soft target stickiness across turns. Deferred — relying on natural feature stability (honor count, max-suit count, pair count change by ≤2 per draw). If targets visibly flap during playtest, add explicit per-AI scene-owned state in a follow-up.

Completion summary:

- Fill this in when the slice is merged.

### S07: Playable Round 1 UI

Status: `pending`

Goal: turn the debug-playable deal into a human-playable Round 1 flow.

Why this comes now: the rules stack should already work; this slice focuses on ergonomic play and state presentation.

Dependencies:

- `S06`

Owned areas:

- `src_tl/app/`
- `src_tl/ui/`
- `src_tl/scenes/start_scene.tl`
- `src_tl/scenes/boon_select_scene.tl`
- `src_tl/scenes/table_scene.tl`
- `src_tl/scenes/reward_scene.tl`
- `src_tl/scenes/result_scene.tl`

Tasks:

- `T01`: Implement scene stack and app wiring.
- `T02`: Implement start/run setup screen.
- `T03`: Implement starter boon selection screen with 3 curated offers.
- `T04`: Implement table view with tile rendering, player hand, opponent panels, discard piles, open sets, and wall count.
- `T05`: Implement player tile selection and discard action.
- `T06`: Implement action prompts for Chi, Peng, Kong, Hu, and Pass.
- `T07`: Implement Known Wall, boon counters, and scoring explanation displays.
- `T08`: Implement Fresh Start opening tile-swap interaction.
- `T09`: Implement reward screen after a Round 1 win.
- `T10`: Implement lose-life/retry and 0-lives run loss flow.

Acceptance criteria:

- Player can start Round 1, choose a starter boon, and play through a deal.
- Player legal actions are visible and selectable.
- The reward screen appears after player win.
- Losing a deal costs 1 life and retries Round 1.
- Run ends at 0 lives.
- Debug inspector remains available.

Verification:

```sh
make test
make run
```

Out of scope:

- tutorial
- animation polish
- full tournament advancement

Completion summary:

- Fill this in when the slice is merged.

### S08: Milestone 1 Integration And Playtest Pass

Status: `pending`

Goal: stabilize the one-round vertical slice for internal playtesting.

Why this comes now: the feature set needs a focused pass for regressions, confusing UI, and missing debug visibility before broader Phase 0 work.

Dependencies:

- `S07`

Owned areas:

- cross-cutting integration fixes
- tests
- docs

Tasks:

- `T01`: Run a full smoke pass across starter boon selection, deal play, win reward, loss retry, and run loss.
- `T02`: Add regression tests for bugs found during smoke testing.
- `T03`: Audit import boundaries and generated-file hygiene.
- `T04`: Audit HK mahjong terminology and remove accidental Japanese terminology.
- `T05`: Update README and docs where behavior or commands changed.
- `T06`: Add durable decisions or learnings to `docs/DECISIONS.md`.

Acceptance criteria:

- Definition Of Done is satisfied.
- The slice is playable enough for dev/playtester feedback.
- Known rough edges are documented as follow-up work, not hidden in the final response.

Verification:

```sh
make check
make test
make run
git status --short
```

Out of scope:

- new gameplay features beyond Milestone 1
- balance tuning beyond obvious bug fixes

Completion summary:

- Fill this in when the slice is merged.

---

## Open Follow-Ups

- Decide exact Teal and busted installation commands once toolchain is initialized.
- Decide whether to use LuaJIT or system Lua for generated test execution.
- Decide whether PRD and architecture docs should be split from this plan or generated from it.
