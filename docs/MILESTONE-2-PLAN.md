# facai Milestone 2 Plan

> Status: working engineering contract for Milestone 2. Replaces the boon system and effect architecture from Milestone 1, expands play to the full 5-round tournament, and introduces the in-deal milestone fork system, the cluster-based boon library, and the fan-driven carry-forward mechanism.

---

## Position In The Roadmap

Milestone 2 is the second implementation slice. It assumes Milestone 1 has shipped a one-deal vertical slice with a working rules engine, AI, wall model, scoring, and minimal LÖVE UI.

M2 inherits M1's foundational systems and replaces M1's effect system and boon library. It adds the in-deal roguelike layer (milestone forks), the multi-deal tournament loop, lives, and the carry-forward mechanism that bridges deals.

This plan supersedes `D005: Effects Produce Commands; The Engine Applies; The Runner Is The Only Score Modifier Hook`. A new decision record (suggested `D012: Event-Listener Boon Architecture Replaces Query/Command Effect System`) should be added to `docs/DECISIONS.md` alongside this milestone.

---

## Product Goal

facai should be a Steam-quality roguelike mahjong game. M2 delivers the full solo tournament loop with a boon system rich enough to make each run feel different. The architecture must support continued growth of the boon library without engine changes and must keep mahjong's native scoring philosophy intact.

The M2 boon system is built on a single design principle: **boons enable play, fan rewards play.** The roguelike layer gives the player tools, information, and choices. Mahjong's native fan structure does the score work. The bridge between the two is the carry-forward mechanism, which translates fan magnitude into roguelike progression.

---

## Milestone Goal

M2 produces a fully playable 5-round tournament from starter pick through Round 5 conclusion, with:

- 1 starter boon picked before each round (1 of 3, cluster-tagged)
- 4 in-deal milestone forks (set 1, set 2, set 3, ting reached)
- 26-boon library across 3 clusters (Honor, Suit, Concealed)
- Carry-forward boon selection at round end (count determined by Hu fan)
- Lives system (3 lives, retry-round on loss)
- Round transitions with opponent escalation per `INITIAL-DESIGN.md`
- Run resolution screen on Round 5 win or 0 lives

---

## Definition Of Done

M2 is done when:

- All M1 acceptance criteria still pass.
- A run can be played from start to Round 5 win or run loss.
- Starter pick screen shows 3 starter-eligible boons (one per cluster) and the player picks 1. The starter pick is just the player's first boon; it does NOT bias future offers.
- All 4 in-deal milestone forks fire correctly per the set-detection algorithm and trigger rules.
- Each fork presents 2 boons drawn randomly from the eligible boon pool (any cluster) per the offer rule.
- All 26 boons in the library are implemented through the event-listener architecture and the 6 engine primitives.
- Declined boons within a deal are excluded from re-offer that deal.
- Carry-forward selection screen at round end correctly applies Curve C and lets the player choose which earned boons cross to the next round.
- Lives mechanic correctly decrements on round loss and ends the run at 0.
- Opponent escalation per round matches `INITIAL-DESIGN.md` Phase 0 Opponent Packages.
- Run resolution screen displays final ratings, fan distribution, and run summary.
- Tile conservation passes at every deal transition under boon-stacked play.
- Debug UI exposes: starter pick, active boons (deal-scoped + carried), milestone fork history, fan-to-carry preview, opponent package state.
- M1's query/command effect system is removed; boon registry is the only effect source.

---

## Product Scope

In scope:

- Rounds 1 through 5
- 3 lives, lose 1 on round loss, retry same round
- Starter pick before each round
- 4 in-deal milestone forks per deal
- 26 boons across 3 clusters
- Carry-forward selection between rounds
- Opponent escalation (vanilla → 2 visible packages + legendary target)
- Run resolution screen
- Debug UI for boons and forks

Out of scope:

- Tournament structures beyond 5 rounds
- Boons that affect opponents directly
- Multiplayer
- Steam integration / build pipeline
- Tutorial flow
- Animation polish beyond M1's baseline
- Boon library beyond the 26 specified
- Defensive boon primitives (silence_next_discard etc.) — deferred to M3+

---

## Inherits From M1

The following are unchanged from M1 and assumed working:

- Tile model, naming, and ID generation (`src_tl/core/`)
- Wall model, RNG, deterministic shuffle (`docs/MILESTONE-1-PLAN.md` Wall Model section)
- Hand validation, max-set-decomposition, Hu shape evaluation (`docs/MILESTONE-1-PLAN.md` Hand Validation and Scoring section)
- Native HK fan calculation including Phase 0 patterns (Ping Hu through Limit hands)
- Deal state machine, pending zones, call resolution
- Action model (`DealAction` typed records)
- AI architecture from D006/D008/D010 (vanilla AI from M1; M2 adds package-driven AI)
- Debug UI baseline (seeds, wall count, AI reasoning, tile conservation)
- Test hand notation
- LÖVE integration conventions

Anything not explicitly replaced by this document continues to follow M1's contract.

---

## Replaces From M1

