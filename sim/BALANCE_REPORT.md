# Dragonshard Legends — Balance Report (30-day sim)
Model: 5 taps/s, 4 sessions/day (75 min active), offline gold 50% (12h cap), greedy upgrades, prestige after 8 active min without new max stage (stage>=50).
Formulas: enemy HP = 12*1.39^(s-1); boss x7, 30s; shards = floor(8*1.08^(stage-50)); artifacts cost ceil(base*growth^L) (core growth 1.22).
Results (sim/sim_output.txt):
- First prestige: stage 56, day 1.3. Run 3: 77, run 4: 98, run 5: 118.
- Day 10: stage ~170; day 20: ~215; day 30: ~247.
- Max stage climbs every few runs over the whole 30 days, so there's no dead wall. Runs get shorter (4–20h) as artifacts compound.
Change log: removed the late-HP jump at stage 120 (it caused a 20-day plateau at ~120). Switched shards from polynomial to exponential and lowered artifact cost growth from 1.6 to 1.22.
