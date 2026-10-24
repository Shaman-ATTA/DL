extends Node
## Game state + economy. Formulas mirror sim/simulate.py exactly.
signal changed
var C: Dictionary
var gold := 0.0
var shards := 0
var hero_lv := 1
var comp: Array = []
var art: Dictionary = {}
var stage := 1
var max_stage := 1
var run_max := 1
var kills := 0
var total_taps := 0
var sound_on := true
var music_on := true
var lang := "ru"
var offline_gold := 0.0
var gems := 0
var owned: Dictionary = {}        # non-consumable unlocks: "supporter", "vip", "aura_fire" ...
var aura := ""                    # equipped cosmetic aura
var ach: Dictionary = {}          # locally unlocked achievements
var prestiges := 0
var last_daily := ""
var auto_tap_left := 0.0
var processed_tokens: Dictionary = {}  # purchase tokens already granted (idempotency)
var S: Dictionary                 # data/services.json
var K: Dictionary                 # data/content.json (gear, pets, tree, quests, raid ...)
# ---- Phase 3 state ----
var settings := {"vol_master": 1.0, "vol_music": 0.8, "vol_sfx": 1.0, "haptics": true, "quality": 2, "fps": 60,
	"battery": false, "dmg_numbers": true, "shake": true, "notif_offline": true, "notif_skills": true}
var essence := 0
var eggs := 0
var gear: Array = []              # [{id, slot, r, set, lv}]
var equipped := {}                # slot -> gear id
var gear_uid := 1
var pets := {}                    # pet id -> level (0 = not owned)
var active_pet := ""
var tree := {}                    # node id -> level
var streak := 0                   # days claimed in the current 7-day cycle
var streak_day := ""
var quest_day := ""
var quests: Array = []            # [{k, goal, p, done}]
var quest_bonus := false
var raid_day := ""
var raid_tickets := 3
var raid_best := 0                # tier*100 + percent
var story_seen := {}
var offline_full := false
var stats := {"kills": 0, "bosses": 0, "fairies": 0, "raids": 0}
signal quest_done(text: String)
signal achievement(key: String)
signal gems_changed
signal click
const SAVE := "user://save.json"

func _ready() -> void:
	C = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	S = JSON.parse_string(FileAccess.get_file_as_string("res://data/services.json"))
	K = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	var ex = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n.json"))
	if typeof(ex) == TYPE_DICTIONARY: _i18n_extra = ex
	for p in K.pets.list: pets[p.id] = 0
	for b in K.tree.branches.values():
		for n in b: tree[n[0]] = 0
	comp.resize(C.companions.size()); comp.fill(0)
	for a in C.artifacts: art[a.id] = 0
	if OS.get_locale_language() != "ru": lang = "en"
	load_game()
	_dev_lang()

func hp(s: int) -> float:
	var L: int = int(C.late_growth_from_stage)
	if s <= L: return C.enemy_hp_base * pow(C.enemy_hp_growth, s - 1)
	return C.enemy_hp_base * pow(C.enemy_hp_growth, L - 1) * pow(C.enemy_hp_growth_late, s - L)

func is_boss_stage() -> bool: return true  # every stage ends with a boss after N enemies

func comp_mult(l: int) -> float:
	var m := 1.0
	for ms in C.companion_milestones:
		if l >= ms[0]: m *= ms[1]
	var last: int = C.companion_milestones[-1][0]
	if l > last: m *= pow(C.companion_milestone_repeat_mult, (l - last) / int(C.companion_milestone_repeat_every))
	return m

func art_def(id: String) -> Dictionary:
	for a in C.artifacts:
		if a.id == id: return a
	return {}

func artv(id: String) -> float:
	var a := art_def(id); var L: int = art[id]
	if a.effect in ["boss_time", "start_stage"]: return a.per_level * L
	return pow(a.per_level, L)

func comp_dps(i: int, l: int = -1) -> float:
	if l < 0: l = comp[i]
	return C.companions[i].base_dps * l * comp_mult(l) * artv("heart") * ally_mult()

func dps() -> float:
	var t := 0.0
	for i in comp.size(): t += comp_dps(i)
	return t

