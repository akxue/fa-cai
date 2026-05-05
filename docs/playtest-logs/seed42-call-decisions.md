# Seed 42 call-decision log

Logs every chi/peng/open-kong opportunity. Format per opportunity:
- what was discarded, by whom
- responder's hand state
- which calls were available
- the gate inputs (ting before/after, 3-fan path before/after)
- decision and reason for accept/reject

---

## Opportunity 1 (step 45)

- p1 discarded **1W**
- p4 (responder) hand: `3T 4T 4T 5T 5T 1W 1W 3W 3W 4W 8W F B`
- p4 sets: 0 open
- offered: peng
- pre-call live ting (combined): 1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting 1→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 2 (step 58)

- p4 discarded **3T**
- p1 (responder) hand: `4T 5T 8T 9T 9T 3W 4W 5W 7W 9W 2B 7B 8B`
- p1 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 4
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using tiao_4_d+tiao_5_b): ting 4→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 3 (step 74)

- p3 discarded **3B**
- p2 (responder) hand: `3T 4T 6W 7W 2B 2B 3B 3B 4B 5B 5B 6B 9B`
- p2 sets: 0 open
- offered: peng
- pre-call live ting (combined): 2
- pre-call chosen target: qing_yi_se (est_fan=6)
- pre-call has_3fan_path: true
- **peng**: ting 2→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 4 (step 83)

- p1 discarded **2B**
- p2 (responder) hand: `3T 4T 6W 7W 2B 2B 3B 3B 4B 5B 5B 6B 9B`
- p2 sets: 0 open
- offered: peng, chi (1 combos)
- pre-call live ting (combined): 2
- pre-call chosen target: qing_yi_se (est_fan=6)
- pre-call has_3fan_path: true
- **peng**: ting 2→100 (REGRESS), has_3fan_post=true → REJECT
- **chi #1** (using bing_3_c+bing_4_c): ting 2→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 5 (step 89)

- p2 discarded **9B**
- p3 (responder) hand: `2T 2T 6T 8T 7W 4B 6B 6B 7B 8B N N B`
- p3 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 2
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using bing_7_d+bing_8_b): ting 2→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 6 (step 94)

- p3 discarded **3B**
- p2 (responder) hand: `3T 4T 2W 6W 7W 2B 2B 3B 3B 4B 5B 5B 6B`
- p2 sets: 0 open
- offered: peng
- pre-call live ting (combined): 2
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **peng**: ting 2→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 7 (step 98)

- p4 discarded **4W**
- p1 (responder) hand: `4T 5T 8T 9T 9T 3W 4W 5W 7W 5B 7B 7B 8B`
- p1 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using wan_3_c+wan_5_b): ting 3→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 8 (step 120)

- p4 discarded **N**
- p3 (responder) hand: `2T 2T 6T 8T 7W 8W 6B 6B 7B 8B N N B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): 2
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting 2→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 9 (step 133)

- p3 discarded **7B**
- p1 (responder) hand: `4T 5T 6T 8T 9T 9T 3W 4W 5W 7W 5B 7B 7B`
- p1 sets: 0 open
- offered: peng
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **peng**: ting 3→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 10 (step 144)

- p1 discarded **B**
- p3 (responder) hand: `2T 2T 6T 8T 7W 8W 6B 6B 8B N N B B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): 1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting 1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 11 (step 168)

- p2 discarded **9T**
- p1 (responder) hand: `4T 5T 6T 8T 9T 9T 3W 4W 5W 7W 5B 7B 7B`
- p1 sets: 0 open
- offered: peng
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **peng**: ting 3→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 12 (step 175)

- p3 discarded **6T**
- p4 (responder) hand: `4T 4T 5T 5T 1W 1W 3W 3W 5W 8W 8W F B`
- p4 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 0
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using tiao_4_c+tiao_5_c): ting 0→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 13 (step 178)

- p4 discarded **5W**
- p1 (responder) hand: `4T 5T 6T 8T 9T 9T 3W 4W 5W 7W 5B 7B 7B`
- p1 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using wan_3_c+wan_4_c): ting 3→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 14 (step 188)

- p2 discarded **7B**
- p1 (responder) hand: `4T 5T 6T 9T 9T 2W 3W 4W 5W 7W 5B 7B 7B`
- p1 sets: 0 open
- offered: peng
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **peng**: ting 3→-1 (ok), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 15 (step 243)

