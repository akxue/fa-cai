# AI Research Notes

Date: 2026-05-05

Purpose: understand open mahjong AI projects broadly, including their own
rulesets and assumptions, then translate the useful ideas into facai's Hong
Kong mahjong roguelike AI. This is a study note, not an implementation plan.

## Facai Baseline

Current facai AI already follows these accepted constraints:

- `ai.decide_main(deal, player_index)` and `ai.decide_reaction(deal, player_index)` are pure decision functions.
- AI returns `DealAction` plus `AiReasoning`; it never mutates `DealState`.
- The engine remains rules-only and knows nothing about AI.
- S06 implemented a target-pattern heuristic: `default`, `dui_dui_hu`, `hun_yi_se`, and `qing_yi_se`.
- The current ranking is target-aware and 3-fan-aware, but it is still a heuristic, not a search or learned policy.

The research question is therefore not "what should replace facai AI now?"
It is "what ideas should shape the next versions?"

## Sources Studied

- clarkwkw/mahjong-ai: https://github.com/clarkwkw/mahjong-ai
- MahjongRepository/tenhou-python-bot: https://github.com/MahjongRepository/tenhou-python-bot
- KiddoZhu/Aleo: https://github.com/KiddoZhu/Aleo
- mjx-project/mjx: https://github.com/mjx-project/mjx
- Equim-chan/Mortal: https://github.com/Equim-chan/Mortal and https://mortal.ekyu.moe/
- Jimboom7/AlphaJong: https://github.com/Jimboom7/AlphaJong
- Tjong paper abstract: https://doi.org/10.1049/cit2.12298
- Microsoft Suphx project page: https://www.microsoft.com/en-us/research/project/suphx-mastering-mahjong-with-deep-reinforcement-learning/

## clarkwkw/mahjong-ai

Ruleset: Hong Kong Mahjong. This is the closest direct reference.

What it contains:

- A `MoveGenerator` interface with separate decisions for Chow, Pong, Kong,
  discard, and win.
- A simple rule-based AI.
- Python and C++ Monte Carlo tree search variants.
- Deep Q and policy-gradient models.
- A benchmark script where named model types play many games against each
  other.
- A tile-state encoder for neural networks.

Important architecture ideas:

- Decision modules are swappable. Human, random, heuristic, MCTS, DQN, and
  policy-gradient players share the same decision surface.
- The rule-based baseline stores a "majority suit" strategy and then evaluates
  each tile by how much it supports that strategy.
- It tracks visible tiles from discards and fixed/open sets, then uses that to
  estimate future availability.
- It estimates opponents' suit tendency from their open sets and discards.
- MCTS is framed around swap-tile futures: choose a discard, sample possible
  future draws, and evaluate the resulting hand.
- The learned models use explicit action filters so illegal actions are masked
  before choosing.

Algorithm lessons:

- A very simple HK baseline can be "choose a suit/shape, keep useful tiles,
  discard the least useful tile."
- Suit commitment can be delayed. The baseline has an exploration parameter
  before it locks into a majority suit.
- Open-call decisions can be strategy-consistent rather than only
  ting-distance-driven.
- MCTS can be introduced as an evaluator behind the same action API without
  replacing the engine.
- Training and inference need legality masks. Letting a model emit impossible
  actions and then repairing them should be treated as a training failure.

Facai translation:

- Already adopted: swappable pure AI entry points and target-pattern strategy.
- Near-term useful: add a lightweight "target stickiness" or "commitment"
  score so AI does not recompute targets too nervously every turn.
- Near-term useful: expose visible-tile accounting per target, not only live
  tile counts. Example: "qing_yi_se is high value, but the dominant suit is
  visibly depleted."
- Later useful: add MCTS as an optional evaluator that ranks the top few
  heuristic actions, not every legal action.
- Later useful: model opponents' likely suit/package target from open sets and
  discards.

Do not copy code directly unless licensing is clarified. The repo did not
include a license file in the inspected checkout.

## tenhou-python-bot

Ruleset: Japanese competitive mahjong. It is archived, MIT licensed, and
highly useful for AI structure even though many rules are not facai rules.

What it contains:

- A full bot decision pipeline for Tenhou.
- `DiscardOption` records with hand distance, waits, improving tile count,
  tile valuation, and danger.
- A hand builder that enumerates candidate discards, calculates waits, counts
  visible/revealed tiles, applies strategy constraints, and then chooses.
- Open-hand strategies for suit-heavy, value-honor, simple-tile, and
  ready-hand goals.
