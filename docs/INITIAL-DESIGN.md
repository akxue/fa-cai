# facai (發財) — Game Design Document v4.1

> Last updated: May 2026. Share-ready pass. This document describes the intended game, the broader Phase 0 prototype target, and the current design assumptions. Milestone-specific build scope lives in separate milestone plans.

---

## Short Pitch

**Accumulate boons that bend the rules of a single mahjong hand in your favor, land a valid Hu before your opponents do.**

facai is a solo roguelike mahjong game about building a strange, powerful tournament run out of small rule-bending advantages. The player is not choosing a class or forcing a legendary hand from the start. Instead, each run begins with one boon, then evolves hand by hand as the player wins rounds, adds new boons, and discovers what kind of mahjong engine they have accidentally built.

The fantasy is: **I know mahjong, but this run lets me play mahjong in a way I have never played before.**

For players who do not already know mahjong, facai should still be readable as a tile-based race: make a valid hand before three opponents do, then use boons to make future hands easier, stranger, or more valuable.

---

## Design Goals

- Preserve the tension and table-reading of real mahjong
- Make each run feel like a distinct roguelike build
- Keep the first playable version small enough to validate quickly
- Teach through visible pressure, clear rewards, and repeatable hands rather than long rules explanations
- Let expert players chase elegant, high-rated, or legendary hands without making beginners understand the full scoring system upfront

---

## Target Audience

facai is for roguelike-literate players and curious newcomers first, with enough mahjong authenticity to remain interesting to people who already know the game. The first version should assume the player can learn by doing, but should not assume they already understand Hong Kong scoring, fan thresholds, or every named hand.

The game should expose enough information to make decisions feel fair: visible opponent plans, clear boon triggers, explicit hand ratings, and UI counters for anything the player would otherwise have to track mentally.

---

## End Vision

The long-term version of facai is a compact, highly replayable roguelike built on mahjong fundamentals. A full run should eventually support a larger boon pool, stronger opponent identities, rarer build-defining effects, mastery ratings, unlocks, and possibly later layers such as classes, relics, boss auras, overworld routing, or co-op.

Those layers are intentionally deferred. The broader Phase 0 target is not "all of roguelike mahjong." The first implementation milestone is even smaller: prove that **racing three opponents to a 3+ fan Hu, with one starter boon and a readable reward beat, is fun enough to keep building.**

---

## Phase 0 Prototype

Phase 0 is the broader prototype target that can validate the core promise across a complete five-round tournament.

Solo player. Standard 136-tile Wall. Full HK mahjong rules (Chi, Peng, Gang, Hu, Zi Mo). Minimum 3 fan required to Hu for every player. Five tournament rounds. Three lives. Gate-style structure: losing a hand costs 1 life and retries the same round; winning a hand advances to the next round. Choose 1 starter boon from a curated entry set before Round 1, then choose a boon from the full Phase 0 pool after clearing Rounds 1-4 (3 options; 4 on Zi Mo win). Three AI opponents play vanilla mahjong in Round 1, then escalate through visible scripted packages and declared targets. Scoring is presented as C/B/A/S/SS/Legend ratings instead of point totals. No art. No classes. No overworld. No co-op.

**The single question Phase 0 answers:** Is racing three opponents to Hu, under the minimum fan rule, with an accumulating boon stack, fun enough to keep playing?

### Milestone 1 Slice

Milestone 1 is the first playable build slice of Phase 0, not the whole Phase 0 prototype. It implements Round 1 only: choose 1 starter boon from 3 curated offers, play against 3 vanilla AI opponents, win the deal to see a reward screen, or lose 1 life and retry Round 1. Round 2+, the full 12-boon reward pool, and scripted opponent packages are Phase 0 follow-up work after the first slice is playable.

---

## The Core Loop

Choose a starter boon → sit down → play a mahjong match against 3 AI opponents → win the round and advance, or lose a life and retry → choose a boon after clearing Rounds 1-4 → win Round 5 before your lives run out.

This is the atom. Every other mechanic must serve this loop or get cut. The legendary hand you land is not chosen upfront -- it emerges from which boons you have accumulated. The boons are the identity of the run, not the hand you are targeting.

---

## The Tournament Structure