func tap_dmg(l: int = -1) -> float:
	if l < 0: l = hero_lv
	var h: Dictionary = C.hero
	return l * h.dmg_per_level * pow(h.milestone_mult, l / int(h.milestone_every)) * artv("gauntlet") * artv("heart") * tap_mult() + dps() * h.dps_to_tap_share

func hero_cost(l: int = -1) -> float:
	if l < 0: l = hero_lv
	return ceil(C.hero.base_cost * pow(C.hero.cost_growth, l - 1))

func comp_cost(i: int) -> float:
	return ceil(C.companions[i].base_cost * pow(C.companion_cost_growth, comp[i]))

func gold_kill(s: int, boss := false) -> float:
	var g: float = hp(s) * C.gold_per_hp * artv("crown") * (S.gems.vip_gold_mult if owned.has("vip") else 1.0) * gold_mult()
	return g * (C.boss_gold_mult * (1.0 + tv("t_bossg")) if boss else 1.0)

func boss_time() -> float: return C.boss_time + artv("hourglass") + tv("t_boss") + set_bonus("frost")

func shards_for(s: int) -> int:
	var p: Dictionary = C.prestige
	if s < p.min_stage: return 0
	return int(p.base * pow(p.growth, s - p.min_stage))

func art_cost(id: String) -> int:
	var a := art_def(id)
	return int(ceil(a.cost_base * pow(a.cost_growth, art[id])))

func buy_hero() -> bool:
	var c := hero_cost()
	if gold < c: return false
	gold -= c; hero_lv += 1; qp("upgrades"); changed.emit(); return true

func buy_comp(i: int) -> bool:
	var c := comp_cost(i)
	if gold < c: return false
	gold -= c; comp[i] += 1; qp("upgrades")
	if not comp.has(0): unlock("all_allies")
	changed.emit(); return true

func buy_art(id: String) -> bool:
	var a := art_def(id); var c := art_cost(id)
	if shards < c or art[id] >= a.max: return false
	shards -= c; art[id] += 1; changed.emit(); return true

func prestige() -> int:
	var s := shards_for(run_max)
	if s <= 0: return 0
	shards += s; gold = 0; hero_lv = 1; comp.fill(0)
	stage = 1 + int(artv("start_stage")); run_max = stage; kills = 0
	prestiges += 1; unlock("first_prestige")
	changed.emit(); save_game(); return s

## Dev screenshot args carry the language as their last comma field.
func _dev_lang() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a.begins_with("--intro-shot="): lang = a.split(",")[-1]

func to_dict() -> Dictionary:
	return {"v": 3, "settings": settings, "essence": essence, "eggs": eggs, "gear": gear, "equipped": equipped,
		"gear_uid": gear_uid, "pets": pets, "active_pet": active_pet, "tree": tree, "streak": streak, "streak_day": streak_day,
		"quest_day": quest_day, "quests": quests, "quest_bonus": quest_bonus, "raid_day": raid_day, "raid_tickets": raid_tickets,
		"raid_best": raid_best, "story": story_seen, "stats": stats, "gold": gold, "shards": shards, "hero": hero_lv, "comp": comp, "art": art,
		"stage": stage, "max": max_stage, "run_max": run_max, "taps": total_taps, "snd": sound_on,
		"mus": music_on, "lang": lang, "t": Time.get_unix_time_from_system(), "gems": gems, "owned": owned,
		"aura": aura, "ach": ach, "prestiges": prestiges, "daily": last_daily, "tokens": processed_tokens}

