# Dragonshard Legends — Balance Report (30-day sim)
Model: 5 taps/s, 4 sessions/day (75 min active), offline gold 50% (12h cap), greedy upgrades, prestige after 8 active min without new max stage (stage>=50).
Formulas: enemy HP = 12*1.39^(s-1); boss x7, 30s; shards = floor(8*1.08^(stage-50)); artifacts cost ceil(base*growth^L) (core growth 1.22).
Results (sim/sim_output.txt):
- First prestige: stage 56, day 1.3. Run 3: 77, run 4: 98, run 5: 118.
- Day 10: stage ~170; day 20: ~215; day 30: ~247.
- Max stage climbs every few runs over the whole 30 days, so there's no dead wall. Runs get shorter (4–20h) as artifacts compound.
Change log: removed the late-HP jump at stage 120 (it caused a 20-day plateau at ~120). Switched shards from polynomial to exponential and lowered artifact cost growth from 1.6 to 1.22.

## Phase 3 (v1.2.0) — meta systems rebalance

The sim now models gear, pets, the skill tree and crit as expected values (`META=1`, the default; `META=0` = the old core loop).
Best stage reached by day (30-day sim, same player model):

| Run | d1 | d3 | d5 | d10 | d20 | d30 |
|---|---|---|---|---|---|---|
| META=0 (core only) | 56* | 76 | 106 | 135 | 177 | 218 |
| META=1 first tuning | 83 | 135 | 171 | 285 | 533 | 592 |
| META=1 **final** | 53 | 99 | 123 | 163 | 261 | 366 |

*The first META=0 prestige lands at day 1.34.

The first tuning ran away: with ~2.7× progress by day 30, the artifact cost curve became trivial.
Changes in data/content.json:
- gear rarity_base 0.3/0.7/1.5/3.0 → 0.05/0.12/0.25/0.5
- enhance 0.2 → 0.06 per level
- boss drop 15% → 10%
- tree: 1 point per 25 stages (was 10); tap/ally nodes 0.08; gold 0.10; crit dmg 0.06
- drake/sprite pet 0.08 per level; owl 0.06

Result: early pacing matches the core game, with a ~1.2× lift at d5–10 and ~1.7× at d30.
The remaining gap is intended: it rewards engagement with the new systems. Revisit it with real retention data.