The run is a five-round mahjong tournament. You sit at a table with three AI opponents and race them to Hu. You start with **3 lives**. Fail to win a hand and you lose 1 life, then retry the same tournament round. Clear Round 5 to win the tournament. Hit 0 lives and the run ends.

Before Round 1, you choose **1 starter boon** from 3 options. This gives the run an identity immediately while keeping the minimum fan threshold fixed at 3 from the first hand.

### How a Hand Ends

A hand ends the moment any player Hus with a valid hand, or the Wall exhausts. Exactly like real mahjong. The tournament round only advances when you win the hand.

- **You Hu at or above the minimum fan:** you win the round and advance
- **You Hu by Zi Mo:** you win the round and, if a boon reward follows, get an additional boon option on the post-round reward screen (4 choices instead of 3)
- **An opponent Hus before you:** hand ends immediately. Lose 1 life and retry the same round
- **You Hu below the minimum fan:** hand does not count, round continues
- **Wall exhausts with no valid Hu:** lose 1 life and retry the same round
- **Hit 0 lives:** run over

### Boons Only Come From Winning

You choose a starter boon before Round 1, then choose another boon after clearing Rounds 1-4. Clearing Round 5 ends the tournament, so no post-round boon is needed. Losing hands give you nothing. This makes winning meaningful and losing genuinely costly -- not just a lost life but a missed chance to build momentum.

### How Difficulty Escalates

The minimum fan threshold stays **fixed** throughout the run at 3 fan for every player. Difficulty comes from stronger opponents each round -- faster strategies, visible boon packages, and declared targets.

Opponent packages are defined in **Phase 0 Opponent Packages**. They are simpler than player boons so the table creates readable pressure without feeling like four fully complex roguelike builds at once.

| Round | Opponent Strength |
|---|---|
| 1 | Vanilla. No boons. |
| 2 | One visible package each. |
| 3 | One visible package each; one declared target hand. |
| 4 | Two compatible visible packages each. |
| 5 | Two compatible visible packages each; one declared legendary target. |

---

## Core Terms

This document uses standard mahjong terms, but the game should teach them in context.

| Term | Meaning in facai |
|---|---|
| Hu | A legal winning hand |
| Fan | The scoring value that determines whether a hand is valid and how highly it rates |
| 3 fan minimum | Every Hu must be worth at least 3 fan to count |
| Zi Mo | Winning by self-draw |
| Men Qian | A fully concealed hand with no open melds |
| Wall | The legal 136-tile mahjong tile stack |
| Boon | A run upgrade that bends scoring, information, or timing in the player's favor |
| Limit hand | A rare named hand that receives the Legend rating |

---

## Scoring and Rating System

facai uses real Hong Kong mahjong fan logic for hand validation and mastery expression. Fan (番) accumulate from hand patterns plus modifiers. **Minimum 3 fan required to declare a valid Hu for every player.**

Phase 0 abstracts away point conversion and presents hand quality as a rating. This lets newcomers understand progress immediately while preserving fan as the underlying expert system.

### Fan-to-Rating Conversion

| Result | Rating |
|---|---|
| 3 fan | C |
| 4-5 fan | B |
| 6-7 fan | A |
| 8-9 fan | S |
| 10+ fan | SS |
| Limit hand | Legend |

Limit hands are treated as a special category, not as a large fan number. A Limit hand always awards the **Legend** rating regardless of additive fan modifiers.

### Hand Patterns

| Pattern | Fan | Description |
|---|---|---|
| Ping Hu (平胡) | 1 | Four sequences + pair, suit tiles only |
| Dui Dui Hu (對對胡) | 3 | Four triplets or quads + pair |
| Qi Dui (七對) | 4 | Seven pairs |
| Xiao San Yuan (小三元) | 4 | Two dragon triplets + dragon pair |
| Hun Yi Se (混一色) | 3 | One suit + honor tiles |
| Qing Yi Se (清一色) | 6 | One suit only, no honors |
| Xiao Si Xi (小四喜) | 6 | Three wind triplets + wind pair |
| Zi Yi Se (字一色) | Limit | All honor tiles |
| Da San Yuan (大三元) | Limit | All three dragon triplets |
| Da Si Xi (大四喜) | Limit | All four wind triplets |
| Jiu Lian Bao Deng (九蓮寶燈) | Limit | Nine Gates: 1-1-1-2-3-4-5-6-7-8-9-9-9 in one suit |
| Shi San Yao (十三么) | Limit | Thirteen Orphans: one of each terminal and honor + one duplicate |
| Si Gang (四槓) | Limit | Four kongs + pair |