func from_dict(d: Dictionary) -> void:
	gold = d.get("gold", 0.0); shards = int(d.get("shards", 0)); hero_lv = int(d.get("hero", 1))
	var cs: Array = d.get("comp", [])
	comp.fill(0)
	for i in min(cs.size(), comp.size()): comp[i] = int(cs[i])
	var ar: Dictionary = d.get("art", {})
	for k in art: art[k] = int(ar.get(k, 0))
	stage = int(d.get("stage", 1)); max_stage = int(d.get("max", 1)); run_max = int(d.get("run_max", stage))
	total_taps = int(d.get("taps", 0)); sound_on = d.get("snd", true); music_on = d.get("mus", true); lang = d.get("lang", lang)
	gems = int(d.get("gems", 0)); owned = d.get("owned", {}); aura = d.get("aura", ""); ach = d.get("ach", {})
	prestiges = int(d.get("prestiges", 0)); last_daily = d.get("daily", ""); processed_tokens = d.get("tokens", {})
	# v3 (Phase 3); older saves migrate with defaults
	var st: Dictionary = d.get("settings", {})
	for k in st:
		if settings.has(k): settings[k] = st[k]
	if not st.has("vol_sfx") and not sound_on: settings.vol_sfx = 0.0
	if not st.has("vol_music") and not music_on: settings.vol_music = 0.0
	settings.quality = int(settings.quality); settings.fps = int(settings.fps)
	essence = int(d.get("essence", 0)); eggs = int(d.get("eggs", 0))
	gear = d.get("gear", []); equipped = d.get("equipped", {}); gear_uid = int(d.get("gear_uid", 1))
	for g in gear: g.id = int(g.id); g.r = int(g.r); g.lv = int(g.lv)
	for k in equipped: equipped[k] = int(equipped[k])
	var pd: Dictionary = d.get("pets", {})
	for k in pets: pets[k] = int(pd.get(k, 0))
	active_pet = d.get("active_pet", "")
	var td: Dictionary = d.get("tree", {})
	for k in tree: tree[k] = int(td.get(k, 0))
	streak = int(d.get("streak", 0)); streak_day = d.get("streak_day", "")
	quest_day = d.get("quest_day", ""); quests = d.get("quests", []); quest_bonus = d.get("quest_bonus", false)
	raid_day = d.get("raid_day", ""); raid_tickets = int(d.get("raid_tickets", 3)); raid_best = int(d.get("raid_best", 0))
	story_seen = d.get("story", {}); var sd: Dictionary = d.get("stats", {})
	for k in stats: stats[k] = int(sd.get(k, 0))

## Progress score used to resolve local vs cloud save conflicts.
func progress_score(d: Dictionary) -> float:
	return float(d.get("prestiges", 0)) * 1e6 + float(d.get("max", 1)) * 1e3 + float(d.get("shards", 0)) * 1e-3

func save_game() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(to_dict()))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if typeof(d) != TYPE_DICTIONARY: return
	from_dict(d)
	var dt: float = clamp(Time.get_unix_time_from_system() - float(d.get("t", 0)), 0, C.offline_cap_hours * 3600.0)
	offline_full = dt >= C.offline_cap_hours * 3600.0 - 1
	if dt > 60: offline_gold = offline_income(dt); gold += offline_gold

func offline_income(seconds: float) -> float:
	var d_ := dps()
	if d_ <= 0: return 0.0
	var kt: float = max(hp(stage) / d_, C.respawn_delay)
	return seconds / kt * gold_kill(stage) * C.offline_gold_factor * artv("moonwell") * (1.0 + tv("t_off"))

## Daily login gems; returns amount granted (0 if already claimed today).
func claim_daily() -> int:
	var today := Time.get_date_string_from_system()
	new_day(today)
	if last_daily == today: return 0
	last_daily = today; add_gems(int(S.gems.daily_login)); return int(S.gems.daily_login)

func add_gems(n: int) -> void:
	gems += n; gems_changed.emit(); save_game()

func spend_gems(n: int) -> bool:
	if gems < n: return false
	gems -= n; gems_changed.emit(); save_game(); return true

func unlock(key: String) -> void:
	if ach.has(key): return
	ach[key] = true; gems += int(S.gems.achievement_reward); gems_changed.emit()
	achievement.emit(key)

func on_stage_cleared(new_stage: int) -> void:
	unlock("first_boss")
	stats.bosses += 1; qp("bosses")
	if new_stage > max_stage and new_stage % int(K.pets.egg_every_stages) == 1 and new_stage > 1: eggs += 1
	if new_stage > max_stage and new_stage % 10 == 1: add_gems(int(S.gems.boss_every_10_first_clear))
	for m in [50, 100, 200]:
		if new_stage >= m: unlock("stage_%d" % m)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()