- Defense modules that estimate tile danger against threatening opponents.
- Tests for strategies, defense, Kan, placement, and discard behavior.

Important architecture ideas:

- Every discard candidate is a rich object, not just a tile id.
- Candidate ranking is staged:
  1. generate legal candidates;
  2. compute distance and waits;
  3. mark danger;
  4. apply active strategy constraints;
  5. choose by distance, improving count, secondary value, and safety.
- The bot separates "current hand strategy" from base hand efficiency.
- A call is accepted only if it supports the current strategy and leaves a
  plausible path after the required post-call discard.
- Defense is threat-based. The AI only becomes defensive when opponents are
  threatening enough, then danger can override hand efficiency.
- Decision logging serializes candidate metrics, which makes AI behavior
  inspectable.

Rule-specific concepts worth understanding:

- Japanese-only declarations, discard-lockout safety rules, bonus indicators,
  Japanese hand-pattern names, Japanese point math, and Tenhou placement logic
  are not facai rules.
- The transferable concepts are candidate records, stage ordering, danger
  modeling, strategy gating, and debug serialization.

Facai translation:

- Upgrade `AiReasoning` or inspector details from one chosen action to a short
  ranked candidate list. This would make AI review much easier.
- Represent discard candidates internally as a typed record:
  `tile_id`, `target`, `ting_after`, `ukeire`, `est_fan`, `tile_value`,
  `danger`, `reasons`.
- Add a future `defense` layer after S07/S08: it should be optional and
  threat-triggered, not always-on.
- Add opponent target analyzers for facai packages: Pure Suit, Triplet Hunter,
  Dragon Chaser, Fast Hand. These are the HK/roguelike equivalent of
  hand-pattern analyzers.
- Keep the same staged pipeline, but replace Japanese scoring with Hong Kong
  fan and boon-aware estimates.

## KiddoZhu/Aleo

Ruleset: GuoBiao/Chinese Official Mahjong, not HK. Apache-2.0 licensed.

What it contains:

- C++ core game state.
- A bot interface with `play(Game&) -> Message`.
- A `MaxProbabilityBot` that evaluates legal play, Peng, Chi, Gang, and Hu.
- A simulator for self-play.
- Fan calculator and wait/probability search.
- Python interface for machine learning.

Important architecture ideas:

- The bot does action comparison by temporarily applying each legal call or
  discard, scoring the resulting state, then undoing the temporary state.
- The core evaluation searches waits up to a bounded number of needed tiles.
- It sums weighted probabilities for waits, then chooses the discard with the
  best probability mass.
- Kongs are evaluated by averaging over possible replacement draws.
- The simulator can run bots against each other and save/load histories.

Algorithm lessons:

- A compact probability engine can sit below a simple bot.
- "What is my probability of completing a valid hand within N tiles?" is a
  stronger metric than raw ting distance.
- Action comparison by hypothetical state is powerful, but it needs safe copy
  or rollback discipline.
- Kong decisions deserve special treatment because the replacement draw changes
  expected value.

Facai translation:

- Add a bounded "completion probability" evaluator for top candidates:
  use live counts and target constraints to estimate chance of reaching a 3+
  fan Hu within one or two draws.
- Use this as a second-stage evaluator after the existing heuristic narrows the
  candidate list.
- For Kong decisions, evaluate target-filtered expected value after the
  replacement draw rather than only "does ting regress?"
- The simulator/self-play boundary matches facai's deterministic engine well.

## mjx-project/mjx

Ruleset: Japanese competitive mahjong. MIT licensed.

What it contains:

- A fast simulator intended for Mahjong AI research.
- Mjai-compatible server behavior.
- Exact Tenhou compatibility validated against logs.
- Gym-like API:
  `env.reset()`, legal actions from observations, `env.step(actions)`,
  `env.rewards()`.
- gRPC serving for distributed evaluation and batched inference.
- Visualization and examples.

Important architecture ideas:

- The environment exposes observations and legal actions; agents are separate.
- Batched `act_batch` exists because neural inference is more efficient in
  batches than one decision at a time.
- Evaluation can run many games in parallel against remote agents.
- API stability matters; the repo explicitly warns that APIs may change before
  v1.0.

Facai translation:

- Build a headless evaluation harness before any ML work. It should run N
  seeded deals and record win rate, wall exhaustion rate, average turns, target
  distribution, and invalid-action count.
- Keep an observation/action boundary even for heuristic AI. That makes future
  ML and remote evaluation easier.
- If we ever train models, support batched evaluation of many deal states.
- Do not bind facai to mjx. The ruleset and API do not match.

