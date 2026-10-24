extends Control
## Main screen: battle, skills, tabs. UI built in code for a single portable scene.
const BIOMES := ["forest", "cave", "lava", "ice"]
const MOBS := {"forest": ["slime", "mushroom", "goblin"], "cave": ["golem", "goblin", "wraith"],
	"lava": ["salamander", "golem", "mushroom"], "ice": ["wraith", "slime", "golem"]}
const BOSSES := ["boss_dragon", "boss_frostking", "boss_lich"]
var G
var bg: TextureRect
var battle: Control
var enemy: TextureRect
var hero: TextureRect
var hp_bar: ProgressBar
var hp_lbl: Label
var stage_lbl: Label
var gold_lbl: Label
var shard_lbl: Label
var timer_lbl: Label
var boss_btn: Button
var tab_box: VBoxContainer
var cur_tab := 0
var tab_btns: Array = []
var skill_btns: Dictionary = {}
var skill_cd: Dictionary = {}
var skill_active: Dictionary = {}
var enemy_hp := 1.0
var enemy_max := 1.0
var boss := false
var boss_left := 0.0
var farming := false
var respawn := 0.0
var haste_acc := 0.0
var save_acc := 0.0
var ui_acc := 0.0
var shake := 0.0
var sfx := {}
var music: AudioStreamPlayer
var row_updaters: Array = []
var tex_cache := {}

func tex(p: String) -> Texture2D:
	if not tex_cache.has(p): tex_cache[p] = load(p)
	return tex_cache[p]

func _ready() -> void:
	G = Game
	var th := Theme.new(); th.default_font_size = 38
	theme = th
	_build()
	for s in ["tap", "crit", "coin", "boss", "level", "skill"]:
		var p := AudioStreamPlayer.new(); p.stream = load("res://assets/audio/%s.wav" % s); add_child(p); sfx[s] = p
	music = AudioStreamPlayer.new(); music.stream = load("res://assets/audio/music.wav"); music.volume_db = -14; add_child(music)
	music.finished.connect(func(): if G.music_on: music.play())
	if G.music_on: music.play()
	for k in G.C.skills: skill_cd[k.id] = 0.0; skill_active[k.id] = 0.0
	G.changed.connect(_refresh_tab)
	spawn()
	_show_tab(0)
	if G.offline_gold > 0:
		popup(G.tr_("offline") % G.fmt(G.offline_gold))
	elif G.total_taps == 0:
		popup(G.tr_("story"))

func play(s: String) -> void:
	if G.sound_on and sfx.has(s):
		sfx[s].pitch_scale = randf_range(0.9, 1.1); sfx[s].play()