# ================= Phase 3: meta-progression (gear, pets, tree, streak, quests, raid) =================
func tv(id: String) -> float:
	for b in K.tree.branches.values():
		for n in b:
			if n[0] == id: return float(n[1]) * int(tree.get(id, 0))
	return 0.0

func tree_points() -> int: return int(max_stage / int(K.tree.stages_per_point))
func tree_spent() -> int:
	var n := 0
	for k in tree: n += int(tree[k])
	return n
func tree_buy(id: String) -> bool:
	if tree_spent() >= tree_points() or int(tree[id]) >= int(K.tree.max): return false
	tree[id] = int(tree[id]) + 1; changed.emit(); save_game(); return true
func tree_respec() -> bool:
	if tree_spent() == 0 or not spend_gems(int(K.tree.respec_cost)): return false
	for k in tree: tree[k] = 0
	changed.emit(); return true

func gear_by_id(id: int) -> Dictionary:
	for g in gear:
		if int(g.id) == id: return g
	return {}
func gear_value(g: Dictionary) -> float:
	return float(K.gear.rarity_base[int(g.r)]) * (1.0 + float(K.gear.enhance_per_level) * int(g.lv))
func gear_stat(stat: String) -> float:
	var v := 0.0
	for slot in equipped:
		var g := gear_by_id(int(equipped[slot]))
		if not g.is_empty() and K.gear.slot_stat[slot] == stat: v += gear_value(g)
	return v
func set_count(set_id: String) -> int:
	var n := 0
	for slot in equipped:
		var g := gear_by_id(int(equipped[slot]))
		if not g.is_empty() and g.set == set_id: n += 1
	return n
## 2 pieces = half bonus, 4 pieces = full bonus.
func set_bonus(set_id: String) -> float:
	var n := set_count(set_id); var full: float = K.gear.sets[set_id].full
	return full if n >= 4 else (full * 0.5 if n >= 2 else 0.0)
func pet_v(stat: String) -> float:
	for p in K.pets.list:
		if p.stat == stat and active_pet == p.id: return float(p.per_level) * int(pets[p.id])
	return 0.0

func tap_mult() -> float:
	return (1.0 + gear_stat("tap")) * (1.0 + gear_stat("all")) * (1.0 + set_bonus("ember")) * (1.0 + pet_v("tap")) * (1.0 + tv("t_tap"))
func ally_mult() -> float:
	return (1.0 + gear_stat("ally")) * (1.0 + gear_stat("all")) * (1.0 + pet_v("ally")) * (1.0 + tv("t_ally"))
func gold_mult() -> float:
	return (1.0 + gear_stat("gold")) * (1.0 + set_bonus("verdant")) * (1.0 + pet_v("gold")) * (1.0 + tv("t_gold")) * festival_gold()
func crit_chance() -> float: return C.crit_chance + pet_v("crit") + tv("t_crit")
func crit_mult() -> float: return C.crit_mult * (1.0 + tv("t_critd"))
func cooldown_mult() -> float: return max(0.5, 1.0 - tv("t_cd"))
func pet_damage() -> float:
	if active_pet == "": return 0.0
	return tap_dmg() * (3.0 + int(pets[active_pet])) * (1.0 + set_bonus("storm")) * (1.0 + tv("t_pet"))
func festival() -> bool:
	var wd: int = Time.get_datetime_dict_from_system().weekday
	return wd == 0 or wd == 6
func festival_gold() -> float: return float(K.festival.gold_mult) if festival() else 1.0

## Rolls a gear piece. min_r forces at least that rarity (crafting).
func roll_gear(min_r := 0) -> Dictionary:
	if gear.size() >= int(K.gear.inventory_cap): return {}
	var w: Array = K.gear.rarity_weights; var tot := 0.0
	for x in w: tot += x
	var roll := randf() * tot; var r := 0
	for i in w.size():
		roll -= w[i]
		if roll <= 0: r = i; break
	r = max(r, min_r)
	var g := {"id": gear_uid, "slot": K.gear.slots[randi() % 4], "r": r, "set": K.gear.sets.keys()[randi() % 4], "lv": 0}
	gear_uid += 1; gear.append(g)
	if not equipped.has(g.slot): equipped[g.slot] = g.id
	if r == 3: unlock("legendary")
	changed.emit(); return g