### Modifiers (stack on top of hand pattern)

| Modifier | +Fan | Condition |
|---|---|---|
| Zi Mo (自摸) | +1 | Win by self-draw |
| Men Qian (門清) | +1 | Fully concealed hand, no open melds |
| Dragon Pung | +1 each | Triplet or quad of any Dragon tile |
| Seat Wind Pung | +1 | Triplet or quad of your seat wind |
| Round Wind Pung | +1 | Triplet or quad of the round wind |
| Hai Di (海底撈月) | +1 | Win on the very last Wall tile |
| Gang Shang (槓上開花) | +1 | Win on supplement tile after a Kong |
| Qiang Gang (搶槓) | +1 | Rob an opponent's declared Kong to win |

### The Minimum Fan Rule in Practice

3 fan is the floor. A bare Ping Hu is only 1 fan -- not enough on its own. To clear minimum with Ping Hu you need two modifiers (e.g. Zi Mo + Men Qian). This means even the simplest hands require deliberate construction. Boons exist to push you above this floor and eventually let normal hands compete with legendary ones on rating.

Ratings are aspirational in Phase 0. They do not improve boon rarity or reward quality yet, because that would make strong runs snowball harder. Later versions may let high-rated wins add softer reward expression, such as extra boon choices, rerolls, upgrades, achievements, or cosmetics.

---

## The Boon System

### Core Principles

- You start each run with 1 starter boon chosen before Round 1
- Boons are offered after clearing Rounds 1-4 (3 choices; 4 if you won by Zi Mo)
- Maximum 5 active boons across a run (starter boon plus four earned boons before Round 5)
- Boons never modify the tile distribution -- the Wall is always a legal 136-tile set
- Boons affect you only (opponent-affecting boons deferred to later design)
- Boons can be passive (fire automatically on trigger) or active (consciously triggered once per hand)
- Fan modifications are additive in Phase 0; multiplicative effects are deferred until the base economy is stable
- Rule exceptions are allowed only when they bend a rule at a cost, not eliminate it entirely
- Archetypes are a design tool only -- not communicated to the player

### The Eight Trigger Moments

Every boon fires on one of these moments inside a single hand:

1. **Opening** -- your starting 13 tiles
2. **Each draw** from the Wall
3. **Each discard** you make
4. **Calling** Chi, Peng, or Kong
5. **Passing** on a legal call
6. **Reaching tenpai** (one tile from Hu)
7. **Winning by Zi Mo**
8. **Winning by discard, last tile, or robbing a Kong**

### Memory Types

- **Within-hand counter:** builds during the hand, pays out on Hu. Displayed in the UI so the player never has to track it mentally.
- **Tournament memory:** remembers how many rounds you have won so far. Displayed on the boon card.

---

## Phase 0 Boon Pool

Phase 0 starts with 12 player boons. This is intentionally small enough to test the core loop and build identity without overwhelming newcomers.

| Archetype | Boons |
|---|---|
| Sculptor | Current |
| Hunter | Discipline, Still Water |
| Caller | Dragon's Weight, Open Eyes, Heavy Hand |
| Reader | Third Eye, Fresh Start |
| Gambler | Last Gasp, Stolen Thunder |
| Grinder | Momentum, Compounding Interest |

This covers all 6 archetypes, but not evenly. Caller is the most represented because open-meld play is easy for newcomers to understand and creates visible table interaction. Sculptor and Gambler are intentionally thin in Phase 0 because their more extreme effects are more likely to distort the hand economy.

The full boon set below includes future candidates and higher-risk effects. It is a design catalog, not the Phase 0 implementation list.

### Starter Boon Set

The starter boon is chosen from a curated entry set, not the full Phase 0 pool. Starter boons should be immediately understandable, broadly useful, and strong enough to suggest a playstyle before the player knows the whole boon system.

