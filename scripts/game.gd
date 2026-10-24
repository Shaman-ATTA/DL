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
const SAVE := "user://save.json"

func _ready() -> void:
	C = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	comp.resize(C.companions.size()); comp.fill(0)
	for a in C.artifacts: art[a.id] = 0
	if OS.get_locale_language() != "ru": lang = "en"
	load_game()

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
	return C.companions[i].base_dps * l * comp_mult(l) * artv("heart")

func dps() -> float:
	var t := 0.0
	for i in comp.size(): t += comp_dps(i)
	return t

func tap_dmg(l: int = -1) -> float:
	if l < 0: l = hero_lv
	var h: Dictionary = C.hero
	return l * h.dmg_per_level * pow(h.milestone_mult, l / int(h.milestone_every)) * artv("gauntlet") * artv("heart") + dps() * h.dps_to_tap_share

func hero_cost(l: int = -1) -> float:
	if l < 0: l = hero_lv
	return ceil(C.hero.base_cost * pow(C.hero.cost_growth, l - 1))

func comp_cost(i: int) -> float:
	return ceil(C.companions[i].base_cost * pow(C.companion_cost_growth, comp[i]))

func gold_kill(s: int, boss := false) -> float:
	var g: float = hp(s) * C.gold_per_hp * artv("crown")
	return g * (C.boss_gold_mult if boss else 1.0)

func boss_time() -> float: return C.boss_time + artv("hourglass")

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
	gold -= c; hero_lv += 1; changed.emit(); return true

func buy_comp(i: int) -> bool:
	var c := comp_cost(i)
	if gold < c: return false
	gold -= c; comp[i] += 1; changed.emit(); return true

func buy_art(id: String) -> bool:
	var a := art_def(id); var c := art_cost(id)
	if shards < c or art[id] >= a.max: return false
	shards -= c; art[id] += 1; changed.emit(); return true

func prestige() -> int:
	var s := shards_for(run_max)
	if s <= 0: return 0
	shards += s; gold = 0; hero_lv = 1; comp.fill(0)
	stage = 1 + int(artv("start_stage")); run_max = stage; kills = 0
	changed.emit(); save_game(); return s

func save_game() -> void:
	var d := {"v": 1, "gold": gold, "shards": shards, "hero": hero_lv, "comp": comp, "art": art,
		"stage": stage, "max": max_stage, "run_max": run_max, "taps": total_taps, "snd": sound_on,
		"mus": music_on, "lang": lang, "t": Time.get_unix_time_from_system()}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if typeof(d) != TYPE_DICTIONARY: return
	gold = d.get("gold", 0.0); shards = int(d.get("shards", 0)); hero_lv = int(d.get("hero", 1))
	var cs: Array = d.get("comp", [])
	for i in min(cs.size(), comp.size()): comp[i] = int(cs[i])
	var ar: Dictionary = d.get("art", {})
	for k in ar: if art.has(k): art[k] = int(ar[k])
	stage = int(d.get("stage", 1)); max_stage = int(d.get("max", 1)); run_max = int(d.get("run_max", stage))
	total_taps = int(d.get("taps", 0)); sound_on = d.get("snd", true); music_on = d.get("mus", true); lang = d.get("lang", lang)
	var dt: float = clamp(Time.get_unix_time_from_system() - float(d.get("t", 0)), 0, C.offline_cap_hours * 3600.0)
	var d_ := dps()
	if dt > 60 and d_ > 0:
		var kt: float = max(hp(stage) / d_, C.respawn_delay)
		offline_gold = dt / kt * gold_kill(stage) * C.offline_gold_factor * artv("moonwell")
		gold += offline_gold

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()

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

func tr_(key: String) -> String:
	var d: Dictionary = I18N.get(key, {})
	return d.get(lang, d.get("en", key))

const I18N := {
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
	"privacy": {"en": "Privacy: the game collects no personal data. Progress is stored only on your device.", "ru": "Конфиденциальность: игра не собирает личные данные. Прогресс хранится только на устройстве."},
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