func enhance_cost(g: Dictionary) -> int: return (int(g.lv) + 1) * int(K.gear.enhance_cost[int(g.r)])
func enhance(g: Dictionary) -> bool:
	var c := enhance_cost(g)
	if int(g.lv) >= int(K.gear.enhance_max) or essence < c: return false
	essence -= c; g.lv = int(g.lv) + 1; changed.emit(); save_game(); return true
func salvage(g: Dictionary) -> void:
	for slot in equipped.keys():
		if int(equipped[slot]) == int(g.id): equipped.erase(slot)
	essence += int(K.gear.salvage[int(g.r)]); gear.erase(g); changed.emit(); save_game()
func equip(g: Dictionary) -> void: equipped[g.slot] = int(g.id); changed.emit(); save_game()
func craft() -> Dictionary:
	if essence < int(K.gear.craft_cost) or gear.size() >= int(K.gear.inventory_cap): return {}
	essence -= int(K.gear.craft_cost); return roll_gear(1)

func pets_unlocked() -> bool: return max_stage >= int(K.pets.unlock_stage)
## Hatches one egg: +1 level for a random pet. Returns the pet id.
func hatch() -> String:
	if eggs <= 0: return ""
	eggs -= 1
	var p: Dictionary = K.pets.list[randi() % K.pets.list.size()]
	pets[p.id] = int(pets[p.id]) + 1
	if active_pet == "": active_pet = p.id
	unlock("first_pet"); changed.emit(); save_game(); return p.id

## Day rollover: streak, quests, raid tickets.
func new_day(today: String) -> void:
	if raid_day != today: raid_day = today; raid_tickets = int(K.raid.tickets)
	if quest_day != today:
		quest_day = today; quest_bonus = false; quests = []
		var pool: Array = K.quests.pool.duplicate(); pool.shuffle()
		for q in pool.slice(0, int(K.quests.per_day)): quests.append({"k": q.k, "goal": int(q.goal), "p": 0, "done": false})
	save_game()

func _yesterday() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)

## 7-day login calendar. Returns the reward dict granted today (empty if claimed already).
func claim_streak() -> Dictionary:
	var today := Time.get_date_string_from_system()
	if streak_day == today: return {}
	if streak_day != _yesterday() or streak >= 7: streak = 0
	var r: Dictionary = K.streak[streak]
	streak += 1; streak_day = today
	grant(r)
	if streak == 7: unlock("streak_7")
	return r

func grant(r: Dictionary) -> void:
	if r.has("gems"): gems += int(r.gems)
	if r.has("essence"): essence += int(r.essence)
	if r.has("eggs"): eggs += int(r.eggs)
	if r.has("warp_h"): gold += offline_income(float(r.warp_h) * 3600.0)
	gems_changed.emit(); changed.emit(); save_game()

## Quest progress hook.
func qp(kind: String, n := 1) -> void:
	for q in quests:
		if q.k == kind and not q.done:
			q.p = min(int(q.goal), int(q.p) + n)
			if int(q.p) >= int(q.goal):
				q.done = true
				grant({"gems": K.quests.reward_gems, "essence": K.quests.reward_essence})
				quest_done.emit(tr_("quest_done") % tr_("q_" + kind))
	if not quest_bonus and quests.size() > 0 and quests.all(func(q): return q.done):
		quest_bonus = true; grant({"eggs": K.quests.all_bonus_eggs}); unlock("quests_all")
		quest_done.emit(tr_("quest_all"))

## Raid score: tier*100 + percent into the next tier, for absolute damage dealt.
func raid_hp(k: int) -> float: return float(K.raid.tier_hp) * pow(float(K.raid.tier_growth), k)
func raid_score(total: float) -> int:
	var k := 0; var left := total
	while left >= raid_hp(k) and k < 2000: left -= raid_hp(k); k += 1
	return k * 100 + int(100.0 * left / raid_hp(k))
func raid_fmt(score: int) -> String: return "%d.%02d" % [score / 100, score % 100]
func raid_finish(score: int) -> Dictionary:
	var tier := score / 100
	var r := {"gems": int(K.raid.reward_gems_base) + tier, "essence": int(K.raid.reward_essence_base) + 2 * tier}
	if randf() < float(K.raid.egg_chance): r.eggs = 1
	raid_best = max(raid_best, score); stats.raids += 1
	if tier >= 10: unlock("raid_10")
	grant(r); qp("raid"); return r