| Starter Boon | Why it belongs in the entry set |
|---|---|
| Current | Points the player toward suit concentration without forcing a declaration |
| Still Water | Makes concealed play legible and rewarding |
| Dragon's Weight | Makes honor tiles and Dragon Pengs exciting immediately |
| Open Eyes | Encourages calling while teaching that information is a reward |
| Third Eye | Gives a clear information advantage from the first hand |
| Fresh Start | Lets newcomers repair a confusing opening hand |
| Momentum | Teaches that the tournament itself can become part of the build |

These Phase 0 boons are excluded from starter offers:

| Excluded Boon | Reason |
|---|---|
| Discipline | Requires understanding the value of passing legal calls |
| Heavy Hand | Too narrow without supporting Peng incentives |
| Last Gasp | Mostly relevant near the end of a hand |
| Stolen Thunder | Too rare and reactive for a first impression |
| Compounding Interest | Does nothing until after the player has won a round |

In the full Phase 0 prototype, boon rewards after Round 1 draw from the full 12-boon Phase 0 pool. Milestone 1 may reuse the curated starter set for its single reward screen because Round 2+ is outside that first build slice.

---

## Phase 0 Opponent Packages

Opponents do not draw from the player boon pool in Phase 0. Instead, each opponent uses visible scripted packages that communicate intent. These packages are mostly AI priorities, not player-style rule exceptions.

| Package | Visible Intent | AI Behavior |
|---|---|---|
| Pure Suit | Building one suit | Prefers one suit, discards off-suit and honor tiles earlier |
| Triplet Hunter | Building Peng / Dui Dui Hu | Calls Peng more aggressively and values pairs highly |
| Dragon Chaser | Building dragon value | Holds Dragons longer and calls Dragon Peng aggressively |
| Concealed Hand | Avoiding open melds | Rarely calls and values Men Qian / Zi Mo routes |
| Fast Hand | Racing to 3 fan | Prioritizes the quickest valid 3 fan path over high ratings |
| Legend Chaser | Declared rare target | Slower but dangerous; appears mainly in Round 5 |

Opponent packages should be displayed before the hand starts and remain inspectable during play. The player should be able to make simple defensive reads, such as "this opponent is chasing Dragons, so Dragon discards are dangerous."

### Opponent Escalation

| Round | Opponent Setup |
|---|---|
| 1 | All opponents are vanilla |
| 2 | Each opponent has 1 visible package |
| 3 | Each opponent has 1 visible package; 1 opponent declares a target hand |
| 4 | Each opponent has 2 compatible visible packages |
| 5 | Each opponent has 2 compatible visible packages; 1 opponent declares a legendary target |

---

## Boon Catalog

Boons are organized by archetype (design reference only) and tier. Tier 1 boons fire on guaranteed triggers, low ceiling, always useful. Tier 2 fire on conditional triggers, higher ceiling. Tier 3 are build-warping, can be weak alone, devastating in combination.

Only the 12 boons listed in **Phase 0 Boon Pool** are required for the broader Phase 0 prototype. Milestone 1 implements the curated starter set first. Other boons in this catalog are future candidates.

---

### Archetype: The Sculptor
*Lock into one suit, saturate the Wall, let the hand emerge*

**[T1] Current**
Passive. Each time you draw a tile that matches the suit you currently have the most of in your hand, gain 1 Suit Counter (tracked in UI). When you Hu, add +1 fan per 4 Suit Counters. Rewards natural suit concentration without requiring a declaration upfront.

**[T1] Forced Hand**
Passive. After completing any Chi sequence, the next tile you draw is revealed before you commit to drawing it. You may pass the draw and take the tile after it instead. Information reward for building sequences.

**[T2] Saturation**
Passive. When your hand contains 10 or more tiles of the same suit, draw 2 tiles per turn instead of 1. Activates automatically once you reach the threshold. Specifically enables Nine Gates without pre-declaring it.

**[T3] Pure Expression**
Passive. If you win a Qing Yi Se with a fully concealed hand, your hand is treated as if won by Zi Mo regardless of how you actually won. Hard prerequisite (concealed + pure suit) for a meaningful rule exception. Does not apply to open melds.

---