func _lbl(t: String, size := 38, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", 10)
	return l

func _panel(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = col
	sb.set_corner_radius_all(18); sb.border_color = Color(0.95, 0.75, 0.3); sb.set_border_width_all(4)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	return sb

func _btn(t: String, col := Color(0.55, 0.25, 0.1)) -> Button:
	var b := Button.new(); b.text = t
	b.add_theme_stylebox_override("normal", _panel(col))
	b.add_theme_stylebox_override("hover", _panel(col.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _panel(col.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", _panel(Color(0.3, 0.3, 0.3)))
	b.add_theme_font_size_override("font_size", 34)
	return b

func _build() -> void:
	battle = Control.new(); battle.position = Vector2(0, 0); battle.size = Vector2(1080, 1180)
	battle.mouse_filter = Control.MOUSE_FILTER_STOP; battle.clip_contents = true
	add_child(battle)
	battle.gui_input.connect(_on_battle_input)
	bg = TextureRect.new(); bg.size = Vector2(1080, 1920); bg.position = Vector2(0, -300)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.add_child(bg)
	enemy = TextureRect.new(); enemy.size = Vector2(560, 560); enemy.position = Vector2(400, 420)
	enemy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; enemy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy.pivot_offset = Vector2(280, 560); enemy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.add_child(enemy)
	hero = TextureRect.new(); hero.texture = tex("res://assets/sprites/hero.png"); hero.size = Vector2(400, 460)
	hero.position = Vector2(20, 640); hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.pivot_offset = Vector2(200, 460)
	battle.add_child(hero)
	# top bar
	var top := PanelContainer.new(); top.position = Vector2(0, 0); top.size = Vector2(1080, 110)
	top.add_theme_stylebox_override("panel", _panel(Color(0.12, 0.06, 0.16, 0.85))); top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var hb := HBoxContainer.new(); top.add_child(hb); hb.add_theme_constant_override("separation", 12)
	var ci := TextureRect.new(); ci.texture = tex("res://assets/ui/coin.png"); ci.custom_minimum_size = Vector2(70, 70)
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; hb.add_child(ci)
	gold_lbl = _lbl("0", 52, Color(1, 0.85, 0.3)); gold_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(gold_lbl)
	var si := TextureRect.new(); si.texture = tex("res://assets/ui/shard.png"); si.custom_minimum_size = Vector2(60, 60)
	si.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; si.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; hb.add_child(si)
	shard_lbl = _lbl("0", 44, Color(0.6, 0.85, 1)); hb.add_child(shard_lbl)
	stage_lbl = _lbl("", 44); stage_lbl.position = Vector2(0, 130); stage_lbl.size = Vector2(1080, 60)
	stage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stage_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(stage_lbl)
	hp_bar = ProgressBar.new(); hp_bar.position = Vector2(140, 200); hp_bar.size = Vector2(800, 50); hp_bar.show_percentage = false
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.85, 0.15, 0.2); fill.set_corner_radius_all(12)
	var back := StyleBoxFlat.new(); back.bg_color = Color(0.1, 0.05, 0.05, 0.8); back.set_corner_radius_all(12)
	back.border_color = Color(0.95, 0.75, 0.3); back.set_border_width_all(3)
	hp_bar.add_theme_stylebox_override("fill", fill); hp_bar.add_theme_stylebox_override("background", back)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hp_bar)
	hp_lbl = _lbl("", 32); hp_lbl.position = Vector2(140, 200); hp_lbl.size = Vector2(800, 50)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hp_lbl)
	timer_lbl = _lbl("", 48, Color(1, 0.4, 0.3)); timer_lbl.position = Vector2(0, 260); timer_lbl.size = Vector2(1080, 60)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; timer_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(timer_lbl)
	boss_btn = _btn("", Color(0.7, 0.1, 0.15)); boss_btn.position = Vector2(760, 270); boss_btn.size = Vector2(300, 90)
	boss_btn.pressed.connect(func(): farming = false; boss_btn.visible = false; spawn())
	boss_btn.visible = false; add_child(boss_btn)
	# skill bar
	var sk := HBoxContainer.new(); sk.position = Vector2(15, 1190); sk.size = Vector2(1050, 170)
	sk.add_theme_constant_override("separation", 12); add_child(sk)
	for k in G.C.skills:
		var b := Button.new(); b.custom_minimum_size = Vector2(165, 165); b.icon = tex("res://assets/ui/skill_%s.png" % k.id)
		b.expand_icon = true; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_stylebox_override("normal", _panel(Color(0.2, 0.1, 0.3)))
		b.add_theme_stylebox_override("disabled", _panel(Color(0.15, 0.15, 0.15, 0.9)))
		b.add_theme_font_size_override("font_size", 40)
		b.add_theme_color_override("font_disabled_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color.BLACK); b.add_theme_constant_override("outline_size", 10)
		b.pressed.connect(_use_skill.bind(k))
		sk.add_child(b); skill_btns[k.id] = b
	# tab content
	var pc := PanelContainer.new(); pc.position = Vector2(0, 1370); pc.size = Vector2(1080, 430)
	pc.add_theme_stylebox_override("panel", _panel(Color(0.16, 0.09, 0.2, 0.97))); add_child(pc)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pc.add_child(sc)
	tab_box = VBoxContainer.new(); tab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_box.add_theme_constant_override("separation", 10); sc.add_child(tab_box)
	var tb := HBoxContainer.new(); tb.position = Vector2(0, 1805); tb.size = Vector2(1080, 115)
	tb.add_theme_constant_override("separation", 6); add_child(tb)
	for i in 4:
		var b := _btn("", Color(0.35, 0.18, 0.45)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 110); b.pressed.connect(_show_tab.bind(i)); tb.add_child(b); tab_btns.append(b)

func _tab_names() -> void:
	var keys := ["tab_hero", "tab_comp", "tab_art", "tab_set"]
	for i in 4: tab_btns[i].text = G.tr_(keys[i])
	boss_btn.text = G.tr_("fight_boss")

func biome() -> String: return BIOMES[((G.stage - 1) / 10) % BIOMES.size()]

func spawn() -> void:
	var n: int = G.C.enemies_per_stage
	boss = (G.kills >= n) and not farming
	enemy_max = G.hp(G.stage) * (G.C.boss_hp_mult if boss else 1.0)
	enemy_hp = enemy_max
	bg.texture = tex("res://assets/bg/%s.jpg" % biome())
	var id: String = BOSSES[(G.stage / 5) % BOSSES.size()] if boss else MOBS[biome()][randi() % 3]
	enemy.texture = tex("res://assets/sprites/%s.png" % id)
	enemy.scale = Vector2(1.25, 1.25) if boss else Vector2.ONE
	enemy.position = Vector2(380, 360) if boss else Vector2(420, 460)
	enemy.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(enemy, "modulate", Color.WHITE, 0.2)
	if boss: boss_left = G.boss_time(); play("boss")
	_update_hud()

func _on_battle_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed:
		tap(e.position)


func rage_mult() -> float:
	return _skill("rage").power if skill_active.get("rage", 0.0) > 0 else 1.0

func _skill(id: String) -> Dictionary:
	for k in G.C.skills:
		if k.id == id: return k
	return {}

func tap(pos: Vector2, silent := false) -> void:
	if respawn > 0: return
	G.total_taps += 1
	var d: float = G.tap_dmg() * rage_mult()
	var crit: bool = randf() < G.C.crit_chance
	if crit: d *= G.C.crit_mult
	damage(d, pos, crit)
	if not silent:
		play("crit" if crit else "tap")
		var tw := create_tween(); tw.tween_property(hero, "rotation", 0.15, 0.05); tw.tween_property(hero, "rotation", 0.0, 0.08)

func damage(d: float, pos: Vector2, crit := false, col := Color.WHITE) -> void:
	if respawn > 0: return
	enemy_hp -= d
	_float_text(G.fmt(d), pos, Color(1, 0.3, 0.2) if crit else col, 72 if crit else 50)
	enemy.self_modulate = Color(3, 3, 3)
	var tw := create_tween(); tw.tween_property(enemy, "self_modulate", Color.WHITE, 0.12)
	var sq := create_tween(); var base_s: Vector2 = enemy.scale
	sq.tween_property(enemy, "scale", base_s * Vector2(1.08, 0.92), 0.05); sq.tween_property(enemy, "scale", base_s, 0.08)
	if crit: shake = 0.25
	if enemy_hp <= 0: kill()

func _float_text(t: String, pos: Vector2, col: Color, size: int) -> void:
	var l := _lbl(t, size, col); l.position = pos + Vector2(randf_range(-60, 20), -60)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; battle.add_child(l)
	var tw := create_tween().set_parallel(); tw.tween_property(l, "position:y", l.position.y - 180, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

func kill() -> void:
	var g: float = G.gold_kill(G.stage, boss) * (_skill("goldrain").power if skill_active.get("goldrain", 0.0) > 0 else 1.0)
	G.gold += g
	_coins(int(clamp(log(g + 1) / 2, 3, 12)))
	play("coin")
	var tw := create_tween(); tw.tween_property(enemy, "modulate", Color(1, 1, 1, 0), 0.25)
	if boss:
		G.stage += 1; G.kills = 0; boss = false
		G.run_max = max(G.run_max, G.stage); G.max_stage = max(G.max_stage, G.stage); play("level")
	else:
		G.kills += 1
	respawn = G.C.respawn_delay

func _coins(n: int) -> void:
	for i in n:
		var c := TextureRect.new(); c.texture = tex("res://assets/ui/coin.png"); c.size = Vector2(64, 64)
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = enemy.position + Vector2(280, 400) + Vector2(randf_range(-120, 120), randf_range(-60, 60))
		add_child(c)
		var tw := create_tween()
		tw.tween_property(c, "position", c.position + Vector2(randf_range(-100, 100), randf_range(-160, -60)), 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", Vector2(40, 20), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(c.queue_free)

func _use_skill(k: Dictionary) -> void:
	if skill_cd[k.id] > 0 or G.hero_lv < k.unlock_level: return
	skill_cd[k.id] = k.cooldown; play("skill")
	match k.id:
		"blade":
			damage(G.tap_dmg() * k.power, Vector2(500, 600), true, Color(0.6, 0.9, 1)); shake = 0.4
		"ward":
			if boss: boss_left += 15
			else: skill_cd[k.id] = 0
		_:
			skill_active[k.id] = k.duration

func _process(dt: float) -> void:
	for id in skill_cd:
		skill_cd[id] = max(0.0, skill_cd[id] - dt); skill_active[id] = max(0.0, skill_active[id] - dt)
	if respawn > 0:
		respawn -= dt
		if respawn <= 0: spawn()
	else:
		var dmul: float = _skill("meteor").power if skill_active["meteor"] > 0 else 1.0
		var d: float = G.dps() * dmul * dt
		if d > 0:
			enemy_hp -= d
			if enemy_hp <= 0: kill()
		if skill_active["haste"] > 0:
			haste_acc += dt * _skill("haste").power
			while haste_acc >= 1: haste_acc -= 1; tap(Vector2(randf_range(450, 800), randf_range(500, 800)), true)
		if boss and respawn <= 0:
			boss_left -= dt
			if boss_left <= 0:
				farming = true; G.kills = 0; boss_btn.visible = true
				_float_text(G.tr_("failed"), Vector2(300, 500), Color(1, 0.4, 0.3), 64); spawn()
	if shake > 0:
		shake -= dt; battle.position = Vector2(randf_range(-14, 14), randf_range(-14, 14)) if shake > 0 else Vector2.ZERO
	ui_acc += dt
	if ui_acc > 0.15: ui_acc = 0; _update_hud()
	save_acc += dt
	if save_acc > 10: save_acc = 0; G.save_game()

func _update_hud() -> void:
	gold_lbl.text = G.fmt(G.gold); shard_lbl.text = G.fmt(G.shards)
	var n: int = G.C.enemies_per_stage
	stage_lbl.text = "%s %d  %s" % [G.tr_("stage"), G.stage, (G.tr_("boss") if boss else "%d/%d" % [min(G.kills, n), n])]
	hp_bar.max_value = 1000; hp_bar.value = 1000 * max(enemy_hp, 0) / enemy_max
	hp_lbl.text = "%s / %s" % [G.fmt(max(enemy_hp, 0)), G.fmt(enemy_max)]
	timer_lbl.text = ("%.1f" % boss_left) if boss else ""
	for k in G.C.skills:
		var b: Button = skill_btns[k.id]
		var locked: bool = G.hero_lv < k.unlock_level
		b.disabled = locked or skill_cd[k.id] > 0
		b.text = ("%d" % k.unlock_level) if locked else ("%d" % ceil(skill_cd[k.id]) if skill_cd[k.id] > 0 else "")
		b.modulate = Color(1, 1, 0.6) if skill_active[k.id] > 0 else Color.WHITE
	for u in row_updaters: u.call()

func _show_tab(i: int) -> void:
	cur_tab = i
	for j in 4: tab_btns[j].modulate = Color(1.3, 1.2, 0.8) if j == i else Color.WHITE
	_refresh_tab(true)

var _last_sig := ""
func _refresh_tab(force := false) -> void:
	# rebuild only when the set of rows changes (tab switch / hire / language)
	var sig := "%d|%s|%d" % [cur_tab, G.lang, G.comp.count(0)]
	if not force and sig == _last_sig: return
	_last_sig = sig
	_tab_names()
	for c in tab_box.get_children(): c.queue_free()
	row_updaters.clear()
	match cur_tab:
		0: _tab_hero()
		1: _tab_comp()
		2: _tab_art()
		3: _tab_settings()
	_update_hud()

func _row(icon: Texture2D, on_buy: Callable) -> Array:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 14); tab_box.add_child(hb)
	var ic := TextureRect.new(); ic.texture = icon; ic.custom_minimum_size = Vector2(120, 120)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; hb.add_child(ic)
	var l := _lbl("", 32); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hb.add_child(l)
	var b := _btn("", Color(0.2, 0.5, 0.15)); b.custom_minimum_size = Vector2(300, 110); b.pressed.connect(on_buy); hb.add_child(b)
	return [l, b]

func _tab_hero() -> void:
	var r := _row(tex("res://assets/sprites/hero.png"), func(): if G.buy_hero(): play("level"))
	row_updaters.append(func():
		r[0].text = "%s  %s %d\n%s: %s\n%s: %s" % [G.tr_("title"), G.tr_("lvl"), G.hero_lv, G.tr_("tap_dmg"), G.fmt(G.tap_dmg()), G.tr_("dps"), G.fmt(G.dps())]
		r[1].text = "%s\n%s" % [G.tr_("buy"), G.fmt(G.hero_cost())]; r[1].disabled = G.gold < G.hero_cost())
	for k in G.C.skills:
		var l := _lbl("", 30); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(l)
		l.text = "• %s — %s" % [G.tr_("s_" + k.id), G.tr_("unlock_at") % k.unlock_level]

func _tab_comp() -> void:
	for i in G.C.companions.size():
		var id: String = G.C.companions[i].id
		var r := _row(tex("res://assets/portraits/%s.png" % id), func(): if G.buy_comp(i): play("coin"))
		row_updaters.append(func():
			var l: int = G.comp[i]
			r[0].text = "%s  %s %d\nDPS: %s" % [G.tr_(id), G.tr_("lvl"), l, G.fmt(G.comp_dps(i))]
			r[1].text = "%s\n%s" % [G.tr_("hire") if l == 0 else G.tr_("buy"), G.fmt(G.comp_cost(i))]
			r[1].disabled = G.gold < G.comp_cost(i))
		if G.comp[i] == 0: break  # reveal companions one at a time

func _tab_art() -> void:
	var pb := _btn("", Color(0.45, 0.15, 0.6)); pb.custom_minimum_size = Vector2(0, 100); tab_box.add_child(pb)
	var info := _lbl("", 28); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(info)
	pb.pressed.connect(func():
		var s: int = G.prestige()
		if s > 0: play("boss"); farming = false; boss_btn.visible = false; spawn(); _refresh_tab(true))
	row_updaters.append(func():
		var s: int = G.shards_for(G.run_max)
		pb.text = G.tr_("prestige"); pb.disabled = s <= 0
		info.text = G.tr_("prestige_info") % [G.fmt(s), G.C.prestige.min_stage, G.run_max])
	for a in G.C.artifacts:
		var id: String = a.id
		var r := _row(tex("res://assets/ui/shard.png"), func(): if G.buy_art(id): play("level"))
		row_updaters.append(func():
			var v: float = G.artv(id)
			var vs: String = ("%d" % int(v)) if a.effect in ["boss_time", "start_stage"] else G.fmt(v) if v >= 1000 else "%.2f" % v
			r[0].text = "%s\n%s %d/%d" % [G.tr_("a_" + id) % vs, G.tr_("lvl"), G.art[id], a.max]
			var maxed: bool = G.art[id] >= a.max
			r[1].text = G.tr_("max") if maxed else "%s\n%s" % [G.tr_("buy"), G.fmt(G.art_cost(id))]
			r[1].disabled = maxed or G.shards < G.art_cost(id))

func _tab_settings() -> void:
	var sb := _btn(""); tab_box.add_child(sb)
	var mb := _btn(""); tab_box.add_child(mb)
	var lb := _btn(""); tab_box.add_child(lb)
	sb.pressed.connect(func(): G.sound_on = not G.sound_on; G.save_game())
	mb.pressed.connect(func():
		G.music_on = not G.music_on; G.save_game()
		if G.music_on: music.play()
		else: music.stop())
	lb.pressed.connect(func(): G.lang = "en" if G.lang == "ru" else "ru"; G.save_game(); _refresh_tab(true))
	var st := _lbl("", 28); st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(st)
	row_updaters.append(func():
		sb.text = "%s: %s" % [G.tr_("sound"), G.tr_("on") if G.sound_on else G.tr_("off")]
		mb.text = "%s: %s" % [G.tr_("music"), G.tr_("on") if G.music_on else G.tr_("off")]
		lb.text = G.tr_("language")
		st.text = "%s: %d\n\n%s\n\n%s\nv1.0.0" % [G.tr_("best"), G.max_stage, G.tr_("story"), G.tr_("privacy")])

func popup(t: String) -> void:
	var p := PanelContainer.new(); p.position = Vector2(90, 600); p.custom_minimum_size = Vector2(900, 0); p.size = Vector2(900, 400)
	p.add_theme_stylebox_override("panel", _panel(Color(0.18, 0.08, 0.25, 0.97))); add_child(p)
	var v := VBoxContainer.new(); p.add_child(v); v.add_theme_constant_override("separation", 20)
	var l := _lbl(t, 40); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size = Vector2(860, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(l)
	var b := _btn(G.tr_("ok"), Color(0.2, 0.5, 0.15)); b.custom_minimum_size = Vector2(0, 100); v.add_child(b)
	b.pressed.connect(p.queue_free)

## Dev-only: `godot -- --shot=<file>,<tab>,<stage>,<hero>` renders a store screenshot.
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var p: PackedStringArray = a.substr(7).split(",")
			call_deferred("_shot", p[0], int(p[1]), int(p[2]), int(p[3]))

func _shot(path: String, tab: int, st: int, hl: int) -> void:
	set_process(false)
	G.lang = OS.get_cmdline_user_args()[0].split(",")[4]
	G.stage = st; G.run_max = st + 8; G.hero_lv = hl; G.offline_gold = 0
	for i in G.comp.size(): G.comp[i] = max(0, hl - 25 * i)
	G.gold = G.hp(st) * 40; G.shards = 340; G.kills = 10 if tab == 2 else 6
	for c in get_children(): if c is PanelContainer and c.position.y == 600: c.queue_free()
	for k in G.C.skills: skill_cd[k.id] = 0.0
	spawn(); _show_tab(tab)
	if tab == 1: skill_active["rage"] = 10; skill_cd["rage"] = 100; skill_cd["blade"] = 12
	for i in 30: await get_tree().process_frame
	enemy.modulate = Color.WHITE
	for i in 4: _float_text(G.fmt(G.tap_dmg() * (8 if i == 2 else 1)), Vector2(520 + i * 90, 640 - i * 40), Color(1, 0.3, 0.2) if i == 2 else Color.WHITE, 72 if i == 2 else 50)
	_coins(6)
	enemy_hp = enemy_max * 0.62
	if boss: boss_left = 17.4
	_update_hud()
	for i in 9: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