- p1 discarded **1B**
- p2 (responder) hand: `3T 4T 4W 4W 6W 7W 2B 2B 3B 3B 5B 5B 6B`
- p2 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using bing_2_c+bing_3_c): ting 1→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 16 (step 258)

- p4 discarded **6W**
- p1 (responder) hand: `4T 5T 6T 9T 9T 2W 3W 4W 5W 7W 5B 7B 7B`
- p1 sets: 0 open
- offered: chi (2 combos)
- pre-call live ting (combined): 3
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using wan_4_c+wan_5_b): ting 3→100 (REGRESS), has_3fan_post=false → REJECT
- **chi #2** (using wan_5_b+wan_7_c): ting 3→-1 (ok), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 17 (step 263)

- p1 discarded **2T**
- p2 (responder) hand: `3T 4T 4W 4W 6W 7W 2B 2B 3B 3B 5B 5B 6B`
- p2 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using tiao_3_b+tiao_4_a): ting 1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 18 (step 264)

- p1 discarded **2T**
- p3 (responder) hand: `2T 2T 3W 6W 7W 7W 8W 6B 6B N N B B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): 0
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting 0→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 19 (step 275)

- p3 discarded **6T**
- p4 (responder) hand: `4T 4T 5T 5T 1W 1W 3W 3W 8W 8W F F B`
- p4 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using tiao_4_c+tiao_5_c): ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 20 (step 283)

- p1 discarded **7B**
- p2 (responder) hand: `3T 4T 4W 4W 6W 7W 2B 2B 3B 3B 5B 5B 6B`
- p2 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): 1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using bing_5_d+bing_6_b): ting 1→100 (REGRESS), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 21 (step 298)

- p4 discarded **3T**
- p1 (responder) hand: `4T 5T 6T 9T 9T 2W 3W 4W 5W 6W 7W 5B 7B`
- p1 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): -1
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using tiao_4_d+tiao_5_b): ting -1→-1 (ok), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 22 (step 315)

- p3 discarded **3W**
- p4 (responder) hand: `4T 4T 5T 5T 1W 1W 3W 3W 8W 8W F F B`
- p4 sets: 0 open
- offered: peng
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 23 (step 329)

- p2 discarded **6B**
- p3 (responder) hand: `2T 2T 6W 7W 7W 8W 8W 6B 6B N N B B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 24 (step 349)

- p2 discarded **2T**
- p3 (responder) hand: `2T 2T 6W 7W 7W 8W 8W 6B 6B N N B B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 25 (step 378)

- p4 discarded **5T**
- p1 (responder) hand: `4T 5T 6T 9T 9T 2W 3W 4W 5W 6W 7W 5B 7B`
- p1 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): -1
- pre-call chosen target: default (est_fan=1)
- pre-call has_3fan_path: false
- **chi #1** (using tiao_4_d+tiao_6_d): ting -1→-1 (ok), has_3fan_post=false → REJECT
- AI decision: **pass_reaction**

## Opportunity 26 (step 400)

- p4 discarded **N**
- p3 (responder) hand: `2T 2T 6W 7W 7W 8W 8W 6B 6B N N B B`
- p3 sets: 0 open
- offered: peng
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 27 (step 410)

- p2 discarded **4T**
- p4 (responder) hand: `4T 4T 5T 5T 1W 1W 3W 3W 8W 8W F F B`
- p4 sets: 0 open
- offered: peng
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **peng**: ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

## Opportunity 28 (step 415)

- p3 discarded **2W**
- p4 (responder) hand: `4T 4T 5T 5T 1W 1W 3W 3W 8W 8W F F B`
- p4 sets: 0 open
- offered: chi (1 combos)
- pre-call live ting (combined): -1
- pre-call chosen target: dui_dui_hu (est_fan=3)
- pre-call has_3fan_path: true
- **chi #1** (using wan_1_b+wan_3_a): ting -1→100 (REGRESS), has_3fan_post=true → REJECT
- AI decision: **pass_reaction**

---

## Summary

- Total opportunities: 28
- AI accepted: 0
- AI passed: 28

### Rejection reasons (per call type)

- no 3-fan path post-call: 1
- no 3-fan path post-chi: 3
- ting regression (chi): 12
- ting regression: 14

Final phase: deal_over after 421 steps.
