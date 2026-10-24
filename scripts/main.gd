extends Control
## Main screen: battle, skills, tabs. UI is built in code; effects use pooled nodes.
const BIOMES := ["forest", "cave", "lava", "ice"]
const MOBS := {"forest": ["slime", "mushroom", "goblin"], "cave": ["golem", "goblin", "wraith"],
	"lava": ["salamander", "golem", "mushroom"], "ice": ["wraith", "slime", "golem"]}
const BOSSES := ["boss_dragon", "boss_frostking", "boss_lich"]
const BIOME_TINT := {"forest": Color(0.7, 1, 0.6), "cave": Color(0.6, 0.8, 1), "lava": Color(1, 0.55, 0.2), "ice": Color(0.85, 0.95, 1)}
const AURAS := {"aura_fire": Color(1, 0.45, 0.1), "aura_frost": Color(0.5, 0.85, 1), "aura_arcane": Color(0.8, 0.4, 1), "aura_gold": Color(1, 0.85, 0.3)}
const TAB_KEYS := ["tab_hero", "tab_comp", "tab_art", "tab_shop", "tab_set"]
const ENEMY_BASE := Vector2(420, 460)
const HERO_BASE := Vector2(20, 640)
var G
var bg: TextureRect
var bg2: TextureRect
var battle: Control
var enemy_holder: Control
var enemy: TextureRect
var enemy_mat: ShaderMaterial
var hero_holder: Control
var hero: TextureRect
var slash: TextureRect
var hp_bar: ProgressBar
var hp_lbl: Label
var stage_lbl: Label
var gold_lbl: Label
var shard_lbl: Label
var gem_lbl: Label
var timer_lbl: Label
var boss_btn: Button
var tab_panel: PanelContainer
var tab_scroll: ScrollContainer
var tab_box: VBoxContainer
var tab_hl: Panel
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
var auto_acc := 0.0
var save_acc := 0.0
var ui_acc := 0.0
var shake := 0.0
var t := 0.0
var cur_biome := ""
var sfx := {}
var music: AudioStreamPlayer
var row_updaters: Array = []
var tex_cache := {}
# pools (no per-hit allocations)
var dmg_pool: Array[Label] = []
var dmg_i := 0
var coin_pool: Array[TextureRect] = []
var coin_i := 0
var hit_fx: CPUParticles2D
var death_fx: CPUParticles2D
var level_fx: CPUParticles2D
var prestige_fx: CPUParticles2D
var ambient: CPUParticles2D
var aura_fx: CPUParticles2D
var vignette: TextureRect
var overlay: ColorRect
var banner: Label
var toast_lbl: Label
var toast_tw: Tween
var dying := false

func tex(p: String) -> Texture2D:
	if not tex_cache.has(p): tex_cache[p] = load(p)
	return tex_cache[p]

func _ready() -> void:
	G = Game
	theme = UI.make_theme()
	_build()
	for s in ["tap", "crit", "coin", "boss", "level", "skill", "levelup", "prestige", "dissolve", "click", "whoosh"]:
		var p := AudioStreamPlayer.new(); p.stream = load("res://assets/audio/%s.wav" % s); add_child(p); sfx[s] = p
	sfx["click"].volume_db = -6
	music = AudioStreamPlayer.new(); music.stream = load("res://assets/audio/music.ogg"); music.volume_db = -14; add_child(music)
	music.finished.connect(func(): if G.music_on: music.play())
	if G.music_on: music.play()
	for k in G.C.skills: skill_cd[k.id] = 0.0; skill_active[k.id] = 0.0
	G.changed.connect(_refresh_tab)
	G.click.connect(func(): play("click", false))
	G.gems_changed.connect(_gems_pop)
	G.achievement.connect(func(k: String): toast(G.tr_("ach_get") % [G.tr_("ach_" + k), int(G.S.gems.achievement_reward)]))
	Online.toast.connect(toast)
	Online.status_changed.connect(func(): _refresh_tab(true))
	Online.cloud_conflict.connect(_ask_cloud)
	Online.purchase_granted.connect(func(_p): _celebrate(prestige_fx, Color(1, 0.85, 0.3)); _update_aura())
	_update_aura()
	spawn()
	_show_tab(0, true)
	# entrance: fade from black
	overlay.color = Color(0, 0, 0, 1)
	create_tween().tween_property(overlay, "color:a", 0.0, 0.5)
	var daily: int = G.claim_daily()
	if G.offline_gold > 0:
		popup(G.tr_("offline") % G.fmt(G.offline_gold))
	elif G.total_taps == 0:
		popup(G.tr_("story"))
	if daily > 0: toast(G.tr_("daily") % daily)

func play(s: String, vary := true) -> void:
	if G.sound_on and sfx.has(s):
		sfx[s].pitch_scale = randf_range(0.9, 1.1) if vary else 1.0; sfx[s].play()

func _lbl(t_: String, size := 38, col := Color.WHITE) -> Label: return UI.lbl(t_, size, col)
func _btn(t_: String, col := Color(0.55, 0.25, 0.1)) -> Button: return UI.btn(t_, col)
func _tr(c: Control) -> Control: c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c