## Equim-chan/Mortal

Ruleset: Japanese competitive mahjong. AGPL-3.0-or-later licensed.

What it contains:

- A strong open-source Japanese-mahjong AI powered by deep reinforcement
  learning.
- Rust mahjong emulator with Python interface.
- mjai interface.
- Backend use for log review tooling.
- Documentation that describes training, observation/action representations,
  environment/reward design, inference, and a Rust rules/simulation layer.

Important architecture ideas:

- Strong AI depends on simulator speed as much as model architecture.
- Model-facing observations/actions deserve a stable schema.
- Log review is a first-class product surface: the same AI can play, evaluate,
  and explain past choices.
- A separate mahjong essentials library lets multiple tools share the same
  validated rules implementation.

Facai translation:

- Long-term, facai should treat AI as both an opponent and a reviewer. A
  debug/replay screen could show "AI preferred X because target Y, fan Z,
  ukeire N, danger D."
- If ML becomes relevant, define observation/action schema before training.
- Do not copy code from Mortal into facai. The license is AGPL and the ruleset
  is Japanese competitive mahjong.
- The useful lesson is engineering shape: fast engine, stable schema, replay
  reviewer, separated model interface.

## Jimboom7/AlphaJong

Ruleset: Japanese Mahjong Soul, with 3-player and 4-player support.
GPL-3.0 licensed.

What it contains:

- Browser userscript bot.
- No machine learning; conventional algorithms.
- Offensive evaluation that simulates possible future draws.
- Defensive evaluation that estimates deal-in danger.
- Configurable parameters for performance, efficiency, safety, calling, Kan,
  and strategy.
- Help mode that recommends actions without playing automatically.

Important architecture ideas:

- It simulates each possible discard, then approximates the next two turns.
- Runtime is controlled by performance modes. Lower modes prune more future
  combinations.
- Tile priority combines efficiency, expected hand score, and danger.
- Defense estimates each tile's danger per opponent, then weights by expected
  deal-in value.
- Call acceptance is multi-factor: distance improvement, value loss/gain, bad
  wait improvement, dealer position, wall timing, and danger.
- It has explicit personality knobs: safety, efficiency, call appetite, Kan
  appetite, and special-hand thresholds.

Rule-specific concepts worth understanding:

- Japanese-only declarations, discard-lockout safety rules, bonus indicators,
  Japanese point math, Japanese hand-pattern names, and Mahjong Soul automation
  details do not carry over directly.
- The transferable concept is a tunable, inspectable utility function.

Facai translation:

- Add AI personality knobs beyond target weights:
  `speed_bias`, `value_bias`, `safety_bias`, `call_appetite`, `kong_appetite`,
  `stickiness`.
- Add a time-budgeted evaluator. In normal play it can use the fast heuristic;
  in debug or simulation it can run deeper future search.
- The current facai formula can evolve from lexicographic ranking into a
  weighted utility:
  `utility = speed_value + fan_value + target_value + ukeire_value -
  danger_value + boon_synergy_value`.
- Help/recommendation mode is a useful future player-facing feature: the same
  evaluator can drive AI opponents and optional coaching.

## Tjong

Ruleset: Chinese Standard Mahjong/Botzone-oriented research, based on the
paper abstract.

What it contributes conceptually:

- Hierarchical decision-making: split "which action type?" from "which tile?"
- Transformer/self-attention state processing.
- "Fan backward" reward assignment: winning hand fan is propagated backward to
  earlier actions to reduce sparse-reward problems.
- Reported supervised learning plus reinforcement learning pipeline.

Facai translation:

- Even without ML, use hierarchical decisions:
  1. Can/should Hu?
  2. Can/should Kong?
  3. Should call?
  4. Which target?
  5. Which discard?
- For future training data, label decisions with final fan/rating and target
  outcome. This is a roguelike-friendly version of fan-backward learning.
- If we train later, separate action-head and tile-head models would reduce
  complexity compared with one flat action space.

## Suphx

Ruleset: Japanese Tenhou research.

What it contributes conceptually:

- Deep reinforcement learning for multiplayer imperfect-information Mahjong.
- Global reward prediction.
- Oracle guiding.
- Runtime policy adaptation.

Facai translation:

- "Global reward prediction" maps to estimating deal/run outcome, not only
  immediate Hu chance.
- "Oracle guiding" maps to using hidden-perfect-information analysis during
  offline training/evaluation only, never during live AI play.
- "Runtime policy adaptation" maps cleanly to facai opponent packages and boon
  stacks: the same base evaluator can shift weights based on current run state.

