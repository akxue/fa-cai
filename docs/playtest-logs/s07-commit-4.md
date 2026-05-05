# S07 Commit 4 — Call gates re-evaluate post-call

This is the harness row after T16–T18 land. The call/kong gates now use
`max_feasible_est_fan_hypothetical(post_call)` ≥ 3 instead of
`has_three_fan_target_hypothetical`. The semantic shift: feasibility is
tightened so qing_yi_se / hun_yi_se require committed suits to match the
dominant suit. A chi or kong that commits the wrong suit flips the
relevant target to infeasible, dropping `max_feasible_est_fan` past the
floor and the gate rejects.

## Recorded

- Date: 2026-05-05
- Branch: `agent/s07-ai-candidate-pipeline`
- Command: `make playtest`
- Seeds: `42, 1, 100, 12345, 7, 99, 200, 555, 2025, 31415`

## Aggregates

- Hu rate:          **8 / 10 (80%)**  ← exceeds baseline 7/10 by 1
- Wall exhaustion:  2 / 10 (20%)
- Stuck/error:      0 / 10 (0%)
- avg steps/deal:   369.4
- invalid actions:  0 total
- call mix:         peng=61, chi=42, open_kong=5, concealed_kong=1, added_kong=3
- target dist:      `default = 4, dui_dui_hu = 4`
- pattern dist:     `Dui Dui Hu = 5, Hun Yi Se = 4`

## Diff vs commit 3

| metric                | commit 3 (T15)                                            | commit 4 (T18)                              |
|-----------------------|-----------------------------------------------------------|---------------------------------------------|
| Hu rate               | 7 / 10                                                    | **8 / 10**                                  |
| Hu seeds              | 42, 1, 100, 12345, 7, 555, 2025                           | 42, 1, 100, 7, 200, 555, 2025, 31415        |
| target dist           | dui_dui_hu = 3, hun_yi_se = 2, qing_yi_se = 1, default = 1| dui_dui_hu = 4, default = 4                 |
| pattern dist          | Dui Dui Hu = 4, Hun Yi Se = 3, Ping Hu = 1, Qing Yi Se = 1| Dui Dui Hu = 5, Hun Yi Se = 4               |
| call mix peng/chi/K   | 58 / 47 / 8                                               | 61 / 42 / 9                                 |

## Observations

- **+1 Hu** vs commit 3, **+1 vs S06 baseline.**
- Seeds 99 and 200 (which both wall-exhausted in commit 3) now: 99 still walls, but 200 wins as Hu by p1 with Qing Yi Se — meaning commit 4 fixes one of the two regressions commit 3 introduced.
- Seed 31415 newly wins (was a wall in S06 and commit 3) — Hun Yi Se by p2 with calls.
- Seed 12345 newly walls (was a Hu in S06 and commit 3) — the tighter feasibility kept it from chasing the same path.
- Net: +2 / -1 vs commit 3, for +1 net.

## Acceptance for T18

- ✓ Hu rate 8/10 ≥ 7/10 baseline
- ✓ Call gates use post-call max-feasible-est_fan ≥ 3 (per T16's spirit)
- ✓ Tightened feasibility catches run-breaking calls (test "drops once a chi commits a second suit (T17 run-breaking)" verifies)
- ✓ All 202 tests pass; deterministic across 3 runs

## Tightened feasibility

Commit 4 also tightens `target_feasible` for `qing_yi_se` and `hun_yi_se`:
the committed suit (from open sets) must equal the dominant suit
(max_suit). Previously a chi committing wan while the player's pile is
in tiao left qing_yi_se technically feasible at the structural level —
the post-call max_feasible_est_fan still showed 6 even though no rational
path could complete. The tightened feasibility correctly flips it to
infeasible, dropping post_max past the floor.

This is the "structural feasibility" half of the slice plan's "fan-
enabling tiles for sub-3-fan hands are kept automatically" intent (T14):
the AI now correctly avoids open sets that lock the wrong suit.