## Wipes game progress (keeps settings, language and Play purchases so paid items are not lost).
func reset_all() -> void:
	var keep := {"owned": owned, "tokens": processed_tokens, "settings": settings, "lang": lang}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	from_dict(keep); offline_gold = 0.0; offline_full = false; auto_tap_left = 0.0
	if not owned.has(aura): aura = ""
	new_day(Time.get_date_string_from_system())

const SUF := ["", "K", "M", "B", "T"]
func fmt(x: float) -> String:
	if x < 1000: return str(int(x))
	var e := int(floor(log(x) / log(1000.0)))
	var m := x / pow(1000.0, e)
	var s: String
	if e < SUF.size(): s = SUF[e]
	else:
		var k := e - SUF.size()
		s = char(97 + (k / 26) % 26) + char(97 + k % 26)
	return ("%.2f" % m if m < 10 else "%.1f" % m if m < 100 else "%d" % int(m)) + s

var _i18n_extra := {}
func tr_(key: String) -> String:
	var d: Dictionary = I18N.get(key, _i18n_extra.get(key, {}))
	return d.get(lang, d.get("en", key))

const I18N := {
	"tab_shop": {"en": "Shop", "ru": "Лавка"},
	"gems": {"en": "Gems", "ru": "Самоцветы"},
	"play": {"en": "PLAY", "ru": "ИГРАТЬ"},
	"tap_skip": {"en": "Tap to skip", "ru": "Коснитесь, чтобы пропустить"},
	"subtitle": {"en": "Tap. Slay. Restore the Shard.", "ru": "Касайся. Сражайся. Верни Осколок."},
	"gsign": {"en": "Sign in with Google Play", "ru": "Войти через Google Play"},
	"gsigned": {"en": "Google Play Games: signed in", "ru": "Google Play Игры: вход выполнен"},
	"gunavail": {"en": "Google Play Games unavailable on this device/build", "ru": "Google Play Игры недоступны на этом устройстве/сборке"},
	"cloud_save": {"en": "Save to cloud", "ru": "Сохранить в облако"},
	"cloud_load": {"en": "Load from cloud", "ru": "Загрузить из облака"},
	"cloud_saved": {"en": "Saved to cloud", "ru": "Сохранено в облаке"},
	"cloud_found": {"en": "A cloud save with more progress was found (best stage %d). Load it?", "ru": "Найдено облачное сохранение с большим прогрессом (лучший этап %d). Загрузить?"},
	"cloud_none": {"en": "No cloud save found", "ru": "Облачное сохранение не найдено"},
	"yes": {"en": "Yes", "ru": "Да"}, "no": {"en": "No", "ru": "Нет"},
	"achievements": {"en": "Achievements", "ru": "Достижения"},
	"leaderboard": {"en": "Leaderboard", "ru": "Таблица рекордов"},
	"restore": {"en": "Restore purchases", "ru": "Восстановить покупки"},
	"restored": {"en": "Purchases restored", "ru": "Покупки восстановлены"},
	"billing_unavail": {"en": "Store unavailable. Purchases work only in the Google Play version.", "ru": "Магазин недоступен. Покупки работают только в версии из Google Play."},
	"buy_ok": {"en": "Thank you for your support!", "ru": "Спасибо за поддержку!"},
	"pending": {"en": "Payment pending. The reward arrives when it completes.", "ru": "Платёж обрабатывается. Награда придёт после завершения."},
	"owned": {"en": "OWNED", "ru": "КУПЛЕНО"},
	"p_gems_small": {"en": "Pouch of Gems: %d gems", "ru": "Мешочек самоцветов: %d"},
	"p_gems_medium": {"en": "Chest of Gems: %d gems", "ru": "Сундук самоцветов: %d"},
	"p_gems_large": {"en": "Dragon Hoard: %d gems", "ru": "Сокровища дракона: %d"},
	"p_starter_pack": {"en": "Supporter Pack: %d gems + Golden Aura + badge", "ru": "Набор покровителя: %d самоцветов + Золотая аура + значок"},
	"p_vip_pack": {"en": "Royal Treasury (VIP): permanent x2 gold", "ru": "Королевская казна (VIP): золото x2 навсегда"},
	"g_reset": {"en": "Refresh all spell cooldowns", "ru": "Сбросить перезарядку заклинаний"},
	"g_warp": {"en": "Time Warp: collect %dh of ally gold now", "ru": "Искажение времени: сразу получить золото за %d ч"},
	"g_auto": {"en": "Spirit Familiar: auto-tap %d/s for %d min", "ru": "Дух-фамильяр: автоатака %d/с на %d мин"},
	"g_aura_fire": {"en": "Ember Aura (cosmetic)", "ru": "Аура углей (внешний вид)"},
	"g_aura_frost": {"en": "Frost Aura (cosmetic)", "ru": "Аура инея (внешний вид)"},
	"g_aura_arcane": {"en": "Arcane Aura (cosmetic)", "ru": "Тайная аура (внешний вид)"},
	"g_aura_gold": {"en": "Golden Aura (supporters)", "ru": "Золотая аура (для покровителей)"},
	"equip": {"en": "Equip", "ru": "Надеть"}, "equipped": {"en": "Equipped", "ru": "Надето"},
	"premium": {"en": "Support the developer", "ru": "Поддержать разработчика"},
	"spend": {"en": "Spend gems", "ru": "Потратить самоцветы"},
	"daily": {"en": "Daily gift: +%d gems!", "ru": "Ежедневный подарок: +%d самоцветов!"},
	"ach_get": {"en": "Achievement: %s (+%d gems)", "ru": "Достижение: %s (+%d самоцветов)"},
	"ach_first_boss": {"en": "First Boss Slain", "ru": "Первый босс повержен"},
	"ach_stage_50": {"en": "Stage 50", "ru": "Этап 50"},
	"ach_stage_100": {"en": "Stage 100", "ru": "Этап 100"},
	"ach_stage_200": {"en": "Stage 200", "ru": "Этап 200"},
	"ach_first_prestige": {"en": "Shard Shatterer", "ru": "Раскалыватель Осколков"},
	"ach_all_allies": {"en": "Full Fellowship", "ru": "Полный отряд"},
	"ach_taps_10k": {"en": "10,000 Strikes", "ru": "10 000 ударов"},
	"level_up": {"en": "LEVEL UP!", "ru": "НОВЫЙ УРОВЕНЬ!"},
	"stage_clear": {"en": "Stage %d", "ru": "Этап %d"},
	"b_forest": {"en": "Whispering Woods", "ru": "Шепчущий лес"},
	"b_cave": {"en": "Crystal Depths", "ru": "Хрустальные глубины"},
	"b_lava": {"en": "Emberfall Wastes", "ru": "Пепельные пустоши"},
	"b_ice": {"en": "Frostcrown Peaks", "ru": "Вершины Ледяной Короны"},
	"prestige_done": {"en": "+%s Dragon Shards!", "ru": "+%s Драконьих Осколков!"},
	"vip": {"en": "VIP", "ru": "VIP"},
	"supporter": {"en": "Supporter", "ru": "Покровитель"},

	"title": {"en": "Dragonshard Legends", "ru": "Легенды Драконьего Осколка"},
	"stage": {"en": "Stage", "ru": "Этап"},
	"boss": {"en": "BOSS", "ru": "БОСС"},
	"fight_boss": {"en": "Fight Boss", "ru": "К боссу"},
	"tab_hero": {"en": "Hero", "ru": "Герой"},
	"tab_comp": {"en": "Allies", "ru": "Союзники"},
	"tab_art": {"en": "Shards", "ru": "Осколки"},
	"tab_set": {"en": "Settings", "ru": "Настройки"},
	"tap_dmg": {"en": "Tap damage", "ru": "Урон касанием"},
	"dps": {"en": "Allies DPS", "ru": "Урон союзников/с"},
	"lvl": {"en": "Lv", "ru": "Ур"},
	"buy": {"en": "Upgrade", "ru": "Улучшить"},
	"hire": {"en": "Hire", "ru": "Нанять"},
	"max": {"en": "MAX", "ru": "МАКС"},
	"sound": {"en": "Sound", "ru": "Звук"},
	"music": {"en": "Music", "ru": "Музыка"},
	"language": {"en": "Language: English", "ru": "Язык: Русский"},
	"on": {"en": "ON", "ru": "ВКЛ"}, "off": {"en": "OFF", "ru": "ВЫКЛ"},
	"prestige": {"en": "Shatter the Shard (Prestige)", "ru": "Расколоть Осколок (Престиж)"},
	"prestige_info": {"en": "Restart from stage 1, keep artifacts, gain %s Dragon Shards. Available from stage %d. Best this run: %d.", "ru": "Начать с 1 этапа, сохранив артефакты, и получить %s Драконьих Осколков. Доступно с %d этапа. Рекорд забега: %d."},
	"offline": {"en": "While you were away your allies earned %s gold!", "ru": "Пока вас не было, союзники добыли %s золота!"},
	"ok": {"en": "OK", "ru": "OK"},
	"unlock_at": {"en": "Unlocks at hero Lv %d", "ru": "Откроется на %d ур. героя"},
	"story": {"en": "The Dragon Shard that kept the realm of Elaria in peace has shattered. Monsters pour out of every biome. Gather allies, master spells and recover the shards, Shardbearer!", "ru": "Драконий Осколок, хранивший мир Эларии, раскололся. Из всех земель хлынули чудовища. Собери союзников, освой заклинания и верни осколки, Хранитель!"},
	"privacy": {"en": "Privacy: the game itself collects no personal data. Progress is stored on your device and, if you sign in, in your Google Play Games cloud save. Purchases are processed by Google Play.", "ru": "Конфиденциальность: игра сама не собирает личные данные. Прогресс хранится на устройстве и, при входе, в облаке Google Play Игр. Покупки обрабатывает Google Play."},
	"best": {"en": "Best stage", "ru": "Лучший этап"},
	"failed": {"en": "The boss escaped!", "ru": "Босс ускользнул!"},
	"c1": {"en": "Lirael the Archer", "ru": "Лираэль-Лучница"},
	"c2": {"en": "Borin Ironbeard", "ru": "Борин Железнобородый"},
	"c3": {"en": "Embra Flamecaller", "ru": "Эмбра Огнезовущая"},
	"c4": {"en": "Vex Shadowstep", "ru": "Векс Теневой Шаг"},
	"c5": {"en": "Sir Aurel of the Sun", "ru": "Сэр Аурел Солнечный"},
	"c6": {"en": "Thornwyn the Druid", "ru": "Торнвин-Друид"},
	"c7": {"en": "Kael Dragonrider", "ru": "Каэль Всадник Драконов"},
	"c8": {"en": "Nyssa Stormweaver", "ru": "Нисса Ткачиха Бурь"},
	"s_blade": {"en": "Shard Blade", "ru": "Клинок Осколка"},
	"s_rage": {"en": "Berserk Rage", "ru": "Ярость берсерка"},
	"s_haste": {"en": "Arcane Haste", "ru": "Тайная спешка"},
	"s_meteor": {"en": "Meteor Call", "ru": "Зов метеора"},
	"s_goldrain": {"en": "Golden Rain", "ru": "Золотой дождь"},
	"s_ward": {"en": "Time Ward", "ru": "Печать времени"},
	"a_heart": {"en": "Dragon Heart: all damage x%s", "ru": "Сердце дракона: весь урон x%s"},
	"a_gauntlet": {"en": "Titan Gauntlet: tap damage x%s", "ru": "Перчатка титана: урон касанием x%s"},
	"a_crown": {"en": "Miser's Crown: gold x%s", "ru": "Корона скряги: золото x%s"},
	"a_hourglass": {"en": "Sand Hourglass: boss time +%ss", "ru": "Песочные часы: время босса +%sс"},
	"a_moonwell": {"en": "Moonwell: offline gold x%s", "ru": "Лунный колодец: офлайн-золото x%s"},
	"a_wings": {"en": "Wyvern Wings: start at stage +%s", "ru": "Крылья виверны: старт с этапа +%s"},
}
