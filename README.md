# Dragonshard Legends / Легенды Драконьего Осколка
An original fantasy tap/idle RPG for Android, built with Godot 4.3 at 1080x1920 portrait.
- data/balance.json: the whole economy. sim/simulate.py runs the 30-day balance sim (see sim/BALANCE_REPORT.md).
- scripts/game.gd: state, formulas (they mirror the sim), save/offline, RU/EN text. scripts/main.gd: UI, battle, juice.
- tools_process_art.py and tools_make_audio.py regenerate the assets. Licenses are in LICENSES.md.
- Store materials are in store/.
Build: `godot --headless --export-release "Android AAB" build/DragonshardLegends-release.aab` (needs JDK 17, Android SDK, android/ build template, and export_presets.cfg, which is local and holds the keystore password, so it isn't committed).

## v1.1.0
- Animated intro + main menu, tweened tabs/panels, button juice, idle/attack animations, dissolve deaths, boss entrances, level-up/prestige celebrations, pooled damage numbers, biome transitions, OFL Cyrillic fonts, compressed textures, Ogg music.
- Google Play Games Services v2 (sign-in, cloud save, achievements, leaderboard) — optional; the game works without it.
- Google Play Billing shop: gem packs, Supporter pack, VIP (x2 gold). Gems are non pay-to-win (cooldowns, time warp, auto-tapper, cosmetic auras).
- All Play IDs live in `data/services.json` (fill game_id / achievement / leaderboard IDs from Play Console; also set `godot_play_game_services/game_id` in the export preset).
- Build: Godot 4.5.1 with Android gradle build template (`android/build`).

## v1.2.0 (Phase 3)
- Modern tween-based hero and monster animation: squash/stretch, hit flash, idle breathing, death dissolve
- Progressive wounds at 75/50/25% HP, bosses included
- Expanded settings: audio, haptics, graphics/FPS/battery, notifications, language, account, credits, reset
- 12 RU/EN story cutscenes between zones
- Weekly leaderboards: Play Games daily/weekly/all-time spans, in-game screen for stage and raid
- New CC0 orchestral music (see LICENSES.md)
- TT2-inspired meta: gear and sets, pets, skill tree, fairies, daily calendar and quests, solo raid, weekend festival (see docs/TT2_GAP.md)
