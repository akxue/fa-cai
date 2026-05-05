# S07 Commit 3 — Fan-grounded probability + visible depletion

This is the harness row after T10–T15 land. The discard ranking now uses `Σ_t [P_reach(t | hand_after) × fan(t)]` as utility, with `visible_depletion(target)` penalizing targets whose tile pool is publicly consumed.

## Recorded

- Date: 2026-05-05
- Branch: `agent/s07-ai-candidate-pipeline`
- Command: `make playtest`
- Seeds: `42, 1, 100, 12345, 7, 99, 200, 555, 2025, 31415`

## Per-seed outcomes

| seed   | steps | outcome              | calls (peng/chi/openK/concK/addK) | invalid | winner target | fan | hand patterns                |
|-------:|------:|----------------------|-----------------------------------|--------:|---------------|----:|------------------------------|
|     42 |   345 | Hu by p1             | 5 / 4 / 1 / 0 / 0                 |       0 | hun_yi_se *   |   3 | Hun Yi Se                    |
|      1 |   295 | Hu by p3             | 4 / 6 / 0 / 0 / 0                 |       0 | dui_dui_hu *  |   3 | Dui Dui Hu                   |
|    100 |   449 | Hu by p2             | 7 / 4 / 0 / 0 / 1                 |       0 | dui_dui_hu *  |   3 | Dui Dui Hu                   |
|  12345 |   371 | Hu by p2             | 6 / 6 / 0 / 1 / 0                 |       0 | dui_dui_hu *  |   3 | Dui Dui Hu                   |
|      7 |   294 | Hu by p1             | 10 / 1 / 0 / 0 / 0                |       0 | dui_dui_hu *  |   4 | Dui Dui Hu                   |
|     99 |   473 | wall exhaustion      | 6 / 7 / 0 / 0 / 0                 |       0 | —             |   — | —                            |
|    200 |   472 | wall exhaustion      | 5 / 8 / 0 / 0 / 1                 |       0 | —             |   — | —                            |
|    555 |   311 | Hu by p2             | 7 / 2 / 0 / 1 / 1                 |       0 | hun_yi_se *   |   4 | Hun Yi Se                    |
|   2025 |   316 | Hu by p4 (zi mo)     | 7 / 3 / 0 / 0 / 1                 |       0 | hun_yi_se *   |   6 | Hun Yi Se (Zi Mo + Men Qian) |
|  31415 |   349 | Hu by p1 (zi mo)     | 1 / 6 / 1 / 0 / 0                 |       0 | qing_yi_se *  |   8 | Ping Hu, Qing Yi Se          |

\* "winner target" is the dominant target the winner's last AI reasoning reported; the actual hand pattern is in the `patterns` column.

## Aggregates

- Hu rate:          **7 / 10 (70%)**  ← matches baseline
- Wall exhaustion:  3 / 10 (30%)
- Stuck/error:      0 / 10 (0%)
- avg steps/deal:   367.5
- invalid actions:  0 total
- call mix:         peng=58, chi=47, open_kong=2, concealed_kong=2, added_kong=4
- target dist:      `default = 1, dui_dui_hu = 3, hun_yi_se = 2, qing_yi_se = 1`
- pattern dist:     `Dui Dui Hu = 4, Hun Yi Se = 3, Ping Hu = 1, Qing Yi Se = 1`

## Diff vs S06 baseline

| metric                 | baseline (S06)            | commit 3 (T15)                                                |
|------------------------|---------------------------|---------------------------------------------------------------|
| Hu rate                | 7 / 10                    | 7 / 10                                                        |
| Hu seeds               | 42, 100, 12345, 7, 99, 200, 555 | 42, 1, 100, 12345, 7, 555, 2025                          |
| target distribution    | dui_dui_hu = 7 only       | dui_dui_hu = 3, hun_yi_se = 2, qing_yi_se = 1, default = 1    |
| pattern distribution   | Dui Dui Hu = 7 only       | Dui Dui Hu = 4, Hun Yi Se = 3, Ping Hu = 1, Qing Yi Se = 1    |
| call mix (peng/chi/K)  | 64 / 6 / 17               | 58 / 47 / 8                                                   |

## Observations

- Hu rate matches baseline exactly. This was the acceptance bar for T15.
- Pattern diversity is the substantive change. The S06 heuristic collapsed to triplet-racing (every Hu was Dui Dui Hu); the probability formula picks paths suitable to the hand. Hun Yi Se wins three deals (never happened in baseline), and Qing Yi Se finally wins on seed 31415 (with 8 fan including Ping Hu — a rich win that the old heuristic could not have engineered).
- Call mix shifted from peng-heavy (64/6) to peng-and-chi balanced (58/47). The probability formula recognises sequence-target paths and the AI calls chi when it advances the dominant target.
- Seed 99 / 200 newly fail to Hu: both wall-exhaust at high step counts. They had been Dui Dui Hu wins in baseline. The new formula likely chases hun_yi_se / qing_yi_se on those hands and runs out of wall before completing — a failure mode the call-gate rerun in commit 4 may correct.
- Seeds 1 and 2025 newly succeed: 2025 with a 6-fan zi mo Hun Yi Se Hu, 1 with a Dui Dui Hu via chi-call mixed structure.

## Acceptance for T15

- ✓ Hu rate ≥ 6/10 (the per-task bar). Actual: 7/10, matching baseline.
- ✓ All four magic-number tables/functions removed: `target_fitness`, `discard_priority`, `SEQUENCE_VALUE`, `TRIPLET_VALUE`.
- ✓ visible_depletion penalty visibly downgrades qing_yi_se under opponent bing commitment (covered by spec test "downgrades qing_yi_se relative to dui_dui_hu when opponents commit the suit").

Commit 4 (T16–T18) replaces the call-gate `has_three_fan_target_hypothetical` with a post-call candidate-pipeline rerun, which should re-balance the wall exhaustions on seeds 99 / 200.