func _sprite(path: String, sz: Vector2) -> TextureRect:
	var r := TextureRect.new(); if path != "": r.texture = tex(path)
	r.size = sz; r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build() -> void:
	battle = Control.new(); battle.size = Vector2(1080, 1180)
	battle.mouse_filter = Control.MOUSE_FILTER_STOP; battle.clip_contents = true
	add_child(battle); battle.gui_input.connect(_on_battle_input)
	bg = _sprite("", Vector2(1180, 1920)); bg.position = Vector2(-50, -300); bg.stretch_mode = TextureRect.STRETCH_SCALE; battle.add_child(bg)
	bg2 = _sprite("", Vector2(1180, 1920)); bg2.position = Vector2(-50, -300); bg2.stretch_mode = TextureRect.STRETCH_SCALE; bg2.modulate.a = 0; battle.add_child(bg2)
	ambient = UI.particles(tex("res://assets/ui/dot.png"), 40, 7.0, Color(1, 1, 1, 0.7), false)
	ambient.position = Vector2(540, 1200); ambient.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ambient.emission_rect_extents = Vector2(560, 10); ambient.gravity = Vector2(0, -25); ambient.spread = 30
	ambient.initial_velocity_min = 40; ambient.initial_velocity_max = 140; ambient.preprocess = 5; ambient.emitting = true
	battle.add_child(ambient)
	# enemy
	enemy_holder = _tr(Control.new()); enemy_holder.position = ENEMY_BASE; battle.add_child(enemy_holder)
	enemy = _sprite("", Vector2(560, 560)); enemy.pivot_offset = Vector2(280, 560)
	enemy_mat = ShaderMaterial.new(); enemy_mat.shader = load("res://assets/shaders/dissolve.gdshader"); enemy.material = enemy_mat
	enemy_holder.add_child(enemy)
	# hero + aura
	hero_holder = _tr(Control.new()); hero_holder.position = HERO_BASE; battle.add_child(hero_holder)
	aura_fx = UI.particles(tex("res://assets/ui/spark.png"), 30, 1.2, Color.WHITE, false)
	aura_fx.position = Vector2(200, 380); aura_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE; aura_fx.emission_sphere_radius = 150
	aura_fx.gravity = Vector2(0, -160); aura_fx.initial_velocity_min = 10; aura_fx.initial_velocity_max = 60
	aura_fx.scale_amount_min = 0.3; aura_fx.scale_amount_max = 0.7; hero_holder.add_child(aura_fx)
	hero = _sprite("res://assets/sprites/hero.png", Vector2(400, 460)); hero.pivot_offset = Vector2(200, 460); hero_holder.add_child(hero)
	slash = _sprite("res://assets/ui/slash.png", Vector2(520, 520)); slash.pivot_offset = Vector2(260, 260); slash.modulate.a = 0
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; slash.material = add
	battle.add_child(slash)
	hit_fx = UI.particles(tex("res://assets/ui/spark.png"), 14, 0.45, Color(1, 0.9, 0.6)); battle.add_child(hit_fx)
	death_fx = UI.particles(tex("res://assets/ui/dot.png"), 50, 0.9, Color(1, 0.6, 0.2)); death_fx.gravity = Vector2(0, -200); battle.add_child(death_fx)
	level_fx = UI.particles(tex("res://assets/ui/spark.png"), 40, 1.1, Color(1, 0.9, 0.3)); level_fx.gravity = Vector2(0, -300); battle.add_child(level_fx)
	prestige_fx = UI.particles(tex("res://assets/ui/shard.png"), 40, 1.6, Color(0.6, 0.85, 1)); prestige_fx.initial_velocity_max = 1300; add_child(prestige_fx)
	for i in 24:
		var l := _lbl("", 50); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; l.visible = false
		l.pivot_offset = Vector2(60, 30); battle.add_child(l); dmg_pool.append(l)
	vignette = _sprite("res://assets/ui/vignette.png", Vector2(1080, 1180)); vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.modulate = Color(1, 0.1, 0.1, 0); battle.add_child(vignette)
	# top bar
	var top := PanelContainer.new(); top.size = Vector2(1080, 110)
	top.add_theme_stylebox_override("panel", UI.panel(Color(0.12, 0.06, 0.16, 0.85))); top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var hb := HBoxContainer.new(); top.add_child(hb); hb.add_theme_constant_override("separation", 10)
	var ci := _sprite("res://assets/ui/coin.png", Vector2.ZERO); ci.custom_minimum_size = Vector2(70, 70); hb.add_child(ci)
	gold_lbl = _lbl("0", 50, Color(1, 0.85, 0.3)); gold_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(gold_lbl)
	var si := _sprite("res://assets/ui/shard.png", Vector2.ZERO); si.custom_minimum_size = Vector2(60, 60); hb.add_child(si)
	shard_lbl = _lbl("0", 42, Color(0.6, 0.85, 1)); hb.add_child(shard_lbl)
	var gi := _sprite("res://assets/ui/shard.png", Vector2.ZERO); gi.custom_minimum_size = Vector2(56, 56); gi.modulate = Color(1, 0.45, 0.8); hb.add_child(gi)
	gem_lbl = _lbl("0", 42, Color(1, 0.6, 0.9)); gem_lbl.pivot_offset = Vector2(30, 25); hb.add_child(gem_lbl)
	stage_lbl = _lbl("", 44); stage_lbl.position = Vector2(0, 130); stage_lbl.size = Vector2(1080, 60)
	stage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _tr(stage_lbl); add_child(stage_lbl)
	hp_bar = ProgressBar.new(); hp_bar.position = Vector2(140, 200); hp_bar.size = Vector2(800, 50); hp_bar.show_percentage = false
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.85, 0.15, 0.2); fill.set_corner_radius_all(12)
	var back := StyleBoxFlat.new(); back.bg_color = Color(0.1, 0.05, 0.05, 0.8); back.set_corner_radius_all(12)
	back.border_color = UI.GOLD; back.set_border_width_all(3)
	hp_bar.add_theme_stylebox_override("fill", fill); hp_bar.add_theme_stylebox_override("background", back)
	_tr(hp_bar); add_child(hp_bar)
	hp_lbl = _lbl("", 32); hp_lbl.position = Vector2(140, 200); hp_lbl.size = Vector2(800, 50)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _tr(hp_lbl); add_child(hp_lbl)
	timer_lbl = _lbl("", 48, Color(1, 0.4, 0.3)); timer_lbl.position = Vector2(0, 260); timer_lbl.size = Vector2(1080, 60)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _tr(timer_lbl); add_child(timer_lbl)
	boss_btn = _btn("", Color(0.7, 0.1, 0.15)); boss_btn.position = Vector2(760, 270); boss_btn.size = Vector2(300, 90)
	boss_btn.pressed.connect(func(): farming = false; boss_btn.visible = false; spawn())
	boss_btn.visible = false; add_child(boss_btn)
	for i in 12:
		var c := _sprite("res://assets/ui/coin.png", Vector2(64, 64)); c.visible = false; add_child(c); coin_pool.append(c)
	# skill bar
	var sk := HBoxContainer.new(); sk.position = Vector2(15, 1190); sk.size = Vector2(1050, 170)
	sk.add_theme_constant_override("separation", 12); add_child(sk)
	for k in G.C.skills:
		var b := Button.new(); b.custom_minimum_size = Vector2(165, 165); b.icon = tex("res://assets/ui/skill_%s.png" % k.id)
		b.expand_icon = true; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_stylebox_override("normal", UI.panel(Color(0.2, 0.1, 0.3)))
		b.add_theme_stylebox_override("hover", UI.panel(Color(0.25, 0.13, 0.36)))
		b.add_theme_stylebox_override("pressed", UI.panel(Color(0.15, 0.07, 0.22)))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("disabled", UI.panel(Color(0.15, 0.15, 0.15, 0.9), Color(0.45, 0.4, 0.35)))
		b.add_theme_font_size_override("font_size", 40)
		b.add_theme_color_override("font_disabled_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color.BLACK); b.add_theme_constant_override("outline_size", 10)
		b.pressed.connect(_use_skill.bind(k)); UI.juice(b)
		sk.add_child(b); skill_btns[k.id] = b
	# tab content
	tab_panel = PanelContainer.new(); tab_panel.position = Vector2(0, 1370); tab_panel.size = Vector2(1080, 430)
	tab_panel.clip_contents = true
	tab_panel.add_theme_stylebox_override("panel", UI.panel(Color(0.16, 0.09, 0.2, 0.97))); add_child(tab_panel)
	tab_scroll = ScrollContainer.new(); tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tab_panel.add_child(tab_scroll)
	tab_box = VBoxContainer.new(); tab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_box.add_theme_constant_override("separation", 10); tab_scroll.add_child(tab_box)
	var tb := HBoxContainer.new(); tb.position = Vector2(0, 1805); tb.size = Vector2(1080, 115)
	tb.add_theme_constant_override("separation", 6); add_child(tb)
	tab_hl = Panel.new(); tab_hl.size = Vector2(205, 10); tab_hl.position = Vector2(0, 1800); _tr(tab_hl)
	var hls := StyleBoxFlat.new(); hls.bg_color = Color(1, 0.85, 0.35); hls.set_corner_radius_all(5); tab_hl.add_theme_stylebox_override("panel", hls)
	for i in TAB_KEYS.size():
		var b := _btn("", Color(0.35, 0.18, 0.45)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 30)
		b.custom_minimum_size = Vector2(0, 110); b.pressed.connect(_show_tab.bind(i)); tb.add_child(b); tab_btns.append(b)
	add_child(tab_hl)
	# overlays
	banner = _lbl("", 96, Color(1, 0.85, 0.35)); banner.size = Vector2(1080, 140); banner.position = Vector2(0, 520)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner.pivot_offset = Vector2(540, 70); banner.visible = false
	banner.add_theme_constant_override("outline_size", 18); _tr(banner); add_child(banner)
	toast_lbl = _lbl("", 34); toast_lbl.size = Vector2(1000, 0); toast_lbl.position = Vector2(40, 330)
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_stylebox_override("normal", UI.panel(Color(0.1, 0.05, 0.15, 0.92))); toast_lbl.modulate.a = 0; _tr(toast_lbl); add_child(toast_lbl)
	overlay = ColorRect.new(); overlay.size = Vector2(1080, 1920); overlay.color = Color(0, 0, 0, 0); _tr(overlay); add_child(overlay)

func _tab_names() -> void:
	for i in TAB_KEYS.size(): tab_btns[i].text = G.tr_(TAB_KEYS[i])
	boss_btn.text = G.tr_("fight_boss")

func biome() -> String: return BIOMES[((G.stage - 1) / 10) % BIOMES.size()]

func _update_aura() -> void:
	aura_fx.emitting = G.aura != "" and AURAS.has(G.aura)
	if aura_fx.emitting:
		var c: Color = AURAS[G.aura]; var g := Gradient.new(); g.set_color(0, c); g.set_color(1, Color(c.r, c.g, c.b, 0)); aura_fx.color_ramp = g

func spawn() -> void:
	dying = false
	var n: int = G.C.enemies_per_stage
	boss = (G.kills >= n) and not farming
	enemy_max = G.hp(G.stage) * (G.C.boss_hp_mult if boss else 1.0)
	enemy_hp = enemy_max
	var b := biome()
	if b != cur_biome:
		var first := cur_biome == ""
		cur_biome = b
		if first:
			bg.texture = tex("res://assets/bg/%s.jpg" % b)
		else:
			_biome_transition(b)
		var tint: Color = BIOME_TINT[b]; var g := Gradient.new(); g.set_color(0, Color(tint.r, tint.g, tint.b, 0.7)); g.set_color(1, Color(tint.r, tint.g, tint.b, 0))
		ambient.color_ramp = g
	var id: String = BOSSES[(G.stage / 5) % BOSSES.size()] if boss else MOBS[b][randi() % 3]
	enemy.texture = tex("res://assets/sprites/%s.png" % id)
	enemy_mat.set_shader_parameter("dissolve", 0.0); enemy_mat.set_shader_parameter("flash", 0.0)
	enemy.scale = Vector2(1.25, 1.25) if boss else Vector2.ONE
	enemy.position = Vector2(-40, -100) if boss else Vector2.ZERO
	if boss:
		_boss_entrance()
	else:
		enemy.modulate = Color(1, 1, 1, 0); enemy.position.x = 120
		var tw := create_tween().set_parallel()
		tw.tween_property(enemy, "modulate", Color.WHITE, 0.25)
		tw.tween_property(enemy, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_hud()

func _boss_entrance() -> void:
	boss_left = G.boss_time(); play("boss")
	enemy.modulate = Color(0, 0, 0, 0)
	var base_s := enemy.scale
	enemy.scale = base_s * 0.4
	var tw := create_tween().set_parallel()
	tw.tween_property(enemy, "modulate", Color.WHITE, 0.6)
	tw.tween_property(enemy, "scale", base_s, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vignette, "modulate:a", 0.8, 0.3)
	tw.chain().tween_property(vignette, "modulate:a", 0.25, 0.8)
	_banner(G.tr_("boss"), Color(1, 0.3, 0.25))
	shake = 0.5

func _biome_transition(b: String) -> void:
	bg2.texture = tex("res://assets/bg/%s.jpg" % b); bg2.modulate.a = 0
	play("whoosh")
	var tw := create_tween()
	tw.tween_property(bg2, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): bg.texture = bg2.texture; bg2.modulate.a = 0)
	_banner(G.tr_("b_" + b), BIOME_TINT[b])

func _banner(text: String, col: Color) -> void:
	banner.text = text; banner.add_theme_color_override("font_color", col); banner.visible = true
	banner.scale = Vector2(2.2, 2.2); banner.modulate.a = 0
	var tw := banner.create_tween()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.tween_interval(0.9)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): banner.visible = false)