## Cross-Project Patterns

The same ideas repeat across very different projects:

- Legal action masks are mandatory.
- Candidate actions need structured metrics.
- Hand distance alone is too weak.
- Improving tile count matters, but it is not enough.
- Strategy/target selection should constrain candidate choices.
- Calls must be evaluated with the forced post-call discard included.
- Kongs deserve a replacement-draw expectation, not a normal-call check.
- Visible tile accounting is foundational.
- Opponent modeling starts with open sets and discards.
- Defense should be threat-triggered and weighted by opponent hand value.
- Strong AI needs repeatable simulation, not just clever per-turn logic.
- Good AI work needs logs, replay, and candidate explanations.
- ML systems need stable observation/action schemas before training.

## Recommended Facai AI Roadmap

### Now: Make The Current Heuristic Easier To Study

No gameplay behavior change required.

- Add a debug-only candidate list for the chosen AI action.
- Log top 3 discard candidates with target, ting, ukeire, est_fan, tile value,
  and rejection reasons.
- Record per-seed AI summaries: target changes, calls accepted/rejected, wall
  exhaustion reason.

### Next: Improve Heuristic Quality

- Add target stickiness so AIs commit more believably.
- Add visible depletion penalties for suit and triplet targets.
- Add richer personalities:
  `speed_bias`, `value_bias`, `call_appetite`, `kong_appetite`,
  `safety_bias`, `stickiness`.
- Change call logic to evaluate the post-call discard candidate, not just the
  immediate called shape.
- Add Kong replacement-draw expectation.

### Later: Add Defense

- Track opponent target likelihoods from open sets and discards.
- Estimate danger for each discard from:
  opponent target likelihood,
  opponent open hand value,
  visible tile counts,
  whether the tile helps a likely suit/triplet/dragon path,
  late-wall pressure.
- Gate defense by threat level so early M1-style play stays fast and readable.

### Later: Add Search

- Implement a bounded evaluator that samples or enumerates one to two future
  draws for the top heuristic candidates.
- Use the deterministic engine or pure hand evaluators; no hidden information
  cheating in live play.
- Start with discard only, then call/Kong search.
- Track performance budget in milliseconds or candidate count.

### Long-Term: Add Learning

- First create a headless evaluation harness and replay dataset.
- Define an observation schema independent of UI.
- Define legal action masks.
- Train on self-play or heuristic-generated labels only after the simulator is
  stable.
- Use final fan/rating/round outcome as backward labels for earlier decisions.
- Keep models optional; facai should remain playable with heuristic AI.

## Concrete Design Takeaways For facai

Most useful immediate shape:

```text
CandidateAction
  action: DealAction
  target: TargetKind
  ting_after: integer
  ukeire: integer
  est_fan: integer
  tile_value: number
  visible_depletion: number
  danger: number
  utility: number
  rejection_reason: string
```

Most useful future decision pipeline:

```text
observe visible state
generate legal actions through game rules
score immediate Hu
choose or maintain target
build candidate records
reject impossible / sub-3-fan / illegal paths
apply call and Kong special evaluators
apply optional defense if threats are high
rank by personality-weighted utility
return DealAction + AiReasoning
log candidate summary for debug/replay
```

Most useful personality record:

```text
AiPersonality
  target_weights
  speed_bias
  value_bias
  safety_bias
  call_appetite
  kong_appetite
  target_stickiness
  risk_tolerance
```

## Licensing Notes

- clarkwkw/mahjong-ai: no license file found in inspected checkout; study
  concepts only.
- tenhou-python-bot: MIT; permissive, but rules are Japanese-specific.
- Aleo: Apache-2.0; permissive, but rules are GuoBiao/Chinese Official.
- mjx: MIT; permissive, but rules are Japanese-specific and API is unstable.
- Mortal: AGPL-3.0-or-later; do not copy code into facai.
- AlphaJong: GPL-3.0; do not copy code into facai unless facai licensing is
  intentionally made GPL-compatible.

## Bottom Line

The best near-term AI for facai is still an inspectable heuristic, not ML. The
best version of that heuristic should borrow the shape of mature bots:
candidate records, strategy constraints, visible-tile probabilities, post-call
simulation, threat-triggered defense, and clear logs.

The best long-term path is not to jump straight to a model. It is:

1. make the heuristic candidate pipeline explicit;
2. build headless seeded evaluation;
3. add bounded search for top candidates;
4. add opponent/package modeling;
5. only then define ML observation/action schemas and train.
