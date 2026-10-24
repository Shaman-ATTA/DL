# Tap Titans 2 → Dragonshard Legends: gap analysis (Phase 3)

TT2 reference loop (from public guides/wiki): tap + heroes (allies) + skills, stage bosses with a timer, prestige for relics → artifacts,
plus a deep meta layer: equipment & sets, pets, skill tree, clan raids, tournaments, daily login/quests, fairies, events, leaderboards.

| TT2 feature | Before 1.2 | Status in 1.2 | Notes |
|---|---|---|---|
| Tap / heroes / skills / bosses / prestige / artifacts | ✅ | ✅ | core loop since 1.0 |
| Critical hits (+ crit chance/damage stats) | flat crit | ✅ added | crit chance/damage from talents and the Ferret pet |
| Equipment (4 slots, rarities, enhance, salvage) | ❌ | ✅ added | boss drops (15% + pity every 10 bosses), forge for essence |
| Equipment sets | ❌ | ✅ added | 4 sets, 2/4-piece bonuses |
| Pets (passive bonus + auto-strike) | ❌ | ✅ added | 4 pets from eggs, active pet strikes every 10 taps |
| Skill tree | ❌ | ✅ added | 3 branches × 4 nodes, points from best stage, gem respec |
| Fairies (flying bonus) | ❌ | ✅ added | tap to catch: gold, gems or essence |
| Daily login streak (7-day calendar) | daily gems | ✅ added | missing a day restarts the week |
| Daily quests | ❌ | ✅ added | 3 per day + bonus egg |
| Clan raid (timed damage race) | ❌ | ✅ solo raid | 3 tickets/day, 30 s vs the Wyrm, tiered score + PGS leaderboard |
| Weekly events | ❌ | ✅ weekend festival | ×1.5 gold, ×2 fairies on Sat/Sun |
| Leaderboards | native PGS only | ✅ in-game screen | daily/weekly/all-time, stage + raid |
| Clans, clan chat, co-op raids | ❌ | ⛔ skipped | needs our own backend + moderation; not possible with PGS alone |
| Tournaments (async PvP brackets) | ❌ | ⛔ skipped | needs a server to bracket players fairly; the weekly PGS board stands in |
| Equipment cosmetics / hero skins | auras | ⛔ skipped | art budget; auras cover cosmetics |
| Push notifications | ❌ | ⛔ skipped | needs FCM/local-notification plugin; in-game notices only |
| Mythic sets, enchant, crafting shards | ❌ | ⛔ skipped | depth for later; current gear covers the role |
| Spells/skill combos, "Clan ship" | ❌ | ⛔ skipped | complexity vs value for a first release |

Balance: sim/simulate.py now models gear, pets, talents and crit (META=1, the default); see sim/BALANCE_REPORT.md.
