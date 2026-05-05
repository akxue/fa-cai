# S07 Pre-Rebuild Baseline

This is the baseline row each S07 commit's `make playtest` output is compared against. The current AI is the S06 smart-AI heuristic kernel as merged at commit `8a1766b` on `main`. See `docs/MILESTONE-1-PLAN.md` (slice S07) for the rebuild plan and `scripts/playtest.lua` for the harness.

## Recorded

- Date: 2026-05-04
- Commit: `8a1766b` (S06 merge tip on `main`)
- Command: `make playtest`
- Seeds: `42, 1, 100, 12345, 7, 99, 200, 555, 2025, 31415`

## Per-seed outcomes

| seed   | steps | outcome           | calls (peng/chi/openK/concK/addK) | invalid | winner target  | fan | hand pattern   |
|-------:|------:|-------------------|-----------------------------------|--------:|----------------|----:|----------------|
|     42 |   218 | Hu by p4          | 6 / 1 / 0 / 0 / 0                 |       0 | dui_dui_hu     |   3 | Dui Dui Hu     |
|      1 |   453 | wall exhaustion   | 9 / 0 / 4 / 0 / 0                 |       0 | —              |   — | —              |
|    100 |   330 | Hu by p1          | 5 / 0 / 0 / 0 / 0                 |       0 | dui_dui_hu     |   4 | Dui Dui Hu     |
|  12345 |   247 | Hu by p1          | 7 / 0 / 1 / 0 / 0                 |       0 | dui_dui_hu     |   3 | Dui Dui Hu     |
|      7 |   421 | Hu by p2          | 6 / 1 / 1 / 0 / 1                 |       0 | dui_dui_hu     |   4 | Dui Dui Hu     |
|     99 |   285 | Hu by p2          | 7 / 2 / 1 / 0 / 1                 |       0 | dui_dui_hu     |   3 | Dui Dui Hu     |
|    200 |   245 | Hu by p4          | 3 / 1 / 0 / 0 / 1                 |       0 | dui_dui_hu     |   4 | Dui Dui Hu     |
|    555 |   351 | Hu by p4          | 6 / 1 / 3 / 1 / 1                 |       0 | dui_dui_hu     |   4 | Dui Dui Hu     |
|   2025 |   453 | wall exhaustion   | 8 / 0 / 0 / 0 / 0                 |       0 | —              |   — | —              |
|  31415 |   444 | wall exhaustion   | 7 / 0 / 1 / 1 / 0                 |       0 | —              |   — | —              |

## Aggregates

- Hu rate:          **7 / 10 (70%)**
- Wall exhaustion:  3 / 10 (30%)
- Stuck/error:      0 / 10 (0%)
- avg steps/deal:   344.7
- invalid actions:  0 total
- call mix:         peng=64, chi=6, open_kong=11, concealed_kong=2, added_kong=4
- target dist:      `dui_dui_hu = 7`  (every Hu was Dui Dui Hu)
- pattern dist:     `Dui Dui Hu = 7`

## Notes

- The S06 plan's completion summary cites 6/10 Hu. The actual merged tip is 7/10 because the user's PR-review fixes (compute_features suit-count ordering, count_realized_modifiers wind stacking, known-wall draw propagation across all seats) moved seed 12345 from wall exhaustion to a Hu. The 7/10 figure is the row the rebuild must match or beat.
- Every Hu is Dui Dui Hu. No Ping Hu, no Hun Yi Se, no Qing Yi Se. This is the kernel-architecture problem the candidate-pipeline rebuild is intended to address: the heuristic's `target_fitness` / `discard_priority` shape collapses to triplet-racing in nearly every situation. Fan-grounded `Σ P_reach × fan` should distribute target choice more naturally.
- 3 walls + 0 stuck means the engine is stable at this AI level; the rebuild's failure modes should be a regression in Hu rate, not crashes or stuck phases.
- Call mix is heavily peng-skewed (64 peng vs 6 chi). The post-call-best-candidate gate (T16/T17) should re-shape this: chis that break a forming run should drop, but legitimate sequence-target chis may rise.