### Archetype: The Hunter
*Hold concealed, pass calls, fish deep, win once huge*

**[T1] Discipline**
Passive. Each time you legally pass on a call you could have made (Chi, Peng, or Kong), gain 1 Restraint Counter (tracked in UI). When you Hu, add +0.5 fan per Restraint Counter, rounded down. Passing 6 calls adds +3 fan -- enough to turn a Ping Hu into a valid hand on its own.

**[T1] Still Water**
Passive. Your Men Qian (concealed hand) bonus gives +2 fan instead of +1. Straightforward amplification of a condition already worth pursuing.

**[T2] Patient Tide**
Passive. If you are in tenpai for 4 or more consecutive turns without winning, gain +2 fan when you finally Hu. Rewards holding out for the right tile rather than settling.

**[T2] Iron Grip**
Passive. If a tile has been in your hand for 8 or more turns and it ends up being part of your winning hand, that tile's set scores +1 fan. Rewards reading early and committing to a shape before anyone else sees it.

---

### Archetype: The Caller
*Call everything, Peng fast, Honor tile snowball*

**[T1] Dragon's Weight**
Passive. Each Dragon Peng or Kong in your hand gives +2 fan instead of +1. Simple amplification of an already-powerful condition. Pairs directly with Da San Yuan builds.

**[T1] Open Eyes**
Passive. After completing any Peng, reveal the top 3 tiles of the Wall before your next draw. Calls become information events, not just scoring events.

**[T2] Heavy Hand**
Passive. If your hand contains 2 or more Pengs when you Hu, score +2 fan. Rewards committing to an all-triplet strategy regardless of hand shape.

**[T2] Kong Surge**
Active. Once per hand, after declaring a Kong, you may draw 2 supplement tiles instead of 1 and choose which to keep, discarding the other. Converts the rarest call in mahjong into a genuine strategic tool.

---

### Archetype: The Reader
*Information advantages, react to the Wall, never over-commit*

**[T1] Third Eye**
Passive. After your opening hand is dealt, reveal the next 5 Wall tiles. Shapes your early discards with knowledge of what is coming immediately.

**[T1] Trailing Wind**
Passive. Whenever any opponent completes a call (Chi, Peng, or Kong), see the next tile they will draw. Track opponent builds in real time without any active input.

**[T2] Second Sight**
Active. Once per hand, before drawing your tile, you may look at the next 3 Wall tiles and decide whether to draw normally or pass your turn entirely. Information before commitment.

**[T2] Fresh Start**
Active. Once per hand, during the opening, swap up to 3 tiles from your starting hand back into the Wall and draw 3 replacements. The Wall is reshuffled after the swap so the replacements are random. The only opening-affecting boon in the set.

---

### Archetype: The Gambler
*High variance, last-tile engineering, risk as strategy*

**[T1] Last Gasp**
Passive. Winning with 12 or fewer tiles left in the Wall gives +1 fan. Winning on the very last tile of the Wall (Hai Di) gives +3 fan instead of +1. Makes late-Wall play worth engineering toward without making the boon dead in most hands.

**[T1] Stolen Thunder**
Passive. Robbing a Kong (Qiang Gang) gives +3 fan instead of +1. If an opponent declares any Kong while you are in tenpai, gain +1 fan on your eventual Hu this hand. Rewards reading opponents' Kong declarations and positioning your hand to punish them.

**[T2] Double or Nothing**
Active. Once per hand, before drawing any tile, declare "Double." If the tile you draw completes your hand at or above minimum fan, score x2 total fan. If it does not, lose 1 life immediately. A direct bet on a single draw. Deferred until after Phase 0 because multiplicative fan and mid-hand life loss add major balance noise.

**[T3] Destiny**
Active. Once per hand, before drawing, declare any specific tile aloud (e.g. "7-Tiao"). If that exact tile is next in the Wall, win the round immediately and score a Legend rating regardless of your actual hand state. If it is not, your draw turn is skipped. Once per run, not once per hand -- this is a nuclear option. Deferred until after Phase 0.

---

### Archetype: The Grinder
*Tournament memory, rounds won fuel current hand*

