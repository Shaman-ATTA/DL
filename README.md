# Dragonshard Legends / Легенды Драконьего Осколка
An original fantasy tap/idle RPG for Android, built with Godot 4.3 at 1080x1920 portrait.
- data/balance.json: the whole economy. sim/simulate.py runs the 30-day balance sim (see sim/BALANCE_REPORT.md).
- scripts/game.gd: state, formulas (they mirror the sim), save/offline, RU/EN text. scripts/main.gd: UI, battle, juice.
- tools_process_art.py and tools_make_audio.py regenerate the assets. Licenses are in LICENSES.md.
- Store materials are in store/.
Build: `godot --headless --export-release "Android AAB" build/DragonshardLegends-release.aab` (needs JDK 17, Android SDK, android/ build template, and export_presets.cfg, which is local and holds the keystore password, so it isn't committed).