| M1 component | M2 replacement |
|---|---|
| Effect system: query hooks + typed commands (D005) | Event-listener architecture with 6 engine primitives |
| 7 starter boons (Current, Still Water, Dragon's Weight, Open Eyes, Third Eye, Fresh Start, Momentum) | 26 boons across 3 clusters |
| `EffectCommand` types (`RevealWallFrontCommand`, `ReplaceConcealedTilesCommand`, etc.) | Engine primitive functions called directly from boon effects |
| `ActiveEffectState.counters` | Boon-owned `state` table with typed token pools and counters |
| Single-deal flow | 5-round tournament with carry-forward |
| Reward screen at deal end | Carry-forward selection screen at round end + run resolution at run end |

The M1 boons are not preserved. Their gameplay intent is subsumed into the new library where applicable (e.g., Open Eyes' wall reveal becomes the `peek_wall` primitive used by Honor's Eye, Dragon Pulse, etc.).

---

## Architecture: Event-Listener Boon System

### Core principle

A boon is a data record that listens for engine events, evaluates a condition, and runs an effect. Effects mutate game state through a small set of engine primitives. There is no event bus, no boon-emitted events, no chain depth. Synergy is achieved purely through multiple boons listening to the same engine events; their effects sum or coexist.

### Boon record

```lua
record Boon
  id: string                          -- unique, e.g. "honor_eye"
  cluster: Cluster                    -- "honor" | "suit" | "concealed"
  name: string                        -- player-facing display name
  description: string                 -- player-facing text
  eligible_milestones: {MilestoneId}  -- ["set_1"] or ["set_1", "set_2"] for flex
  effect_type: EffectType             -- "peek" | "mulligan" | "swap" | "extra_draw" | "info" | "token"
  weight: number                      -- selection weight, default 1.0
  listens: {EventName}                -- engine events the boon hooks
  condition: function(state: BoonContext, event: EventData): boolean
  effect: function(state: BoonContext, event: EventData)
end

type Cluster = "honor" | "suit" | "concealed"
type MilestoneId = "starter" | "set_1" | "set_2" | "set_3" | "ting"
type EffectType = "peek" | "mulligan" | "swap" | "extra_draw" | "info" | "token"
```

### Engine event vocabulary

The engine emits events at well-defined points in deal flow. Events carry typed payload.

```lua
type EventName =
  -- Player draw/discard
  "on_player_draw"         -- payload: { tile: Tile }
  | "on_player_discard"    -- payload: { tile: Tile }

  -- Calls
  | "on_chi"               -- payload: { tile_set: TileSet, source_player: int }
  | "on_peng"              -- payload: { tile_set: TileSet, source_player: int }
  | "on_kong"              -- payload: { tile_set: TileSet, kind: KongKind, source_player?: int }
  | "on_ankan"             -- payload: { tile_set: TileSet }

  -- State transitions
  | "on_set_formed"        -- payload: { set_index: 1|2|3, set: TileSet, kind: SetKind }
  | "on_ting_reached"      -- payload: { wait_kind: TingShape }
  | "on_hu"                -- payload: { fan_total: int, hand: HandSnapshot }

  -- Opponent events (player observes)
  | "on_opponent_discard"  -- payload: { opponent_index: int, tile: Tile }
  | "on_opponent_call"     -- payload: { opponent_index: int, call_kind: CallKind, tile_set: TileSet }
  | "on_opponent_draw"     -- payload: { opponent_index: int, tile: Tile }

  -- Tile-property events (auto-derived from on_player_draw / on_player_discard / on_opponent_*)
  | "on_honor_drawn"
  | "on_honor_discarded"
  | "on_dragon_drawn"
  | "on_dragon_set_formed"
  | "on_wind_set_formed"
  | "on_dominant_suit_drawn"
  | "on_off_suit_discarded"
  | "on_opponent_honor_discarded"
  | "on_opponent_dominant_suit_discarded"

  -- Per-turn events
  | "on_turn_start"        -- payload: { turn_index: int }
  | "on_turn_end"          -- payload: { turn_index: int }

  -- Deal lifecycle
  | "on_deal_start"
  | "on_deal_end"          -- payload: { result: DealResult }
```

The engine derives tile-property events automatically from base draw/discard events plus the boon's chosen suit/honor target. For example, when `on_player_draw { tile = Red Dragon }` fires, the engine also fires `on_honor_drawn` and `on_dragon_drawn` to any boon listening for them.

### The 7 engine primitives

Boon effects call only these primitives. Adding new boons in the same families requires no new primitives.

```lua
-- 1. Peek upcoming wall tiles, visible to player only
peek_wall(n: integer, filter?: function(Tile): boolean): {Tile}

-- 2. Live counter that updates on relevant state changes
live_counter(filter: function(Tile): boolean, scope: CounterScope): CounterHandle
  -- scope: "wall" | "opponent_discards" | "all_discards"

-- 3. Discard the just-drawn tile, take next wall tile in its place
discard_and_redraw(): Tile

-- 4. Swap a hand tile with the next wall tile; swapped tile goes to player's discard
swap_hand_for_wall(hand_tile: Tile): Tile

-- 5. Take an additional wall tile beyond the normal turn draw
--    Per P8 invariant: caller is responsible for the corresponding extra discard
extra_draw(): Tile

-- 6. Show one opponent's last drawn tile to the player
reveal_opponent_last_draw(opponent_index: integer): Tile?

-- 7. Take a tile from any player's discard pile into the player's concealed hand,
--    instead of drawing from the wall. Subject to age restriction per pile.
--    Drastic mechanic (P10); bounded by player's own turn + age restrictions.
take_from_discard_pile(
  pile_owner: PlayerIndex,
  tile_id: TileId,
  min_age_turns: integer  -- 0 for own pile, ≥5 for opponent piles
): Tile
```

Plus state primitives for token mechanics (not gameplay primitives, but boon-state utilities):

```lua
grant_token(boon_id: string, token_kind: string, count: integer)
spend_token(boon_id: string, token_kind: string, count: integer): boolean
get_tokens(boon_id: string, token_kind: string): integer
```

### Listener registry

A registry maps engine events to listening boons. On each event emit:

1. Engine looks up all boons listening for the event
2. For each, evaluate the boon's `condition` function with state and event payload
3. If true, run the boon's `effect` function (which calls primitives)
4. Engine validates state invariants (tile conservation, etc.) after each effect

Effects run in registration order. Multiple boons listening to the same event execute sequentially; the engine commits state after each.

### Boon scope

Two scopes:

- **Deal-scoped**: boon active only for the current deal. Default for milestone-fork boons. Evaporates at `on_deal_end`.
- **Run-scoped**: boon active for the full run (until run end). Includes carried boons from previous rounds and the current round's starter pick.

Scope is a property of how the boon is acquired, not the boon itself. The same `Boon` record can be active in either scope depending on whether it was earned in-deal or carried forward.

### State storage

```lua
record RunState
  active_boons_run_scoped: {ActiveBoon}     -- carried + current-round starter
  active_boons_deal_scoped: {ActiveBoon}    -- earned this deal
  lives: integer
  current_round: integer
  fan_history: {integer}                     -- fan from each won deal
  -- ...
end

record ActiveBoon
  boon_id: string
  acquired_at: AcquisitionPoint  -- "starter" | "set_1" | "set_2" | "set_3" | "ting" | "carried"
  state: {string: any}            -- token pools, counters, etc.
end

type AcquisitionPoint = "starter" | "set_1" | "set_2" | "set_3" | "ting" | "carried"
```

The engine maintains both lists. On event emit, both are queried.

### Determinism

For a given seed:

- Wall is deterministic (M1 contract).
- Boon offer pool at each milestone is deterministic from `(seed, round_index, milestone_id, prior_pick_history)` — derived via a deterministic shuffle of eligible boons. Different play paths (different declines/picks) produce different downstream offers even with the same seed.
- Player picks affect downstream deal flow but not the offer pool composition.

Offer determinism enables save/replay and testing.

---

## Milestone Forks (In-Deal)

### Trigger structure

Four milestones per deal, all hand-progress-based:

| Milestone | Trigger |
|---|---|
| **Set 1** | First time the player's hand contains 1 set (max-set-decomposition) at end-of-turn |
| **Set 2** | First time the player's hand contains 2 sets at end-of-turn |
| **Set 3** | First time the player's hand contains 3 sets at end-of-turn |
| **Ting** | First time the player reaches ting (any ting shape) |

### Set-detection algorithm

End-of-turn evaluation, max-set-decomposition. Same algorithm as M1's Hu shape validation; boon engine reuses it.

A "set" is any of:

- Chi (run of 3 consecutive same-suit tiles)
- Peng (3 of a kind)
- Kong (4 of a kind, declared as kong)
- Concealed pung (3 of a kind in concealed hand, evaluated as a set for milestone purposes)

The engine computes the **maximum number of disjoint sets** the hand can be decomposed into. If a tile can be used in a chi or a pung, the algorithm picks whichever maximizes total set count.

For ambiguous decompositions (1-2-3-3-3 could be chi 1-2-3 + pair 3-3 + leftover 3, or pung 3-3-3 + chi 1-2 partial), the algorithm returns the highest set count.

### Trigger rules

1. **End-of-turn evaluation**: forks fire after the player's discard resolves, not on draw or call.
2. **Highest-count-reached**: if max-sets crosses a new threshold (1, 2, or 3), fire that milestone fork. If the hand later drops back below the threshold (e.g., concealed pung broken via discard), the fork does not re-trigger when the count climbs again.
3. **No re-fire**: each of set_1, set_2, set_3, ting fires at most once per deal.
4. **Adjacent forks**: if multiple milestones fire on the same turn (e.g., set_3 + ting on a single tile completion), they fire in order: set_n first, then ting. Two consecutive modal picks. Acceptable.

### Special case: ting in pair-wait

In pair-wait ting (4 sets + 1 single), max-set-decomposition reports 4 sets. The set_3 fork has already fired (when the 3rd set formed). The ting fork fires on the same turn the 4th set forms because reaching ting is the triggering condition.

There is no set_4 fork; the 4th set's completion is the Hu, which ends the deal.

### Forks suppress on call

If a milestone would fire mid-call (e.g., a peng that immediately gives the player a set), the fork resolution waits until call processing completes, then fires before the next player action.

---

## Cluster System

### The three clusters

| Cluster | Theme | Trigger flavor |
|---|---|---|
| **Honor** | Wind and dragon tile commitment | Honor draws, dragon set formation, honor pair at ting |
| **Suit** | Single-suit purity | Dominant-suit draws, off-suit discards, opponent suit-discards |
| **Concealed** | No-call play | No-call turns, concealed pung formation, concealed ting |

### Cluster commitment is behavioral, not engine-enforced

The starter pick is simply the player's first boon. It does NOT bias future offers toward any cluster. Cluster commitment is achieved by the player actively choosing in-cluster boons whenever the offer pool surfaces them. RNG determines what's available each fork; the player chooses what to pursue.

Trade-off: high variance per run (the same starter can lead to very different builds depending on which boons RNG offers), strong roguelike feel. The cost is that committed cluster builds are not guaranteed — players sometimes have to pivot when RNG doesn't cooperate, or skip an opportunity to commit when offered cross-cluster choices.

### Offer rule

At each milestone fork, the engine constructs a 3-boon offer:

1. Filter boon registry to those eligible at the current milestone (`milestone_id in boon.eligible_milestones`) and not already picked or declined by the player this deal.
2. Draw 3 random boons from the filtered pool. The 3 may belong to the same cluster or different clusters.
3. Present all three to the player. Mandatory pick (no skip).

There is no guarantee that any specific cluster will appear at any given fork. The pre-deal starter pick declares no cluster lock — it is just the first boon.

Probability calibration: with ~9 eligible boons per milestone (~3 per cluster), drawing 3 random offers yields a ~76% chance that at least one is in any specific cluster. Committed cluster play is viable; ~24% of forks will require pivoting away from the player's intended cluster.

**Exhaustion fallback**: if the eligible pool has fewer than 3 boons remaining (defensive only — extremely rare given pool sizes and exclusion rates), the fork offers however many are available, or skips silently if zero.

### Re-offer rule

A boon offered and declined within a deal is excluded from subsequent forks that deal. A boon picked is also excluded (already held). On round end, all exclusions reset.

### Eligibility flexibility

Some boons are eligible at multiple milestones. The registry's `eligible_milestones` field is a list. Examples:

- `Honor Sense` is eligible at set_1 and set_2 — it's a peek-on-opponent's-honor-discard which works across early/mid game.
- `Concealed Mulligan` is eligible at set_1 and set_2 — it's a one-shot mulligan that can fit either early-fork slot.

Flex eligibility increases pool variance per milestone without bloating the boon count.

---

## Boon Design Principles

Every boon — current and future — must align with these principles. Designs that violate them should either be rejected or trigger explicit revision of the principle itself.

### Foundational philosophy

**P1: Boons enable play; fan rewards play.**
Boons give the player tools, information, and actions. Mahjong's native HK fan structure does all score work. The roguelike layer should not duplicate or pile on top of HK's scoring.

**P2: Carry-forward via fan is the deal-to-run bridge.**
Native fan at Hu determines how many earned boons cross into the next round (Curve C). This is the only mechanism that converts in-deal achievement into run-level progression. Hand patterns matter because of this conversion — not because boons add fan.

### Inclusion criteria — every boon must pass these

**P3: Decision-changing.**
*"Name a mid-deal decision where this boon shifts the EV of an option."* Boons that don't change any decision are decoration. Flat-multiplier boons fail this.

**P4: Information must reveal genuinely hidden info, not compute public info.**
The wall, opponent hand contents, and opponent state (e.g., ting) are hidden — valid reveal targets. Discards, melds, hand sizes, wall count are public — counting them is cognitive offload, not advantage.

**P5: Cluster commitment is rewarded through triggers, not naming.**
A boon belongs to a cluster because its trigger references that cluster's commitment (honor draws/sets, dominant-suit involvement, no-calls play). A "Honor boon" that fires on any tile draw isn't really an Honor boon.

**P6: No strictly-weaker variants.**
If boon B is strictly worse than boon A on every axis, B does not exist in the library. Power-level tiers are fine; pure dominance is not.

**P7: No strict overlap on identical gates.**
Two boons that fire on the exact same trigger condition compete unfairly — players want both, can have only one. Differentiate triggers, or merge into one boon.

### Mechanical rules — every boon must respect these

**P8: End-of-turn hand-size invariant.**
`hand_size = 13 + (kongs_declared_by_player)`. Any boon adding a wall draw must force a corresponding extra discard. Extra discards are callable normally.

**P9: Mahjong's rule fabric is foundational.**
Boons do not violate call windows (only just-discarded tiles are callable for the brief standard window), turn ordering (calls cut to caller's seat), or tile conservation (every tile accounted for exactly once).

**P10: Drastic mechanics are allowed within bounded scope.**
Roguelike feel comes partly from bending rules. Boons can introduce mechanics not native to mahjong — but only when bounded by: firing on the player's own turn, accumulating from natural play events, or having age/recency restrictions that preserve fairness. *Salvage Hand* is the template: takes from older discards only, fires on own turn, accumulating trigger.

### Pattern preferences — design choices we lean toward

**P11: Accumulating triggers beat arbitrary caps.**
"Every N events" feels natural and scales with play. "X times per deal" creates use-it-or-lose-it anxiety and exposes arbitrary design intent. Use accumulators unless there is a specific reason to cap.

**P12: Action density balances info density per cluster.**
A cluster heavy in info-only boons feels thin. Each cluster needs active mechanics that shape the hand toward the cluster's goal. Rough heuristic: at least one-third of a cluster's boons should be action-changing, not info-only.

**P13: Tokens convert events into deferred actions.**
Granting tokens for an event (e.g., concealed turn, dragon set) lets the player accumulate, then spend deliberately. Strong pattern for cluster commitment that pays out as the player chooses.

**P14: Cluster gates apply on spend, not just earn.**
If a token or effect is earned via cluster-themed behavior, it should require ongoing cluster commitment to spend. Players who drift out of the cluster's behavior lose access to earned resources.

### Engineering rules

**P15: Reuse engine primitives.**
The 6 primitives (`peek_wall`, `live_counter`, `discard_and_redraw`, `swap_hand_for_wall`, `extra_draw`, `reveal_opponent_last_draw`) are the engine's contract. New boons should compose from these. New primitives are expensive — each adds engine surface, AI awareness considerations, and UI cost.

**P16: Determinism from seed.**
Offer pools and effect resolutions are deterministic given (seed, player history). Random selections inside boons are seed-derived. Required for save/replay and testing.

---

## Boon Library (24 Boons)

Distribution: Honor 8, Suit 8, Concealed 8.

All boons in this library have been audited against the Boon Design Principles. Every boon passes P3 (decision-changing), P4 (hidden info or action), P5 (cluster commitment via trigger), P6 (no strict dominance), and P7 (no identical-gate overlap). The library is biased toward P11 (accumulating triggers) and P12 (action density).

### Honor cluster (8 boons)

| Milestone | Boon | Description |
|---|---|---|
| starter | **Honor's Gift** | At deal start, choose one honor type (your "marked honor"). See live count of marked honor remaining in the wall. |
| set_1 | **Honor's Eye** | When you draw any honor tile, peek the next wall tile. |
| set_1 (flex set_2) | **Honor Sense** | Every 3rd opponent honor discard, peek 2 wall tiles. |
| set_2 | **Dragon Pulse** | Every dragon set you form (peng/kong/concealed pung of dragons), gain 1 wall-peek token AND 1 mulligan token. No cap. Tokens freely spendable. |
| set_2 (flex set_3) | **Honor Hunt** | Every 4 of your honor-tile draws, on your next turn take an extra wall tile (extra discard required per P8). No cap. |
| set_3 | **Honor Heart** | Every honor peng or kong you complete, take the next wall tile as a free extra draw + extra discard per P8. No cap. |
| set_3 (flex ting) | **Sacred Eye** | When you reach ting where your winning hand's pair is honors, see all opponents' last drawn tiles for the rest of the deal. |
| ting | **Honor Sanctum** | When you reach ting holding 4+ honor tiles (across sets, pair, singletons), peek 1 wall tile each turn for the rest of the deal. |

### Suit cluster (8 boons)

| Milestone | Boon | Description |
|---|---|---|
| starter | **Pure Path** | At deal start, choose one suit (becomes your dominant suit). See count of dominant-suit tiles in each opponent's starting hand. |
| set_1 (flex set_2) | **Cleanse** | Once per deal, post-draw and pre-discard, swap an off-suit tile from your hand for the next wall tile. Swapped tile goes to your discard pile, callable normally. Then make your normal turn discard. Net: 2 wall consumed, 2 discards. |
| set_1 (flex set_2) | **Suit Drift** | One-shot effect on acquisition: when picked at a fork, the fork modal extends to prompt for a new dominant suit. Pure Vision and other dominant-suit-referencing boons retarget immediately. Past dominant-suit effects are immutable. |
| set_2 | **Pure Vision** | Live count of dominant-suit tiles remaining in the wall. |
| set_2 (flex set_3) | **Suit Lure** | When you draw a non-dominant-suit tile, you may immediately discard it and take the next wall tile. Discarded tile callable normally. No cap. |
| set_3 | **Suit Bind** | Once per deal, when you have ≥7 dominant-suit tiles in hand, draw 2 wall tiles instead of 1, then discard 2 from your hand. Net: 2 wall consumed, 2 callable discards. |
| set_3 | **Suit Beacon** | Every dominant-suit chi you complete, take the next wall tile as a free extra draw + extra discard per P8. No cap. |
| ting | **Suit Sentry** | When you reach ting on a pure dominant-suit wait (all wait-tiles are dominant suit), peek 1 wall tile each turn for the rest of the deal. |

### Concealed cluster (8 boons)

| Milestone | Boon | Description |
|---|---|---|
| starter | **Hidden Path** | Start the deal with 1 mulligan token and 1 wall-peek token. Tokens spendable only while you have made no calls (per P14). |
| set_1 (flex set_2) | **Concealed Mulligan** | Once per deal, if you have made no calls yet, discard the drawn tile and take the next wall tile. |
| set_1 (flex set_2) | **Silent March** | Every 3 consecutive turns you remain concealed (no calls by you), gain 1 wall-peek token. Counter resets on any of your calls. Tokens spendable only while still concealed (P14). |
| set_1 (flex set_2) | **Concealed Insight** | Every 4 of your discards while you have made no calls, peek 1 wall tile. |
| set_2 | **Hidden Strength** | Every concealed pung formed (3rd matching tile remaining in your concealed hand at end-of-turn), peek 3 wall tiles. No re-trigger if the pung is later broken and reformed. No cap on distinct pungs formed. |
| set_2 (flex set_3) | **Salvage Hand** | Every 4 of your discards while you have made no calls, on your next turn you may take a tile from any pile (your own pile: any age; opponent piles: tile must have been discarded ≥5 table-wide turns ago) into your concealed hand instead of drawing from the wall. Tile stays concealed. Make your normal discard. |
| set_3 | **Silent Stand** | Every 5 consecutive turns you remain concealed, gain 1 mulligan token. Counter resets on any of your calls. Tokens spendable only while still concealed (P14). |
| ting | **Closed Eye** | When you reach concealed ting, peek 1 wall tile each turn for the rest of the deal. |

### Effect type breakdown

| Type | Boons |
|---|---|
| Peek (`peek_wall`) | Honor's Eye, Honor Sense, Honor Sanctum, Suit Sentry, Concealed Insight, Hidden Strength, Closed Eye |
| Live counter (`live_counter`) | Honor's Gift, Pure Path (deal-start one-shot reveal of opponent suit counts), Pure Vision |
| Mulligan (`discard_and_redraw`) | Concealed Mulligan, Suit Lure; via tokens: Hidden Path, Dragon Pulse, Silent Stand |
| Swap (`swap_hand_for_wall`) | Cleanse |
| Extra draw (`extra_draw`) | Honor Hunt, Honor Heart, Suit Bind, Suit Beacon |
| Reveal opponent (`reveal_opponent_last_draw`) | Sacred Eye |
| Take from discard pile (`take_from_discard_pile`) | Salvage Hand |
| Tokens (granted/spent state) | Hidden Path, Dragon Pulse, Silent March, Silent Stand |
| State mutation (cluster-targeting) | Suit Drift (changes dominant suit; one-shot on acquisition) |

### Cluster commitment summary

| Cluster | Commitment signal | Action mechanics | Token sources | Cluster gate philosophy |
|---|---|---|---|---|
| **Honor** | Honor tile draws/sets, marked honor type, honor pair at ting | Honor Hunt, Honor Heart, Dragon Pulse tokens | Dragon Pulse (every dragon set) | Tokens spendable freely; gate is on earning (must form dragon sets) |
| **Suit** | Dominant suit committed; ≥7 dominant in hand for some boons | Cleanse, Suit Lure, Suit Bind, Suit Beacon | None (no token boons in Suit) | No token gate; effect gates on dominant suit involvement at trigger |
| **Concealed** | No calls by player | Concealed Mulligan, Hidden Strength, Salvage Hand | Hidden Path, Silent March, Silent Stand | Tokens earned via concealed play; spend gated on player still concealed (P14) |

---

## Tournament Structure

### 5 rounds

The run is 5 mahjong deals against escalating AI opponents. Each round is one deal. The player wins the round by Hu'ing first; loses by an opponent Hu'ing, by wall exhaustion, or by Hu'ing below the 3-fan minimum.

### Lives

The player starts with 3 lives. Loss handling:

| Outcome | Effect |
|---|---|
| Player Hu at ≥3 fan | Win round. Choose carry-forward boons. Advance. |
| Opponent Hu | Lose 1 life. Retry same round. |
| Wall exhausts with no valid Hu | Lose 1 life. Retry same round. |
| Player Hu below 3 fan | Hand does not count, deal continues (same as M1) |
| 0 lives reached | Run ends with loss screen |

Lives persist across rounds. They do not regenerate.

### Round transitions

After winning a round:

1. Compute fan total for Hu.
2. Compute carry slots from fan via Curve C (see Carry-Forward Mechanism).
3. Show carry-forward selection screen with all earned deal-scoped boons + already-carried boons.
4. Player picks which boons to retain in the run-scoped pool (subject to cap).
5. Advance to next round. Show pre-round summary.
6. Player picks 1 starter from 3 (one starter-eligible boon per cluster). Starter is added to the run-scoped pool. No bias is set; future offers are still random.
7. New deal begins with run-scoped pool active and 4 fork slots open.

### Opponent escalation

Per `INITIAL-DESIGN.md`:

| Round | Opponent setup |
|---|---|
| 1 | Vanilla. No packages. |
| 2 | Each opponent has 1 visible package. |
| 3 | Each opponent has 1 visible package; 1 opponent declares a target hand. |
| 4 | Each opponent has 2 compatible visible packages. |
| 5 | Each opponent has 2 compatible visible packages; 1 opponent declares a legendary target. |

Opponent packages from `INITIAL-DESIGN.md` Phase 0 Opponent Packages: Pure Suit, Triplet Hunter, Dragon Chaser, Concealed Hand, Fast Hand, Legend Chaser.

Package implementation is AI behavior tuning, not the boon system. Packages are visible to the player but do not interact with the player's boons.

### Run resolution

Run ends on:

- Round 5 win → run win screen (final ratings, fan distribution by round, full boon history)
- 0 lives → run loss screen (round reached, fan from won rounds, full boon history)

---

## Carry-Forward Mechanism

### Fan-to-carry curve (Curve C)

| Fan @ Hu | Carry slots |
|---|---|
| 3 (chicken Hu) | 0 |
| 4-5 | 1 |
| 6-8 | 2 |
| 9-12 | 3 |
| 13+ | 4 |

Chicken Hu carries nothing. This is the design lever that pushes players toward bigger hands. Limit hands cap at 4 carry slots (no special bonus for Limit beyond the 13+ tier).

### Selection

After winning, the player sees all earned deal-scoped boons (1 starter + 4 fork picks = up to 5) plus already-carried boons from previous rounds.

The player picks `carry_slots` boons to **add** to the run-scoped pool. Already-carried boons remain (they don't need re-selection). New picks added to the pool.

### Carry pool cap

Maximum carried + run-scoped = **8 boons** (excluding the current round's starter pick). Calibration: Curve C grants up to 4 carries per round across 4 round-transitions (max 16 theoretical carries); cap at 8 lets the player accumulate freely through rounds 1-2, then makes drop decisions in rounds 3-5 — matching the "build identity → defend identity" arc.

If the cap would be exceeded, the carry-forward screen requires the player to also drop one or more existing carries to make room. Drops happen in the same screen.

### Persistence

- Run-scoped boons persist through round losses (lives, retries) and round transitions.
- They do not persist across runs.
- Lives are independent of carry pool — losing lives does not affect carries.

### M1 preview (not active)

If M2 ships incrementally and an early version still runs only round 1, the deal-end screen should display:

```
You won with N fan.
You would have carried K of your earned boons to round 2.
[Continue]
```

This is a forward-compatibility preview. Once round 2-5 are implemented, the message is replaced by the actual selection screen.

---

## Domain Model Updates

### RunState extensions

```lua
record RunState
  -- existing M1 fields (seed, current_round, lives, etc.)

  active_boons_run_scoped: {ActiveBoon}
  carry_history: {RoundCarryRecord}
  fan_history: {integer}               -- fan from each won deal
  declined_boons_this_deal: {string}   -- boon_ids declined at forks this deal
end

record ActiveBoon
  boon_id: string
  acquired_at: AcquisitionPoint
  state: {string: any}                 -- token pools, counters, custom fields
end

record RoundCarryRecord
  round_index: integer
  fan_at_hu: integer
  carry_slots_granted: integer
  boons_carried: {string}
  boons_dropped: {string}              -- if cap forced drops
end
```

### DealState extensions

```lua
record DealState
  -- existing M1 fields

  active_boons_deal_scoped: {ActiveBoon}
  fork_history: {ForkRecord}
  set_count_high_water: integer        -- highest set count reached this deal
  reached_ting: boolean
  player_call_count: integer           -- total calls made by player this deal
end

record ForkRecord
  milestone_id: MilestoneId
  fired_at_turn: integer
  offered_boons: {string}              -- 2 boon_ids
  picked_boon: string
end
```

### Boon registry

A separate file (`src_tl/content/boons.tl`) defines the catalog as plain data:

```lua
local boons: {Boon} = {
  -- Honor cluster
  {
    id = "honors_gift",
    cluster = "honor",
    name = "Honor's Gift",
    description = "At deal start, choose one honor type. See its live remaining count in the wall throughout the deal.",
    eligible_milestones = {"starter"},
    effect_type = "info",
    weight = 1.0,
    listens = {"on_deal_start"},
    condition = function(ctx, ev) return true end,
    effect = function(ctx, ev)
      local chosen = ctx:prompt_player_for_honor_choice()
      ctx:set_state("chosen_honor", chosen)
      ctx:start_live_counter(function(t) return t.id == chosen end, "wall")
    end,
  },
  -- ... 25 more
}

return boons
```

Adding a boon = 1 entry in this file. No engine code changes.

---

## Migration From M1

### What changes

1. M1's `effect_runner.tl`, `EffectCommand` types, and `ActiveEffectState.counters` are removed. Listener registry replaces them.
2. M1 boons (Current, Still Water, etc.) are removed from the codebase. Test fixtures updated.
3. M1's `collect_score_modifiers` and other query hooks are removed. Boons that need scoring access listen for `on_hu` and read the hand snapshot from event payload.
4. `D005` is marked superseded by the new decision record.

### What stays

1. The scorer remains the only place that computes total fan. Boons listening to `on_hu` can read the fan total but cannot mutate it.
2. The 3-fan minimum stays in the scorer (D005's invariant). Boons cannot Hu a hand below 3 fan.
3. Hu shape validation still runs before any boon participation.

### Migration order

The slice plan below sequences M1 removal alongside M2 implementation so the codebase never enters a state where neither system works.

---

## Slice Breakdown

Slices continue M1's numbering convention but reset to M2-prefix to disambiguate. Each slice is independently reviewable and PR-able.

### M2-S00: Boon Architecture Foundation

Goal: stand up the event-listener engine without removing M1's effect system.

Tasks:

- T00: Define `Boon`, `ActiveBoon`, `EventName` types in `src_tl/effects/types.tl` (or successor location).
- T01: Implement event registry and dispatcher.
- T02: Implement the 7 engine primitives as standalone functions: `peek_wall`, `live_counter`, `discard_and_redraw`, `swap_hand_for_wall`, `extra_draw`, `reveal_opponent_last_draw`, `take_from_discard_pile`.
- T03: Implement token state primitives (`grant_token`, `spend_token`, `get_tokens`).
- T04: Wire event emission at existing engine points (draw, discard, call, set-formed, ting, hu, deal-start, deal-end). M1's effect runner remains active in parallel.
- T05: Add `BoonContext` type that exposes state mutation API to boons.
- T06: Tests for primitives and event dispatch with a minimal stub boon.

Acceptance: a stub "test boon" registered against `on_player_draw` can be observed firing and calling `peek_wall(1)` correctly.

### M2-S01: Milestone Fork Mechanism

Goal: detect set-formation and ting milestones; emit fork events.

Tasks:

- T00: Implement set-count detection at end-of-turn using max-decomposition (reuses M1's hand validation).
- T01: Track `set_count_high_water` on `DealState`; fire `on_set_formed` when crossed.
- T02: Detect ting reached; fire `on_ting_reached`.
- T03: Handle adjacent fork firing (set_3 + ting same turn) — sequential modal queue.
- T04: Update debug UI to show set count and milestone status.
- T05: Tests covering: concealed pung formation, called set formation, set break-then-reform (no re-fire), pair-wait ting same turn as set_3.

Acceptance: in a scripted deal, all 4 milestones fire in correct order and only once per deal.

### M2-S02: Boon Registry And Offer Pool

Goal: load boons from data and present offers at milestones.

Tasks:

- T00: Create `src_tl/content/boons.tl` registry with first 6 boons (one per cluster per milestone, just enough to validate the offer pool).
- T01: Implement `eligible_at(milestone, cluster)` registry query.
- T02: Implement deterministic offer-pool composition: draw 3 random eligible boons from the registry filtered by milestone-eligibility + not-already-picked-or-declined this deal. Seeded random.
- T03: Implement `decline` exclusion (boon excluded for rest of deal).
- T04: Hook offer-pool to milestone fork events.
- T05: Minimal fork modal UI (text-only, scene placeholder).

Acceptance: a player-driven test deal triggers fork modals at each milestone and presents 2 boons; declined boons don't re-appear.

### M2-S03: Cluster Starter Pick

Goal: pre-deal starter selection screen.

Tasks:

- T00: Pre-deal scene: show 3 starter options (1 per cluster).
- T01: Player pick adds the boon to the run-scoped pool. No cluster bias is set — future offers remain random across all clusters.
- T02: Visual cluster icons + descriptions in starter-pick UI.
- T03: Integration test: starter pick correctly biases milestone offers within the deal.

Acceptance: starter pick screen → starter added to run-scoped pool → milestone offers draw randomly from the registry (Model B verified).

### M2-S04: Full Boon Library Implementation

Goal: implement all 24 boons as registry data.

Tasks:

- T00-T07: Honor cluster (8 boons).
- T08-T15: Suit cluster (8 boons).
- T16-T23: Concealed cluster (8 boons).
- T24: Boon-by-boon test fixtures verifying each boon's effect under triggering conditions.
- T25: Token-mechanic boons (Hidden Path, Dragon Pulse, Silent March, Silent Stand) tested for grant/spend correctness. Concealed-cluster token spend gating (P14) verified.
- T26: Accumulating-trigger boons (Honor Sense, Honor Hunt, Honor Heart, Suit Lure, Suit Beacon, Hidden Strength, Concealed Insight, Salvage Hand, Silent March, Silent Stand) tested for correct event counting and reset behavior.
- T27: Drastic-mechanic boon (Salvage Hand) tested for age-restriction (own pile any age; opponent piles ≥5 table-wide turns), pile-source UI, and tile conservation under reclaim.
- T28: Integration test: stack 3 boons in same cluster, verify additive synergy on shared events.

Acceptance: all 24 boons fire correctly under their triggering events; tile conservation passes under boon-stacked play; end-of-turn hand-size invariant (P8) holds under all extra-draw boon combinations.

### M2-S05: M1 Effect System Removal

Goal: remove the query/command effect system.

Tasks:

- T00: Replace M1 boon usages in test fixtures with M2 boon equivalents.
- T01: Remove `effect_runner.apply_commands` and `EffectCommand` types.
- T02: Remove M1 boon modules (`Current`, `Still Water`, etc.).
- T03: Update `D005` decision record to "superseded by D012".
- T04: Add `D012: Event-Listener Boon Architecture` to `docs/DECISIONS.md`.
- T05: Verify M1 acceptance still passes (deal flow, scoring, AI) under M2 boon system.

Acceptance: `make test` passes; M1 query/command code is fully removed; new decision record landed.

### M2-S06: Multi-Round Tournament Loop

Goal: rounds 2-5 playable with round transitions.

Tasks:

- T00: Implement `RunState.current_round` advancement on round win.
- T01: Round transition scene: deal end → carry-forward selection (placeholder; selection UI in S07).
- T02: Lives mechanic: decrement on loss, retry same round.
- T03: Run end conditions: round 5 win → run win screen; 0 lives → run loss screen.
- T04: Pre-round flow per round: starter pick → deal → carry → next pre-round.
- T05: Integration test: full 5-round run scripted to win every round.

Acceptance: a scripted run completes 5 rounds with correct round advancement and life tracking.

### M2-S07: Carry-Forward Selection

Goal: fan-driven carry selection screen.

Tasks:

- T00: Implement Curve C: `fan_to_carry_slots(fan)` function.
- T01: Carry-forward UI: list earned + carried boons, show carry-slot count, pick UI.
- T02: Cap enforcement: 6 max carried+run-scoped. Force drops UI when exceeded.
- T03: Apply selection to `RunState.active_boons_run_scoped`.
- T04: Integration test: round-end with various fan totals → correct carry slot grants.

Acceptance: carry selection works for all curve thresholds, cap is enforced, boons persist correctly into next round.

### M2-S08: Opponent Escalation

Goal: rounds 2-5 opponent packages.

Tasks:

- T00: Implement opponent package data records per `INITIAL-DESIGN.md`.
- T01: AI behavior modulation per package (Pure Suit, Triplet Hunter, etc.). Reuses M1's smart AI heuristic with package-driven priorities.
- T02: Multi-package compatibility (rounds 4-5).
- T03: Declared target hand mechanic (rounds 3, 5).
- T04: Visible package display in pre-round and during deal.
- T05: Tuning playtest: AI Hu rate per round should produce ~50% player-win rate at vanilla skill.

Acceptance: each round's opponents reflect the correct escalation; package effects are visible in AI behavior.

### M2-S09: Run Resolution And Polish

Goal: end-of-run screens and integration polish.

Tasks:

- T00: Run win screen: round-by-round summary, final boon set, total fan.
- T01: Run loss screen: round reached, lives spent, summary.
- T02: Debug UI extensions: show full run state, all active boons, fork history, carry history.
- T03: Save/load via `app/save.tl`: persist run state across game sessions (resume mid-run).
- T04: M2 acceptance playtest: 10 full runs, log issues.

Acceptance: M2 Definition Of Done is met.

---

## Open Follow-Ups

Items deferred from M2 but worth noting:

- **Defensive boon primitives** (e.g., `silence_next_discard`) deferred to M3+. Current library has no direct defensive boons; defensive play is supported through information boons (Sacred Eye, Honor Sanctum, Suit Sentry, Closed Eye, Hidden Path peeks).
- **Larger boon library** beyond 24. Adding boons is data-only once architecture ships; expansion can happen iteratively in M3+ using the principles in the Boon Design Principles section.
- **Cross-cluster synergy boons** (e.g., a boon that fires on combinations of Honor + Concealed events). Possible in M3+ with additional registry tagging or shared trigger events.
- **Boon upgrades / rarity tiers** mentioned in `INITIAL-DESIGN.md`. Not in M2 scope; can be added through `weight` and metadata fields without registry restructure.
- **AI awareness of player boons**. Currently M2 AI is boon-blind. Defensive AI seeing player boons would improve round 4-5 difficulty.
- **Multi-suit dominant tracking** (e.g., a player with 2 strong suits). Suit cluster currently assumes one dominant suit; future expansion could allow multi-suit tracking via Suit Drift extensions.
- **Boon catalog from `INITIAL-DESIGN.md`** (Sculptor, Hunter, Caller, Reader, Gambler, Grinder archetypes) is not subsumed by M2's 3-cluster system. Decision needed: either retire the archetype catalog or migrate selected archetype boons into the cluster system as future-additions in M3+.
- **`INITIAL-DESIGN.md` update**: the Phase 0 boon pool, archetype catalog, and the 8 trigger moments described in that doc are superseded by M2's cluster system, milestone forks, and event-listener architecture. A separate doc-update pass should reconcile `INITIAL-DESIGN.md` with M2's design (preserving the broader game vision while pointing to M2 as canonical for boon design).
- **Active boon UI**: M2 introduces several player-active boons (Cleanse, Suit Bind, token spends). UI specification for invocation buttons, token panels, and player-active prompts is implicit in M2-S03 / M2-S04 but worth treating as its own design pass during implementation.

---

## Appendix: Migration Map From `INITIAL-DESIGN.md` Boons

The 12-boon Phase 0 pool described in `INITIAL-DESIGN.md` is **not** the M2 library. M2 implements a different design. The mapping for reference:

| Original Phase 0 boon | M2 mapping |
|---|---|
| Current (Sculptor T1) | Replaced by Suit cluster (Pure Path + Pure Vision); suit commitment now rewarded through tools, not fan counters |
| Discipline (Hunter T1) | Replaced conceptually by Concealed cluster (Hidden Path + Silent March + Silent Stand + Concealed Insight); concealed commitment rewarded through accumulating tokens and info |
| Still Water (Hunter T1) | Removed — concealed bonus is native HK fan, not boon-modified |
| Dragon's Weight (Caller T1) | Removed — fan-modifying boon eliminated by design pivot |
| Open Eyes (Caller T1) | Subsumed into peek primitive (`peek_wall`) used by Honor's Eye, Suit Beacon, and others |
| Heavy Hand (Caller T2) | Removed — fan-modifying boon eliminated |
| Third Eye (Reader T1) | Subsumed into general peek primitives (Honor Sanctum, Closed Eye, Suit Sentry) |
| Fresh Start (Reader T2) | Removed — opening-modifier mechanic deferred to M3+ |
| Last Gasp (Gambler T1) | Removed — fan-modifying boon eliminated |
| Stolen Thunder (Gambler T1) | Removed — fan-modifying boon eliminated |
| Momentum (Grinder T1) | Removed — opening-modifier mechanic deferred to M3+ |
| Compounding Interest (Grinder T1) | Removed — fan-modifying boon eliminated |

`INITIAL-DESIGN.md` may need updating to reflect that the Phase 0 boon pool design has been superseded. Decision deferred to a separate doc-update task; not in this milestone's scope.