**[T1] Momentum**
Passive. For each round you have won so far in this tournament, start this hand with 1 additional tile in your opening draw (discard the extras down to 13 before play begins). Win 3 rounds and your opening draw is 16 tiles -- you pick your best 13. Tournament memory directly improves information at the start of every subsequent hand.

**[T1] Compounding Interest**
Passive. Gain +1 fan if you won the previous round. Gain +2 fan instead if your previous win was A rating or better. Makes later rounds feel momentum-driven without giving free fan simply for already being ahead.

**[T2] Muscle Memory**
Passive. If you won the previous round by completing the same hand pattern you are currently building (e.g. Qing Yi Se two rounds in a row), gain +2 fan when you Hu this round. Rewards committing to a consistent strategy across rounds.

**[T2] Veteran's Edge**
Active. Once per hand, retrieve any tile from the discard pile -- yours or an opponent's -- into your hand, then discard any tile normally. Unlocks only after winning 2 or more rounds. Tournament experience grants a skill that beginners do not have access to.

---

## Boon Interaction Highlights

The combinations worth knowing before playtesting:

**Discipline + Still Water** (Hunter core): passing 8 calls adds +4 fan from Discipline plus +2 from Still Water's concealed bonus. A Ping Hu with this stack scores 7 fan -- an A-rated hand -- without a single "valuable" tile.

**Current + Saturation** (Sculptor core): Suit Counters build as you draw same-suit tiles, and once you hit 10 of a suit Saturation kicks in giving 2 draws per turn. The counter pays out just as the tempo accelerates -- a double payoff at the moment of peak suit concentration.

**Dragon's Weight + Heavy Hand** (Caller core): two Dragon Pengs give +4 fan from Dragon's Weight plus +2 from Heavy Hand. That's +6 fan on top of whatever the base hand scores. A Dui Dui Hu (3 fan base) with two Dragon Pengs becomes 9 fan -- an S-rated hand -- without touching a Limit hand.

**Last Gasp + Stolen Thunder** (Gambler core): both boons reward rare timing windows, but each now has a lower-ceiling fallback so the Gambler package creates tension without being dead in ordinary hands.

**Momentum + Compounding Interest** (Grinder core): Momentum improves opening selection as the run progresses, while Compounding Interest rewards carrying a strong previous win forward. The Grinder gets continuity without automatically outscaling every other archetype.

---

## Deferred for Phase 0

**Classes:** The loop needs to be fun before class identity layers on top.

**Overworld / Map:** The tournament makes a map unnecessary for Phase 0.

**Merged Wall (co-op):** A co-op mechanic, not a core mechanic. Returns once solo is proven.

**Boss Auras:** These add complexity before the base loop is validated.

**Relics:** Natural fit for the roguelike layer but should not be designed until boons are proven.

**Opponent-affecting boons:** Deferred. Self-affecting boons need to be validated first.

**Shanten-based HP loss:** Removed for Phase 0. Losing a hand costs exactly 1 life. The more nuanced "how close were you?" damage model can return later if the core loop needs more texture.

---

## Open Questions

**Rating economy:** Ratings are display-only in Phase 0. Later versions may let A/S/SS/Legend wins influence reward choices, but this should not be added until basic win consistency is understood.

**Boon pool size after Phase 0:** The initial pool is 12 boons. A replayable version likely needs 18-20 boons, especially if opponents eventually draw from the same pool.

---

## Candidate Expansion Set

After the first loop test, expand toward 18-20 boons before judging long-term replayability. Candidate additions:

**Clean Lines** (Sculptor): Passive. If your winning hand contains no honors, gain +1 fan. If it is also fully concealed, gain +2 fan instead.

**Same River** (Sculptor): Passive. After you discard an honor tile, the next suited tile you draw that matches your majority suit gains 1 Suit Counter.

**Quiet Door** (Hunter): Passive. If you reach tenpai with a concealed hand, gain +1 fan on Hu this hand.

**Known Quantity** (Reader): Passive. After any player reveals tiles through a call, mark one tile type from that meld. If you Hu using that tile type, gain +1 fan.

**Thin Edge** (Gambler): Passive. If you win while waiting on exactly one tile type, gain +2 fan.

**Form Study** (Grinder): Passive. When you win a round, remember its primary hand pattern. The next time you win with a different primary hand pattern, gain +1 fan.