func toast(text: String) -> void:
	toast_lbl.text = text
	if toast_tw: toast_tw.kill()
	toast_lbl.position.y = 300; toast_lbl.modulate.a = 0
	toast_tw = create_tween()
	toast_tw.tween_property(toast_lbl, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	toast_tw.parallel().tween_property(toast_lbl, "position:y", 330.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toast_tw.tween_interval(2.4)
	toast_tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.4)

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
	if respawn > 0 or dying: return
	G.total_taps += 1
	if G.total_taps == 10000: G.unlock("taps_10k")
	var d: float = G.tap_dmg() * rage_mult()
	var crit: bool = randf() < G.C.crit_chance
	if crit: d *= G.C.crit_mult
	damage(d, pos, crit)
	if not silent:
		play("crit" if crit else "tap")
		_hero_attack(pos)

func _hero_attack(pos: Vector2) -> void:
	var tw := hero.create_tween()
	tw.tween_property(hero, "position", Vector2(70, -20), 0.05).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(hero, "rotation", 0.18, 0.05)
	tw.tween_property(hero, "position", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hero, "rotation", 0.0, 0.12)
	slash.position = pos - Vector2(260, 260); slash.rotation = randf_range(-0.6, 0.6); slash.scale = Vector2(0.6, 0.6); slash.modulate.a = 1
	var st := slash.create_tween().set_parallel()
	st.tween_property(slash, "scale", Vector2(1.15, 1.15), 0.16)
	st.tween_property(slash, "modulate:a", 0.0, 0.18)

func damage(d: float, pos: Vector2, crit := false, col := Color.WHITE) -> void:
	if respawn > 0 or dying: return
	enemy_hp -= d
	_float_text(G.fmt(d), pos, Color(1, 0.3, 0.2) if crit else col, 76 if crit else 52, crit)
	enemy_mat.set_shader_parameter("flash", 0.8)
	var tw := enemy.create_tween(); tw.tween_method(func(v: float): enemy_mat.set_shader_parameter("flash", v), 0.8, 0.0, 0.14)
	var base_s: Vector2 = Vector2(1.25, 1.25) if boss else Vector2.ONE
	var sq := create_tween()
	sq.tween_property(enemy, "scale", base_s * Vector2(1.1, 0.9), 0.05); sq.tween_property(enemy, "scale", base_s, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hit_fx.position = pos; hit_fx.restart(); hit_fx.emitting = true
	if crit: shake = 0.25
	if enemy_hp <= 0: kill()

func _float_text(t_: String, pos: Vector2, col: Color, size: int, crit := false) -> void:
	var l: Label = dmg_pool[dmg_i]; dmg_i = (dmg_i + 1) % dmg_pool.size()
	if l.has_meta("tw"):
		var old: Tween = l.get_meta("tw"); if old and old.is_valid(): old.kill()
	l.text = t_; l.visible = true
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.position = pos + Vector2(randf_range(-60, 20), -70); l.modulate.a = 1
	l.scale = Vector2(1.8, 1.8) if crit else Vector2(0.6, 0.6); l.rotation = randf_range(-0.15, 0.15) if crit else 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position", l.position + Vector2(randf_range(-40, 40), -200), 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.45)
	tw.tween_callback(func(): l.visible = false)
	l.set_meta("tw", tw)

func kill() -> void:
	if dying: return
	dying = true
	var g: float = G.gold_kill(G.stage, boss) * (_skill("goldrain").power if skill_active.get("goldrain", 0.0) > 0 else 1.0)
	G.gold += g
	_coins(int(clamp(log(g + 1) / 2, 3, 12)))
	play("coin"); play("dissolve")
	var c: Vector2 = enemy_holder.position + enemy.position + Vector2(280, 330)
	death_fx.position = c; death_fx.restart(); death_fx.emitting = true
	var tw := enemy.create_tween()
	tw.tween_method(func(v: float): enemy_mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.45)
	if boss:
		var was: int = G.max_stage
		G.stage += 1; G.kills = 0; boss = false
		G.run_max = max(G.run_max, G.stage)
		G.on_stage_cleared(G.stage)
		G.max_stage = max(G.max_stage, G.stage); play("level")
		vignette.create_tween().tween_property(vignette, "modulate:a", 0.0, 0.5)
		if G.stage > was: Online.submit_stage()
		if G.stage % 10 == 1: Online.save_cloud(false)
		_banner(G.tr_("stage_clear") % G.stage, Color(1, 0.85, 0.35))
	else:
		G.kills += 1
	respawn = max(G.C.respawn_delay, 0.45)

func _coins(n: int) -> void:
	var start: Vector2 = enemy_holder.position + Vector2(280, 400)
	for i in n:
		var c: TextureRect = coin_pool[coin_i]; coin_i = (coin_i + 1) % coin_pool.size()
		if c.has_meta("tw"):
			var old: Tween = c.get_meta("tw"); if old and old.is_valid(): old.kill()
		c.visible = true; c.position = start + Vector2(randf_range(-120, 120), randf_range(-60, 60)); c.scale = Vector2.ONE
		var tw := c.create_tween()
		tw.tween_property(c, "position", c.position + Vector2(randf_range(-100, 100), randf_range(-160, -60)), 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", Vector2(40, 20), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(i * 0.03)
		tw.parallel().tween_property(c, "scale", Vector2(0.6, 0.6), 0.45)
		tw.tween_callback(func(): c.visible = false; _pulse(gold_lbl))
		c.set_meta("tw", tw)

func _pulse(c: Control) -> void:
	c.pivot_offset = c.size / 2
	var tw := c.create_tween(); tw.tween_property(c, "scale", Vector2(1.15, 1.15), 0.05); tw.tween_property(c, "scale", Vector2.ONE, 0.12)

func _gems_pop() -> void:
	gem_lbl.text = str(G.gems); _pulse(gem_lbl)

func _celebrate(fx: CPUParticles2D, col: Color) -> void:
	fx.position = Vector2(540, 700); fx.restart(); fx.emitting = true
	var tw := create_tween(); overlay.color = Color(col.r, col.g, col.b, 0)
	tw.tween_property(overlay, "color:a", 0.6, 0.08); tw.tween_property(overlay, "color:a", 0.0, 0.5)

func _level_up_fx() -> void:
	level_fx.position = hero_holder.position + Vector2(200, 300); level_fx.restart(); level_fx.emitting = true
	var tw := hero.create_tween()
	tw.tween_property(hero, "scale", Vector2(1.15, 1.15), 0.08); tw.tween_property(hero, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if G.hero_lv % 50 == 0:
		play("levelup"); _banner(G.tr_("level_up"), Color(1, 0.9, 0.3)); _celebrate(level_fx, Color(1, 0.9, 0.4))
	else:
		play("level")

func _use_skill(k: Dictionary) -> void:
	if skill_cd[k.id] > 0 or G.hero_lv < k.unlock_level: return
	skill_cd[k.id] = k.cooldown; play("skill")
	var b: Button = skill_btns[k.id]
	b.pivot_offset = b.size / 2
	var tw := b.create_tween(); tw.tween_property(b, "rotation", 0.2, 0.06); tw.tween_property(b, "rotation", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC)
	match k.id:
		"blade":
			damage(G.tap_dmg() * k.power, Vector2(640, 700), true, Color(0.6, 0.9, 1)); shake = 0.4
			_hero_attack(Vector2(680, 700))
		"ward":
			if boss: boss_left += 15
			else: skill_cd[k.id] = 0
		_:
			skill_active[k.id] = k.duration

func _process(dt: float) -> void:
	t += dt
	# idle: hero breathes, enemy bobs (no allocations)
	hero_holder.position.y = HERO_BASE.y + sin(t * 2.2) * 6
	hero_holder.scale.y = 1.0 + sin(t * 2.2 + 1.0) * 0.015
	enemy_holder.position = ENEMY_BASE + Vector2(sin(t * 1.3) * 8, sin(t * 2.6) * 10)
	for id in skill_cd:
		skill_cd[id] = max(0.0, skill_cd[id] - dt); skill_active[id] = max(0.0, skill_active[id] - dt)
	if G.auto_tap_left > 0: G.auto_tap_left = max(0.0, G.auto_tap_left - dt)
	if respawn > 0:
		respawn -= dt
		if respawn <= 0: spawn()
	elif not dying:
		var dmul: float = _skill("meteor").power if skill_active["meteor"] > 0 else 1.0
		var d: float = G.dps() * dmul * dt
		if d > 0:
			enemy_hp -= d
			if enemy_hp <= 0: kill()
		if skill_active["haste"] > 0:
			haste_acc += dt * _skill("haste").power
			while haste_acc >= 1: haste_acc -= 1; tap(Vector2(randf_range(560, 860), randf_range(500, 800)), true)
		if G.auto_tap_left > 0:
			auto_acc += dt * float(G.S.gems.sinks.auto_tapper_tps)
			while auto_acc >= 1: auto_acc -= 1; tap(Vector2(randf_range(560, 860), randf_range(500, 800)), true)
		if boss and respawn <= 0 and not dying:
			boss_left -= dt
			if boss_left <= 0:
				farming = true; G.kills = 0; boss_btn.visible = true
				vignette.create_tween().tween_property(vignette, "modulate:a", 0.0, 0.4)
				_float_text(G.tr_("failed"), Vector2(300, 500), Color(1, 0.4, 0.3), 64); spawn()
	if shake > 0:
		shake -= dt; battle.position = Vector2(randf_range(-14, 14), randf_range(-14, 14)) if shake > 0 else Vector2.ZERO
	ui_acc += dt
	if ui_acc > 0.15: ui_acc = 0; _update_hud()
	save_acc += dt
	if save_acc > 10: save_acc = 0; G.save_game()

func _update_hud() -> void:
	gold_lbl.text = G.fmt(G.gold); shard_lbl.text = G.fmt(G.shards); gem_lbl.text = str(G.gems)
	var n: int = G.C.enemies_per_stage
	stage_lbl.text = "%s %d  %s" % [G.tr_("stage"), G.stage, (G.tr_("boss") if boss else "%d/%d" % [min(G.kills, n), n])]
	hp_bar.max_value = 1000; hp_bar.value = lerp(hp_bar.value, 1000 * max(enemy_hp, 0) / enemy_max, 0.6)
	hp_lbl.text = "%s / %s" % [G.fmt(max(enemy_hp, 0)), G.fmt(enemy_max)]
	timer_lbl.text = ("%.1f" % boss_left) if boss else ""
	for k in G.C.skills:
		var b: Button = skill_btns[k.id]
		var locked: bool = G.hero_lv < k.unlock_level
		b.disabled = locked or skill_cd[k.id] > 0
		b.text = ("%d" % k.unlock_level) if locked else ("%d" % ceil(skill_cd[k.id]) if skill_cd[k.id] > 0 else "")
		b.modulate = Color(1, 1, 0.6) if skill_active[k.id] > 0 else Color.WHITE
	for u in row_updaters: u.call()

func _show_tab(i: int, instant := false) -> void:
	var dir := signf(i - cur_tab) if i != cur_tab else 1.0
	cur_tab = i
	var w: float = 1080.0 / TAB_KEYS.size()
	for j in TAB_KEYS.size(): tab_btns[j].modulate = Color(1.3, 1.2, 0.8) if j == i else Color(0.85, 0.85, 0.9)
	if instant:
		tab_hl.position.x = i * w + 10; tab_hl.size.x = w - 20; _refresh_tab(true); return
	var hl := create_tween(); hl.tween_property(tab_hl, "position:x", i * w + 10, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	play("whoosh")
	# slide out, rebuild, slide in
	var tw := create_tween()
	tw.tween_property(tab_scroll, "modulate:a", 0.0, 0.09)
	tw.parallel().tween_property(tab_scroll, "position:x", -60.0 * dir, 0.09)
	tw.tween_callback(func():
		_refresh_tab(true); tab_scroll.scroll_vertical = 0; tab_scroll.position.x = 80.0 * dir)
	tw.tween_property(tab_scroll, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tab_scroll, "modulate:a", 1.0, 0.18)

var _last_sig := ""
func _refresh_tab(force := false) -> void:
	var sig := "%d|%s|%d|%s|%s|%s" % [cur_tab, G.lang, G.comp.count(0), G.owned.size(), G.aura, Online.signed_in]
	if not force and sig == _last_sig: return
	_last_sig = sig
	_tab_names()
	for c in tab_box.get_children(): c.queue_free()
	row_updaters.clear()
	match cur_tab:
		0: _tab_hero()
		1: _tab_comp()
		2: _tab_art()
		3: _tab_shop()
		4: _tab_settings()
	# rows cascade in
	var i := 0
	for c in tab_box.get_children():
		if c is Control:
			c.modulate.a = 0
			c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2).set_delay(0.04 * i); i += 1
	_update_hud()

func _row(icon: Texture2D, on_buy: Callable, btn_col := Color(0.2, 0.5, 0.15)) -> Array:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 14); tab_box.add_child(hb)
	var ic := _sprite("", Vector2.ZERO); ic.texture = icon; ic.custom_minimum_size = Vector2(120, 120); hb.add_child(ic)
	var l := _lbl("", 32); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hb.add_child(l)
	var b := _btn("", btn_col); b.custom_minimum_size = Vector2(300, 110); b.pressed.connect(on_buy); hb.add_child(b)
	return [l, b, ic]

func _header(text: String) -> void:
	var l := _lbl(text, 40, Color(1, 0.85, 0.35)); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tab_box.add_child(l)

func _tab_hero() -> void:
	var r := _row(tex("res://assets/sprites/hero.png"), func():
		if G.buy_hero(): _level_up_fx())
	row_updaters.append(func():
		r[0].text = "%s  %s %d\n%s: %s\n%s: %s" % [G.tr_("title"), G.tr_("lvl"), G.hero_lv, G.tr_("tap_dmg"), G.fmt(G.tap_dmg()), G.tr_("dps"), G.fmt(G.dps())]
		r[1].text = "%s\n%s" % [G.tr_("buy"), G.fmt(G.hero_cost())]; r[1].disabled = G.gold < G.hero_cost())
	for k in G.C.skills:
		var l := _lbl("", 30); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(l)
		l.text = "• %s — %s" % [G.tr_("s_" + k.id), G.tr_("unlock_at") % k.unlock_level]

func _tab_comp() -> void:
	for i in G.C.companions.size():
		var id: String = G.C.companions[i].id
		var r := _row(tex("res://assets/portraits/%s.png" % id), func():
			if G.buy_comp(i): play("coin"); _pulse(r_ic(i)))
		r[2].name = "ic%d" % i
		row_updaters.append(func():
			var l: int = G.comp[i]
			r[0].text = "%s  %s %d\nDPS: %s" % [G.tr_(id), G.tr_("lvl"), l, G.fmt(G.comp_dps(i))]
			r[1].text = "%s\n%s" % [G.tr_("hire") if l == 0 else G.tr_("buy"), G.fmt(G.comp_cost(i))]
			r[1].disabled = G.gold < G.comp_cost(i))
		if G.comp[i] == 0: break  # reveal companions one at a time

func r_ic(i: int) -> Control:
	var n := tab_box.find_child("ic%d" % i, true, false)
	return n if n else tab_box

func _tab_art() -> void:
	var pb := _btn("", Color(0.45, 0.15, 0.6)); pb.custom_minimum_size = Vector2(0, 100); tab_box.add_child(pb)
	var info := _lbl("", 28); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(info)
	pb.pressed.connect(func():
		var s: int = G.prestige()
		if s > 0:
			play("prestige"); _celebrate(prestige_fx, Color(0.6, 0.85, 1)); _banner(G.tr_("prestige_done") % G.fmt(s), Color(0.6, 0.85, 1))
			farming = false; boss_btn.visible = false; cur_biome = ""; spawn(); _refresh_tab(true))
	row_updaters.append(func():
		var s: int = G.shards_for(G.run_max)
		pb.text = G.tr_("prestige"); pb.disabled = s <= 0
		info.text = G.tr_("prestige_info") % [G.fmt(s), G.C.prestige.min_stage, G.run_max])
	for a in G.C.artifacts:
		var id: String = a.id
		var r := _row(tex("res://assets/ui/shard.png"), func():
			if G.buy_art(id): play("level"); _celebrate(level_fx, Color(0.6, 0.85, 1)))
		row_updaters.append(func():
			var v: float = G.artv(id)
			var vs: String = ("%d" % int(v)) if a.effect in ["boss_time", "start_stage"] else G.fmt(v) if v >= 1000 else "%.2f" % v
			r[0].text = "%s\n%s %d/%d" % [G.tr_("a_" + id) % vs, G.tr_("lvl"), G.art[id], a.max]
			var maxed: bool = G.art[id] >= a.max
			r[1].text = G.tr_("max") if maxed else "%s\n%s" % [G.tr_("buy"), G.fmt(G.art_cost(id))]
			r[1].disabled = maxed or G.shards < G.art_cost(id))

func _tab_shop() -> void:
	var sk: Dictionary = G.S.gems.sinks
	var gem_icon: Texture2D = tex("res://assets/ui/shard.png")
	_header(G.tr_("spend"))
	var sinks := [
		["g_reset", int(sk.reset_cooldowns), func():
			for k in skill_cd: skill_cd[k] = 0.0
			play("skill")],
		["g_warp", int(sk.time_warp_cost), func():
			var g: float = G.offline_income(float(sk.time_warp_hours) * 3600.0); G.gold += g
			_coins(12); toast("+" + G.fmt(g))],
		["g_auto", int(sk.auto_tapper_cost), func(): G.auto_tap_left += float(sk.auto_tapper_minutes) * 60.0],
	]
	for s in sinks:
		var key: String = s[0]; var cost: int = s[1]; var fn: Callable = s[2]
		var r := _row(gem_icon, func():
			if G.spend_gems(cost): fn.call(); _celebrate(level_fx, Color(1, 0.5, 0.85)), Color(0.55, 0.15, 0.45))
		r[2].modulate = Color(1, 0.45, 0.8)
		row_updaters.append(func():
			var txt: String = G.tr_(key)
			if key == "g_warp": txt = txt % int(sk.time_warp_hours)
			elif key == "g_auto": txt = txt % [int(sk.auto_tapper_tps), int(sk.auto_tapper_minutes)] + ("\n%d s" % int(G.auto_tap_left) if G.auto_tap_left > 0 else "")
			r[0].text = txt; r[1].text = "%d" % cost; r[1].disabled = G.gems < cost)
	for aid in AURAS:
		var r := _row(tex("res://assets/ui/spark.png"), func():
			if G.owned.has(aid):
				G.aura = "" if G.aura == aid else aid
			elif aid != "aura_gold" and G.spend_gems(int(sk.aura_cost)):
				G.owned[aid] = true; G.aura = aid
			else: return
			G.save_game(); _update_aura(); _refresh_tab(true), Color(0.55, 0.15, 0.45))
		r[2].modulate = AURAS[aid]
		row_updaters.append(func():
			r[0].text = G.tr_("g_" + aid)
			if G.owned.has(aid): r[1].text = G.tr_("equipped") if G.aura == aid else G.tr_("equip"); r[1].disabled = false
			elif aid == "aura_gold": r[1].text = "—"; r[1].disabled = true
			else: r[1].text = "%d" % int(sk.aura_cost); r[1].disabled = G.gems < int(sk.aura_cost))
	_header(G.tr_("premium"))
	if not Online.billing_ready:
		var w := _lbl(G.tr_("billing_unavail"), 28, Color(1, 0.75, 0.6)); w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(w)
	for p in G.S.billing.products:
		var pid: String = p.id
		var r := _row(tex("res://assets/ui/coin.png") if pid == "vip_pack" else gem_icon, func(): Online.buy(pid), Color(0.15, 0.4, 0.6))
		if pid != "vip_pack": r[2].modulate = Color(1, 0.45, 0.8)
		row_updaters.append(func():
			var key := "p_" + pid
			r[0].text = (G.tr_(key) % int(p.gems)) if "%d" in G.tr_(key) else G.tr_(key)
			var owned: bool = p.type == "non_consumable" and G.owned.has(pid)
			r[1].text = G.tr_("owned") if owned else str(Online.prices.get(pid, p.fallback_price))
			r[1].disabled = owned)
	var rb := _btn(G.tr_("restore"), Color(0.3, 0.3, 0.4)); rb.pressed.connect(Online.restore); tab_box.add_child(rb)

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
	_header("Google Play")
	if not Online.gpgs_available:
		var w := _lbl(G.tr_("gunavail"), 28, Color(1, 0.75, 0.6)); w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(w)
	elif not Online.signed_in:
		var g := _btn(G.tr_("gsign"), Color(0.15, 0.35, 0.6)); g.pressed.connect(Online.sign_in); tab_box.add_child(g)
	else:
		var s := _lbl(G.tr_("gsigned"), 30, Color(0.6, 1, 0.6)); tab_box.add_child(s)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); tab_box.add_child(row)
		for pair in [["cloud_save", func(): Online.save_cloud(true)], ["cloud_load", func(): Online.load_cloud(true)]]:
			var b := _btn(G.tr_(pair[0]), Color(0.15, 0.35, 0.6)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.pressed.connect(pair[1]); row.add_child(b)
		var row2 := HBoxContainer.new(); row2.add_theme_constant_override("separation", 10); tab_box.add_child(row2)
		for pair in [["achievements", Online.show_achievements], ["leaderboard", Online.show_leaderboard]]:
			var b := _btn(G.tr_(pair[0]), Color(0.15, 0.35, 0.6)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.pressed.connect(pair[1]); row2.add_child(b)
	var rb := _btn(G.tr_("restore"), Color(0.3, 0.3, 0.4)); rb.pressed.connect(Online.restore); tab_box.add_child(rb)
	var st := _lbl("", 28); st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab_box.add_child(st)
	row_updaters.append(func():
		sb.text = "%s: %s" % [G.tr_("sound"), G.tr_("on") if G.sound_on else G.tr_("off")]
		mb.text = "%s: %s" % [G.tr_("music"), G.tr_("on") if G.music_on else G.tr_("off")]
		lb.text = G.tr_("language")
		var badges := ""
		if G.owned.has("supporter"): badges += "  ★ " + G.tr_("supporter")
		if G.owned.has("vip"): badges += "  ♛ " + G.tr_("vip")
		st.text = "%s: %d%s\n%s: %d/7\n\n%s\n\n%s\nv%s" % [G.tr_("best"), G.max_stage, badges, G.tr_("achievements"), G.ach.size(), G.tr_("story"), G.tr_("privacy"), ProjectSettings.get_setting("application/config/version", "1.1.0")])

func _ask_cloud(d: Dictionary) -> void:
	var p := popup(G.tr_("cloud_found") % int(d.get("max", 1)), false)
	var v: VBoxContainer = p.get_child(0)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 20); v.add_child(h)
	var y := _btn(G.tr_("yes"), Color(0.2, 0.5, 0.15)); y.size_flags_horizontal = Control.SIZE_EXPAND_FILL; y.custom_minimum_size.y = 100
	var n := _btn(G.tr_("no"), Color(0.5, 0.15, 0.15)); n.size_flags_horizontal = Control.SIZE_EXPAND_FILL; n.custom_minimum_size.y = 100
	h.add_child(y); h.add_child(n)
	y.pressed.connect(func():
		Online.apply_cloud(d); farming = false; cur_biome = ""; spawn(); _refresh_tab(true); _close(p))
	n.pressed.connect(_close.bind(p))

func popup(t_: String, with_ok := true) -> PanelContainer:
	var p := PanelContainer.new(); p.position = Vector2(90, 600); p.custom_minimum_size = Vector2(900, 0); p.size = Vector2(900, 400)
	p.add_theme_stylebox_override("panel", UI.panel(Color(0.18, 0.08, 0.25, 0.97))); add_child(p)
	p.add_to_group("popups")
	var v := VBoxContainer.new(); p.add_child(v); v.add_theme_constant_override("separation", 20)
	var l := _lbl(t_, 40); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size = Vector2(860, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(l)
	if with_ok:
		var b := _btn(G.tr_("ok"), Color(0.2, 0.5, 0.15)); b.custom_minimum_size = Vector2(0, 100); v.add_child(b)
		b.pressed.connect(_close.bind(p))
	p.pivot_offset = Vector2(450, 200); p.scale = Vector2(0.6, 0.6); p.modulate.a = 0
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	return p

func _close(p: Control) -> void:
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2(0.8, 0.8), 0.15); tw.tween_property(p, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(p.queue_free)

## Dev-only: `godot -- --shot=<file>,<tab>,<stage>,<hero>,<lang>` renders a store screenshot.
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var p: PackedStringArray = a.substr(7).split(",")
			call_deferred("_shot", p[0], int(p[1]), int(p[2]), int(p[3]), p[4] if p.size() > 4 else "ru")

func _shot(path: String, tab: int, st: int, hl: int, lang: String) -> void:
	set_process(false)
	G.lang = lang
	G.stage = st; G.run_max = st + 8; G.hero_lv = hl; G.offline_gold = 0; G.gems = 340
	for i in G.comp.size(): G.comp[i] = max(0, hl - 25 * i)
	G.gold = G.hp(st) * 40; G.shards = 340; G.kills = 10 if tab == 2 else 6
	if tab == 3: G.owned["aura_fire"] = true; G.aura = "aura_fire"; _update_aura()
	for c in get_tree().get_nodes_in_group("popups"): c.queue_free()
	for k in G.C.skills: skill_cd[k.id] = 0.0
	cur_biome = ""; spawn(); _show_tab(tab, true)
	if tab == 1: skill_active["rage"] = 10; skill_cd["rage"] = 100; skill_cd["blade"] = 12
	for i in 40: await get_tree().process_frame
	overlay.color.a = 0; banner.visible = false; toast_lbl.modulate.a = 0
	if tab == 3: tab_scroll.scroll_vertical = 900
	enemy.modulate = Color.WHITE; enemy.scale = Vector2(1.25, 1.25) if boss else Vector2.ONE
	for i in 4: _float_text(G.fmt(G.tap_dmg() * (8 if i == 2 else 1)), Vector2(560 + i * 90, 640 - i * 40), Color(1, 0.3, 0.2) if i == 2 else Color.WHITE, 76 if i == 2 else 52, i == 2)
	hit_fx.position = Vector2(700, 640); hit_fx.restart(); hit_fx.emitting = true
	_coins(6)
	enemy_hp = enemy_max * 0.62
	if boss: boss_left = 17.4
	_update_hud(); hp_bar.value = 620
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
