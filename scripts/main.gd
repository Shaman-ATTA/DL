extends Control
## Main screen: battle, skills, tabs, meta panels. UI is built in code; effects use pooled nodes.
## Hero and monsters are deformable Actors (scripts/rig.gd + actor.gdshader).
const BIOMES := ["forest", "cave", "lava", "ice"]
const MOBS := {"forest": ["slime", "mushroom", "goblin"], "cave": ["golem", "goblin", "wraith"],
	"lava": ["salamander", "golem", "mushroom"], "ice": ["wraith", "slime", "golem"]}
const BOSSES := ["boss_dragon", "boss_frostking", "boss_lich", "boss_wyrm"]
const BIOME_TINT := {"forest": Color(0.7, 1, 0.6), "cave": Color(0.6, 0.8, 1), "lava": Color(1, 0.55, 0.2), "ice": Color(0.85, 0.95, 1)}
const AURAS := {"aura_fire": Color(1, 0.45, 0.1), "aura_frost": Color(0.5, 0.85, 1), "aura_arcane": Color(0.8, 0.4, 1), "aura_gold": Color(1, 0.85, 0.3)}
const TAB_KEYS := ["tab_hero", "tab_comp", "tab_art", "tab_shop", "tab_set"]
## ichor colour, glow, idle profile [breathe_amp, breathe_speed, bob, hover, wobble, wobble_speed, stiff, mass]
const MOB := {
	"slime": [Color(0.35, 0.95, 0.3), 0.6, [0.05, 3.2, 4, 0, 0.9, 4.0, 150, 0.8]],
	"mushroom": [Color(0.95, 0.85, 0.5), 0.2, [0.03, 2.4, 6, 0, 0.2, 3.0, 170, 1.0]],
	"goblin": [Color(0.75, 0.05, 0.08), 0.0, [0.025, 3.0, 8, 0, 0.0, 3.0, 210, 0.9]],
	"golem": [Color(1.0, 0.55, 0.15), 0.9, [0.012, 1.2, 2, 0, 0.0, 3.0, 120, 1.8]],
	"salamander": [Color(1.0, 0.45, 0.05), 1.0, [0.03, 2.6, 5, 0, 0.35, 5.0, 180, 1.0]],
	"wraith": [Color(0.55, 0.9, 1.0), 1.0, [0.02, 1.8, 18, 10, 0.5, 2.2, 140, 0.7]],
	"boss_dragon": [Color(0.8, 0.05, 0.05), 0.3, [0.025, 1.6, 6, 0, 0.0, 3.0, 150, 1.6]],
	"boss_frostking": [Color(0.45, 0.8, 1.0), 0.8, [0.02, 1.4, 4, 0, 0.0, 3.0, 140, 1.8]],
	"boss_lich": [Color(0.5, 1.0, 0.45), 1.0, [0.02, 1.5, 12, 8, 0.25, 2.0, 140, 1.3]],
	"boss_wyrm": [Color(0.75, 0.3, 1.0), 0.8, [0.03, 1.8, 6, 0, 0.3, 2.4, 140, 1.7]],
}
const ATK_SET := ["slash", "upper", "thrust", "slash", "spin", "upper"]
const HERO_FEET := Vector2(230, 1100)
const ENEMY_FEET := Vector2(730, 1020)
var G
var bg: TextureRect
var bg2: TextureRect
var battle: Control
var enemy: Actor
var enemy_pool := {}  # "legacy" -> Actor, rig id -> SkelActor (see docs/SKELETAL.md)
var hero: Actor
var hero_holder: Node2D
var pet_spr: Sprite2D
var fairy: Node2D
var fairy_t := -1.0
var fairy_wait := 60.0
var slash: TextureRect
var hp_bar: ProgressBar
var hp_lbl: Label
var stage_lbl: Label
var gold_lbl: Label
var shard_lbl: Label
var gem_lbl: Label
var timer_lbl: Label
var boss_btn: Button
var side_btns := {}
var tab_panel: PanelContainer
var tab_scroll: ScrollContainer
var tab_box: VBoxContainer
var tab_hl: Panel
var cur_tab := 0
var hero_sub := 0
var tab_btns: Array = []
var skill_btns: Dictionary = {}
var skill_cd: Dictionary = {}
var skill_active: Dictionary = {}
var enemy_id := ""
var enemy_hp := 1.0
var enemy_max := 1.0
var wound_stage := 0
var boss := false
var boss_left := 0.0
var roar_t := 5.0
var farming := false
var respawn := 0.0
var haste_acc := 0.0
var auto_acc := 0.0
var save_acc := 0.0
var ui_acc := 0.0
var shake := 0.0
var t := 0.0
var cur_biome := ""
var row_updaters: Array = []
var tex_cache := {}
var atk_i := 0
var pet_taps := 0
var raid := false
var raid_left := 0.0
var raid_dmg := 0.0
var story_queue: Array = []
var story_open := false
var shot_mode := false
var quality := 2
var modal: Control
var modal_box: VBoxContainer
# pools (no per-hit allocations)
var dmg_pool: Array[Label] = []
var dmg_i := 0
var coin_pool: Array[TextureRect] = []
var coin_i := 0
var hit_fx: CPUParticles2D
var ichor_fx: CPUParticles2D
var drip_fx: CPUParticles2D
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
	for k in G.C.skills: skill_cd[k.id] = 0.0; skill_active[k.id] = 0.0
	G.changed.connect(_refresh_tab)
	G.click.connect(func(): play("click", false))
	G.gems_changed.connect(_gems_pop)
	G.achievement.connect(func(k: String): toast(G.tr_("ach_get") % [G.tr_("ach_" + k), int(G.S.gems.achievement_reward)]))
	G.quest_done.connect(func(s: String): toast(s); play("levelup", false))
	Online.toast.connect(toast)
	Online.status_changed.connect(func(): _refresh_tab(true))
	Online.cloud_conflict.connect(_ask_cloud)
	Online.purchase_granted.connect(func(_p): _celebrate(prestige_fx, Color(1, 0.85, 0.3)); _update_aura())
	Online.scores_loaded.connect(_on_scores)
	Sound.apply(); apply_quality()
	_update_aura(); _update_pet()
	fairy_wait = _fairy_interval()
	spawn()
	_show_tab(0, true)
	overlay.color = Color(0, 0, 0, 1)
	create_tween().tween_property(overlay, "color:a", 0.0, 0.5)
	var daily: int = G.claim_daily()
	if shot_mode: return
	if G.total_taps == 0: queue_story("start")
	if G.offline_gold > 0:
		var msg: String = G.tr_("offline") % G.fmt(G.offline_gold)
		if G.offline_full and G.settings.notif_offline: msg += "\n\n" + G.tr_("offline_full")
		popup(msg)
	if daily > 0: toast(G.tr_("daily") % daily)
	if G.streak_day != Time.get_date_string_from_system(): get_tree().create_timer(1.2).timeout.connect(_calendar)

func play(s: String, vary := true) -> void: Sound.play(s, vary)

func _lbl(t_: String, size := 38, col := Color.WHITE) -> Label: return UI.lbl(t_, size, col)
func _btn(t_: String, col := Color(0.55, 0.25, 0.1)) -> Button: return UI.btn(t_, col)
func _tr(c: Control) -> Control: c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c
func _wrap(l: Label) -> Label: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; return l

func _sprite(path: String, sz: Vector2) -> TextureRect:
	var r := TextureRect.new(); if path != "": r.texture = tex(path)
	r.size = sz; r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _grad(c: Color, a0 := 1.0) -> Gradient:
	var g := Gradient.new(); g.set_color(0, Color(c.r, c.g, c.b, a0)); g.set_color(1, Color(c.r, c.g, c.b, 0)); return g

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
	# ground shadows
	for x in [HERO_FEET, ENEMY_FEET]:
		var sh := _sprite("res://assets/ui/dot.png", Vector2(420, 70)); sh.stretch_mode = TextureRect.STRETCH_SCALE
		sh.position = x - Vector2(210, 30); sh.modulate = Color(0, 0, 0, 0.45); battle.add_child(sh)
	# enemy
	enemy = Actor.new(); enemy.position = ENEMY_FEET; battle.add_child(enemy); enemy_pool["legacy"] = enemy
	for rid in Rigs.SKELETAL:
		var sa := SkelActor.new(rid); sa.position = ENEMY_FEET; sa.visible = false; battle.add_child(sa); enemy_pool[rid] = sa
	enemy.setup(tex("res://assets/sprites/slime.png"), Vector2(560, 560))
	# hero + aura + pet
	hero_holder = Node2D.new(); hero_holder.position = HERO_FEET; battle.add_child(hero_holder)
	aura_fx = UI.particles(tex("res://assets/ui/spark.png"), 30, 1.2, Color.WHITE, false)
	aura_fx.position = Vector2(-20, -180); aura_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE; aura_fx.emission_sphere_radius = 150
	aura_fx.gravity = Vector2(0, -160); aura_fx.initial_velocity_min = 10; aura_fx.initial_velocity_max = 60
	aura_fx.scale_amount_min = 0.3; aura_fx.scale_amount_max = 0.7; hero_holder.add_child(aura_fx)
	hero = SkelActor.new("hero"); hero_holder.add_child(hero)
	hero.setup(tex("res://assets/sprites/hero_body.png"), Vector2(470, 400))
	hero.breathe_amp = 0.022; hero.breathe_speed = 2.2; hero.bob = 3.0
	hero.set_param("rim_color", Color(1.0, 0.85, 0.55)); hero.set_param("rim_dir", Vector2(0.7, -0.7)); hero.set_param("cape", 0.6)
	hero.add_blade(tex("res://assets/sprites/hero_blade.png"), Vector2(18, 196), Vector2(445, 250), battle)
	pet_spr = Sprite2D.new(); pet_spr.position = Vector2(-150, -420); pet_spr.scale = Vector2(0.32, 0.32); pet_spr.visible = false; hero_holder.add_child(pet_spr)
	slash = _sprite("res://assets/ui/slash.png", Vector2(520, 520)); slash.pivot_offset = Vector2(260, 260); slash.modulate.a = 0
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; slash.material = add
	battle.add_child(slash)
	hit_fx = UI.particles(tex("res://assets/ui/spark.png"), 14, 0.45, Color(1, 0.9, 0.6)); battle.add_child(hit_fx)
	ichor_fx = UI.particles(tex("res://assets/ui/dot.png"), 26, 0.8, Color.WHITE); ichor_fx.gravity = Vector2(0, 1400)
	ichor_fx.initial_velocity_min = 250; ichor_fx.initial_velocity_max = 650; ichor_fx.scale_amount_min = 0.25; ichor_fx.scale_amount_max = 0.6; battle.add_child(ichor_fx)
	drip_fx = UI.particles(tex("res://assets/ui/dot.png"), 6, 1.0, Color.WHITE, false); drip_fx.gravity = Vector2(0, 900)
	drip_fx.initial_velocity_min = 0; drip_fx.initial_velocity_max = 30; drip_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	drip_fx.emission_sphere_radius = 110; drip_fx.scale_amount_min = 0.15; drip_fx.scale_amount_max = 0.3; drip_fx.emitting = false; battle.add_child(drip_fx)
	death_fx = UI.particles(tex("res://assets/ui/dot.png"), 50, 0.9, Color(1, 0.6, 0.2)); death_fx.gravity = Vector2(0, -200); battle.add_child(death_fx)
	level_fx = UI.particles(tex("res://assets/ui/spark.png"), 40, 1.1, Color(1, 0.9, 0.3)); level_fx.gravity = Vector2(0, -300); battle.add_child(level_fx)
	prestige_fx = UI.particles(tex("res://assets/ui/shard.png"), 40, 1.6, Color(0.6, 0.85, 1)); prestige_fx.initial_velocity_max = 1300; add_child(prestige_fx)
	# fairy (tap to collect)
	fairy = Node2D.new(); fairy.visible = false; battle.add_child(fairy)
	var fs := Sprite2D.new(); fs.texture = tex("res://assets/ui/spark.png"); fs.scale = Vector2(1.3, 1.3); fs.modulate = Color(1, 0.75, 1)
	var fm := CanvasItemMaterial.new(); fm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; fs.material = fm; fairy.add_child(fs)
	var ft := UI.particles(tex("res://assets/ui/dot.png"), 24, 0.8, Color(1, 0.7, 1), false); ft.local_coords = false
	ft.gravity = Vector2(0, 60); ft.initial_velocity_max = 30; ft.scale_amount_min = 0.15; ft.scale_amount_max = 0.35; ft.emitting = true; fairy.add_child(ft)
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
	# side menu (quests / raid / ranking / calendar)
	var sv := VBoxContainer.new(); sv.position = Vector2(14, 330); sv.add_theme_constant_override("separation", 10); add_child(sv)
	for pair in [["quests", _quests], ["raid", _raid_menu], ["ranking", _ranking], ["calendar", _calendar]]:
		var b := _btn("", Color(0.3, 0.15, 0.42)); b.custom_minimum_size = Vector2(150, 84)
		b.add_theme_font_size_override("font_size", 24); b.pressed.connect(pair[1]); sv.add_child(b); side_btns[pair[0]] = b
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
	for k in side_btns: side_btns[k].text = G.tr_("side_" + k)
	side_btns.raid.text = "%s %d" % [G.tr_("side_raid"), G.raid_tickets]

## Graphics quality: 0 low, 1 medium, 2 high. Battery saver forces 30 fps and <= medium.
func apply_quality() -> void:
	var st: Dictionary = G.settings
	quality = int(st.quality)
	if st.battery: quality = min(quality, 1)
	Engine.max_fps = 30 if st.battery else int(st.fps)
	ambient.emitting = quality >= 1; ambient.amount = 40 if quality >= 2 else 18
	hero.set_trails(quality >= 1)
	for a in [hero, enemy]: a.set_param("rim", 0.6 if quality >= 2 else 0.0)
	hit_fx.amount = 14 if quality >= 1 else 6
	death_fx.amount = 50 if quality >= 2 else 20
	ichor_fx.amount = 26 if quality >= 1 else 10

func biome() -> String: return BIOMES[((G.stage - 1) / 10) % BIOMES.size()]

func _update_aura() -> void:
	aura_fx.emitting = G.aura != "" and AURAS.has(G.aura)
	if aura_fx.emitting: aura_fx.color_ramp = _grad(AURAS[G.aura])
	hero.set_param("rim_color", AURAS[G.aura] if AURAS.has(G.aura) else Color(1.0, 0.85, 0.55))

func _update_pet() -> void:
	pet_spr.visible = G.active_pet != ""
	if pet_spr.visible: pet_spr.texture = tex("res://assets/sprites/pet_%s.png" % G.active_pet)

func _music() -> void:
	if story_open: return
	Sound.music("raid" if raid else ("boss" if boss else biome()))

func spawn() -> void:
	dying = false
	var n: int = G.C.enemies_per_stage
	boss = (G.kills >= n) and not farming and not raid
	enemy_max = G.hp(G.stage) * (G.C.boss_hp_mult if boss else 1.0)
	enemy_hp = enemy_max
	var b := biome()
	if b != cur_biome:
		var first := cur_biome == ""
		cur_biome = b
		if first: bg.texture = tex("res://assets/bg/%s.jpg" % b)
		else: _biome_transition(b)
		var tint: Color = BIOME_TINT[b]
		ambient.color_ramp = _grad(tint, 0.7)
		enemy.set_param("rim_color", tint.lerp(Color.WHITE, 0.4))
	var id: String
	if raid: id = "boss_wyrm"
	elif boss: id = BOSSES[(G.stage / 5) % BOSSES.size()]
	else: id = MOBS[b][randi() % 3]
	enemy_id = id
	var want: Actor = enemy_pool.get(id, enemy_pool["legacy"])
	if want != enemy:
		enemy.visible = false; enemy = want; enemy.visible = true
	var big := boss or raid
	enemy.position = ENEMY_FEET + (Vector2(20, 0) if big else Vector2.ZERO)
	enemy.setup(tex("res://assets/sprites/%s.png" % id), Vector2(700, 700) if big else Vector2(560, 560), tex("res://assets/wounds/%s.png" % id))
	var m: Array = MOB[id]; var pr: Array = m[2]
	enemy.breathe_amp = pr[0]; enemy.breathe_speed = pr[1]; enemy.bob = pr[2]; enemy.hover = pr[3]
	enemy.set_param("wobble", pr[4]); enemy.set_param("wobble_speed", pr[5]); enemy.stiff = pr[6]
	enemy.set_param("cape", 0.8 if id in ["wraith", "boss_lich", "boss_frostking"] else 0.0)
	enemy.set_param("ichor", m[0]); enemy.set_param("ichor_glow", m[1]); enemy.set_param("darken", 0.0)
	enemy.set_param("edge_color", m[0].lerp(Color(1, 0.7, 0.2), 0.5)); enemy.set_param("flash", 0.0)
	enemy.tilt_target = 0.0; enemy.lean_target = 0.0; enemy.squash_target = 0.0
	ichor_fx.color_ramp = _grad(m[0]); drip_fx.color_ramp = _grad(m[0]); drip_fx.emitting = false
	wound_stage = 0
	roar_t = randf_range(4.0, 6.0)
	if big: _boss_entrance()
	else:
		enemy.scale = Vector2.ONE; enemy.modulate = Color(1, 1, 1, 0); enemy.kick(-900, -1.2, -1.5, -500)  # lands from the right with a squash
		enemy.kx = 160
		create_tween().tween_property(enemy, "modulate", Color.WHITE, 0.25)
	_music()
	_update_hud()

func _boss_entrance() -> void:
	boss_left = G.boss_time() if boss else float(G.K.raid.seconds)
	play("boss")
	enemy.modulate = Color(0, 0, 0, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(enemy, "modulate", Color.WHITE, 0.6)
	if enemy is SkelActor and enemy.has_clip("entrance"):
		enemy.scale = Vector2.ONE; enemy.entrance()
	else:
		enemy.scale = Vector2(0.4, 0.4)
		tw.tween_property(enemy, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vignette, "modulate:a", 0.8, 0.3)
	tw.chain().tween_property(vignette, "modulate:a", 0.25, 0.8)
	_banner(G.tr_("raid_title") if raid else G.tr_("boss"), Color(0.8, 0.5, 1) if raid else Color(1, 0.3, 0.25))
	_shake(0.5)

## Boss roar: anticipation (rear back), then a lunge toward the hero with a screen jolt.
func _roar() -> void:
	if enemy is SkelActor: enemy.play_clip("attack")
	enemy.lean_target = -0.12; enemy.squash_target = -0.08
	var tw := create_tween(); tw.tween_interval(0.35)
	tw.tween_callback(func():
		if dying: return
		enemy.lean_target = 0.0; enemy.squash_target = 0.0
		enemy.kick(-1400, 2.5, 3.0, -300); hero.kick(-500, -1.2, 1.5)
		_shake(0.22); play("boss", true); Sound.haptic(40, 0.6)
		vignette.modulate.a = 0.7; vignette.create_tween().tween_property(vignette, "modulate:a", 0.25, 0.5))

func _shake(v: float) -> void:
	if G.settings.shake: shake = max(shake, v)

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
		if fairy.visible and e.position.distance_to(fairy.position) < 110: _collect_fairy(); return
		tap(e.position)

func rage_mult() -> float:
	return _skill("rage").power if skill_active.get("rage", 0.0) > 0 else 1.0

func _skill(id: String) -> Dictionary:
	for k in G.C.skills:
		if k.id == id: return k
	return {}

func tap(pos: Vector2, silent := false) -> void:
	if respawn > 0 or dying: return
	G.total_taps += 1; G.qp("taps")
	if G.total_taps == 10000: G.unlock("taps_10k")
	var d: float = G.tap_dmg() * rage_mult()
	var crit: bool = randf() < G.crit_chance()
	if crit: d *= G.crit_mult()
	damage(d, pos, crit)
	if not silent:
		play("crit" if crit else "tap")
		if crit: Sound.haptic(30, 0.7)
		_hero_attack(pos, "overhead" if crit else ATK_SET[atk_i % ATK_SET.size()])
		atk_i += 1
	if G.active_pet != "":
		pet_taps += 1
		if pet_taps >= int(G.K.pets.strike_every): pet_taps = 0; _pet_strike()

func _pet_strike() -> void:
	var tgt := enemy.position + Vector2(randf_range(-80, 40), -enemy.size.y * 0.55)
	var start := hero_holder.position + pet_spr.position
	var tw := pet_spr.create_tween()
	tw.tween_property(pet_spr, "position", tgt - hero_holder.position, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): damage(G.pet_damage(), tgt, false, Color(1, 0.75, 0.3)))
	tw.tween_property(pet_spr, "position", start - hero_holder.position, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hero_attack(pos: Vector2, kind := "slash") -> void:
	hero.attack(kind)
	slash.position = pos - Vector2(260, 260); slash.rotation = {"slash": 0.3, "upper": -2.4, "thrust": 0.0, "spin": 1.2, "overhead": 0.9}.get(kind, 0.0) + randf_range(-0.25, 0.25)
	slash.scale = Vector2(0.6, 0.6) * (1.4 if kind == "overhead" else 1.0); slash.modulate.a = 1
	var st := slash.create_tween().set_parallel()
	st.tween_property(slash, "scale", slash.scale * 1.9, 0.16)
	st.tween_property(slash, "modulate:a", 0.0, 0.18)

func damage(d: float, pos: Vector2, crit := false, col := Color.WHITE) -> void:
	if respawn > 0 or dying: return
	if raid: raid_dmg += d
	else: enemy_hp -= d
	if G.settings.dmg_numbers: _float_text(G.fmt(d), pos, Color(1, 0.3, 0.2) if crit else col, 76 if crit else 52, crit)
	var mass: float = MOB[enemy_id][2][7]
	enemy.hit_flash(0.95 if crit else 0.7)
	var f := (2.2 if crit else 1.0) / mass
	enemy.kick(520 * f, 1.4 * f, 2.2 * f, -90 * f)
	hit_fx.position = pos; hit_fx.restart(); hit_fx.emitting = true
	if quality >= 1 and randf() < (0.6 if crit else 0.25):
		ichor_fx.position = pos; ichor_fx.direction = Vector2(1, -1); ichor_fx.restart(); ichor_fx.emitting = true
	if crit: _shake(0.25)
	if raid: _raid_bar(); return
	_check_wounds()
	if enemy_hp <= 0: kill()

## Progressive wounds: cracks at 75%, cuts at 50%, deep gashes + limp + dripping at 25% HP.
func _check_wounds(instant := false) -> void:
	var fr: float = enemy_hp / enemy_max
	var s := 3 if fr <= 0.25 else (2 if fr <= 0.5 else (1 if fr <= 0.75 else 0))
	while wound_stage < s:
		wound_stage += 1
		var key := "wound%d" % wound_stage
		if instant: enemy.set_param(key, 1.0)
		else:
			var tw := enemy.create_tween()
			tw.tween_method(func(v: float): enemy.set_param(key, v), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			enemy.kick(700, 2.0, -1.5, -200)
			ichor_fx.position = enemy.position + Vector2(0, -enemy.size.y * 0.5); ichor_fx.direction = Vector2(0, -1); ichor_fx.restart(); ichor_fx.emitting = true
		enemy.set_param("darken", 0.08 * wound_stage)
		if wound_stage == 3:
			enemy.tilt_target = 0.07; enemy.breathe_speed *= 1.6  # limp + heavy breathing
			if quality >= 1:
				drip_fx.position = enemy.position + Vector2(0, -enemy.size.y * 0.45); drip_fx.emitting = true

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
	G.stats.kills += 1; G.qp("kills")
	_coins(int(clamp(log(g + 1) / 2, 3, 12)))
	play("coin"); play("dissolve")
	var c: Vector2 = enemy.position + Vector2(0, -enemy.size.y * 0.45)
	death_fx.position = c; death_fx.restart(); death_fx.emitting = true
	drip_fx.emitting = false
	enemy.kick(900, 3.0, -2.5, -400)
	var tw := enemy.create_tween()
	if enemy is SkelActor and enemy.has_clip("death"):
		enemy.die(); tw.tween_interval(0.25)
	tw.tween_method(func(v: float): enemy.set_param("dissolve", v), 0.0, 1.0, 0.5)
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
		_gear_drop()
		_story_for_stage(G.stage, G.stage > was)
	else:
		G.kills += 1
	respawn = max(G.C.respawn_delay, 0.5)

func _gear_drop() -> void:
	var chance: float = float(G.K.gear.boss_drop_chance) + G.tv("t_gear")
	if randf() < chance or int(G.stats.bosses) % int(G.K.gear.guaranteed_every) == 0:
		var gg: Dictionary = G.roll_gear()
		if gg.is_empty(): toast(G.tr_("inv_full")); return
		toast(G.tr_("gear_drop") % _gear_name(gg))
		_celebrate(level_fx, Color.html(G.K.gear.rarity_colors[int(gg.r)]))

func _story_for_stage(s: int, first: bool) -> void:
	if not first: return
	var m := {2: ["boss1"], 5: ["stage5"], 11: ["boss10", "biome_cave"], 21: ["biome_lava"], 31: ["biome_ice"], 41: ["boss40", "loop41"], 50: ["stage50"]}
	for id in m.get(s, []): queue_story(id)

func queue_story(id: String) -> void:
	if shot_mode or G.story_seen.has(id) or not StoryOverlay.has_scene(id): return
	story_queue.append(id)
	if not story_open: _next_story()

func _next_story() -> void:
	if story_queue.is_empty(): story_open = false; _music(); return
	var id: String = story_queue.pop_front()
	G.story_seen[id] = true; G.save_game()
	story_open = true; shake = 0.0; battle.position = Vector2.ZERO
	var s := StoryOverlay.new(); add_child(s); s.start(id)
	s.finished.connect(func(): story_open = false; _next_story())

func _coins(n: int) -> void:
	var start: Vector2 = enemy.position + Vector2(0, -160)
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
	level_fx.position = hero_holder.position + Vector2(0, -200); level_fx.restart(); level_fx.emitting = true
	hero.kick(0, 0, -2.5, -500)
	if G.hero_lv % 50 == 0:
		play("levelup"); _banner(G.tr_("level_up"), Color(1, 0.9, 0.3)); _celebrate(level_fx, Color(1, 0.9, 0.4))
	else:
		play("level")

func _use_skill(k: Dictionary) -> void:
	if skill_cd[k.id] > 0 or G.hero_lv < k.unlock_level: return
	skill_cd[k.id] = float(k.cooldown) * G.cooldown_mult(); play("skill"); G.qp("skills"); Sound.haptic(20, 0.4)
	var b: Button = skill_btns[k.id]
	b.pivot_offset = b.size / 2
	var tw := b.create_tween(); tw.tween_property(b, "rotation", 0.2, 0.06); tw.tween_property(b, "rotation", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC)
	match k.id:
		"blade":
			_hero_attack(Vector2(700, 700), "spin")
			damage(G.tap_dmg() * k.power, Vector2(700, 700), true, Color(0.6, 0.9, 1)); _shake(0.4)
		"ward":
			if boss or raid: boss_left += 15
			else: skill_cd[k.id] = 0
		_:
			skill_active[k.id] = k.duration

func _fairy_interval() -> float:
	var f: Dictionary = G.K.fairy
	var rate: float = (1.0 + G.tv("t_fairy")) * (float(G.K.festival.fairy_rate) if G.festival() else 1.0)
	return randf_range(float(f.min_s), float(f.max_s)) / rate

func _collect_fairy() -> void:
	fairy.visible = false; fairy_t = -1.0; fairy_wait = _fairy_interval()
	var f: Dictionary = G.K.fairy; var roll := randi() % 3; var txt := ""
	if roll == 0:
		var g: float = G.offline_income(float(f.gold_seconds)) * 2.0; G.gold += g; _coins(10); txt = "+" + G.fmt(g)
	elif roll == 1: G.grant({"gems": int(f.gems)}); txt = "+%d 💎" % int(f.gems)
	else: G.grant({"essence": int(f.essence)}); txt = "+%d %s" % [int(f.essence), G.tr_("essence")]
	G.stats.fairies += 1; G.qp("fairies"); play("levelup", false)
	_float_text(txt, fairy.position, Color(1, 0.75, 1), 60, true)
	toast(G.tr_("fairy_got") % txt)

func _process(dt: float) -> void:
	t += dt
	var cdm: float = 1.0
	for id in skill_cd:
		var was: float = skill_cd[id]
		skill_cd[id] = max(0.0, skill_cd[id] - dt * cdm); skill_active[id] = max(0.0, skill_active[id] - dt)
		if was > 0 and skill_cd[id] <= 0 and G.settings.notif_skills and G.hero_lv >= _skill(id).unlock_level and _skill(id).cooldown >= 30:
			toast(G.tr_("skill_ready") % G.tr_("s_" + id)); _pulse(skill_btns[id])
	if G.auto_tap_left > 0: G.auto_tap_left = max(0.0, G.auto_tap_left - dt)
	if pet_spr.visible: pet_spr.offset.y = sin(t * 3.0) * 30.0
	# fairy flight
	if fairy_t >= 0:
		fairy_t += dt
		fairy.position = Vector2(-80 + fairy_t * 150, 450 + sin(fairy_t * 2.4) * 120)
		if fairy.position.x > 1160: fairy.visible = false; fairy_t = -1.0; fairy_wait = _fairy_interval()
	elif not raid:
		fairy_wait -= dt
		if fairy_wait <= 0: fairy_t = 0.0; fairy.visible = true
	if respawn > 0:
		respawn -= dt
		if respawn <= 0: spawn()
	elif not dying:
		var dmul: float = _skill("meteor").power if skill_active["meteor"] > 0 else 1.0
		var d: float = G.dps() * dmul * dt
		if d > 0:
			if raid: raid_dmg += d; _raid_bar()
			else:
				enemy_hp -= d; _check_wounds()
				if enemy_hp <= 0: kill()
		if skill_active["haste"] > 0:
			haste_acc += dt * _skill("haste").power
			while haste_acc >= 1: haste_acc -= 1; tap(Vector2(randf_range(560, 860), randf_range(500, 800)), true)
		if G.auto_tap_left > 0:
			auto_acc += dt * float(G.S.gems.sinks.auto_tapper_tps)
			while auto_acc >= 1: auto_acc -= 1; tap(Vector2(randf_range(560, 860), randf_range(500, 800)), true)
		if (boss or raid) and not dying:
			roar_t -= dt
			if roar_t <= 0: roar_t = randf_range(4.0, 6.0); _roar()
			boss_left -= dt
			if boss_left <= 0:
				if raid: _raid_end()
				else:
					farming = true; G.kills = 0; boss_btn.visible = true
					vignette.create_tween().tween_property(vignette, "modulate:a", 0.0, 0.4)
					_float_text(G.tr_("failed"), Vector2(300, 500), Color(1, 0.4, 0.3), 64); spawn()
	if shake > 0:
		shake -= dt; battle.position = Vector2(randf_range(-14, 14), randf_range(-14, 14)) if shake > 0 else Vector2.ZERO
	ui_acc += dt
	if ui_acc > 0.15: ui_acc = 0; _update_hud()
	save_acc += dt
	if save_acc > 10: save_acc = 0; G.save_game()

# ---------------- Rift Raid (30 s damage race vs. the Wyrm, scored by tier) ----------------
func _raid_bar() -> void:
	var sc: int = G.raid_score(raid_dmg)
	hp_bar.max_value = 1000; hp_bar.value = 10 * (sc % 100)
	hp_lbl.text = "%s %s" % [G.tr_("tier"), G.raid_fmt(sc)]

func start_raid() -> void:
	if raid or G.raid_tickets <= 0 or dying: return
	G.raid_tickets -= 1; G.save_game()
	_close_modal()
	raid = true; raid_dmg = 0.0; farming = false; boss_btn.visible = false
	spawn()
	if not G.story_seen.has("raid1"): queue_story("raid1")

func _raid_end() -> void:
	raid = false
	var sc: int = G.raid_score(raid_dmg)
	var best_before: int = G.raid_best
	var r: Dictionary = G.raid_finish(sc)
	Online.submit_raid()
	dying = true; enemy.set_param("dissolve", 0.0)
	enemy.create_tween().tween_method(func(v: float): enemy.set_param("dissolve", v), 0.0, 1.0, 0.6)
	vignette.create_tween().tween_property(vignette, "modulate:a", 0.0, 0.4)
	_celebrate(prestige_fx, Color(0.8, 0.5, 1))
	var txt: String = G.tr_("raid_result") % [G.raid_fmt(sc), _reward_text(r)]
	if sc > best_before: txt += "\n★ " + G.tr_("new_best")
	popup(txt)
	respawn = 0.8

func _reward_text(r: Dictionary) -> String:
	var parts := []
	if r.has("gems"): parts.append("+%d %s" % [int(r.gems), G.tr_("gems")])
	if r.has("essence"): parts.append("+%d %s" % [int(r.essence), G.tr_("essence")])
	if r.has("eggs"): parts.append("+%d %s" % [int(r.eggs), G.tr_("egg")])
	if r.has("warp_h"): parts.append(G.tr_("warp_h") % int(r.warp_h))
	return ", ".join(parts)

func _update_hud() -> void:
	gold_lbl.text = G.fmt(G.gold); shard_lbl.text = G.fmt(G.shards); gem_lbl.text = str(G.gems)
	var n: int = G.C.enemies_per_stage
	if raid:
		stage_lbl.text = G.tr_("raid_title")
		timer_lbl.text = "%.1f" % max(boss_left, 0)
	else:
		stage_lbl.text = "%s %d  %s" % [G.tr_("stage"), G.stage, (G.tr_("boss") if boss else "%d/%d" % [min(G.kills, n), n])]
		if G.festival(): stage_lbl.text += "  ✦" + G.tr_("festival")
		hp_bar.max_value = 1000; hp_bar.value = lerp(hp_bar.value, 1000 * max(enemy_hp, 0) / enemy_max, 0.6)
		hp_lbl.text = "%s / %s" % [G.fmt(max(enemy_hp, 0)), G.fmt(enemy_max)]
		timer_lbl.text = ("%.1f" % boss_left) if boss else ""
	for k in G.C.skills:
		var b: Button = skill_btns[k.id]
		var locked: bool = G.hero_lv < k.unlock_level
		b.disabled = locked or skill_cd[k.id] > 0
		b.text = ("%d" % k.unlock_level) if locked else ("%d" % ceil(skill_cd[k.id]) if skill_cd[k.id] > 0 else "")
		b.modulate = Color(1, 1, 0.6) if skill_active[k.id] > 0 else Color.WHITE
	side_btns.raid.text = "%s %d" % [G.tr_("side_raid"), G.raid_tickets]
	var qd := 0
	for q in G.quests:
		if q.done: qd += 1
	side_btns.quests.text = "%s %d/%d" % [G.tr_("side_quests"), qd, G.quests.size()]
	for u in row_updaters: u.call()

# ============================== tabs ==============================
func _show_tab(i: int, instant := false) -> void:
	var dir := signf(i - cur_tab) if i != cur_tab else 1.0
	cur_tab = i
	var w: float = 1080.0 / TAB_KEYS.size()
	for j in TAB_KEYS.size(): tab_btns[j].modulate = Color(1.3, 1.2, 0.8) if j == i else Color(0.85, 0.85, 0.9)
	if instant:
		tab_hl.position.x = i * w + 10; tab_hl.size.x = w - 20; _refresh_tab(true); return
	var hl := create_tween(); hl.tween_property(tab_hl, "position:x", i * w + 10, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	play("whoosh")
	var tw := create_tween()
	tw.tween_property(tab_scroll, "modulate:a", 0.0, 0.09)
	tw.parallel().tween_property(tab_scroll, "position:x", -60.0 * dir, 0.09)
	tw.tween_callback(func():
		_refresh_tab(true); tab_scroll.scroll_vertical = 0; tab_scroll.position.x = 80.0 * dir)
	tw.tween_property(tab_scroll, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tab_scroll, "modulate:a", 1.0, 0.18)

var _last_sig := ""
func _refresh_tab(force := false) -> void:
	var sig := "%d|%d|%s|%d|%d|%s|%s|%d|%s|%s|%d|%d" % [cur_tab, hero_sub, G.lang, G.comp.count(0), G.owned.size(), G.aura, Online.signed_in,
		G.gear.size(), str(G.equipped), str(G.pets) + G.active_pet, G.tree_spent(), G.eggs]
	if not force and sig == _last_sig: return
	_last_sig = sig
	_tab_names()
	_update_pet()
	for c in tab_box.get_children(): c.queue_free()
	row_updaters.clear()
	match cur_tab:
		0:
			_subtabs()
			match hero_sub:
				0: _tab_hero()
				1: _tab_gear()
				2: _tab_pets()
				3: _tab_tree()
		1: _tab_comp()
		2: _tab_art()
		3: _tab_shop()
		4: _tab_settings()
	var i := 0
	for c in tab_box.get_children():
		if c is Control:
			c.modulate.a = 0
			c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2).set_delay(0.03 * min(i, 12)); i += 1
	_update_hud()

func _row(icon: Texture2D, on_buy: Callable, btn_col := Color(0.2, 0.5, 0.15), parent: Control = null) -> Array:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 14); (parent if parent else tab_box).add_child(hb)
	var ic := _sprite("", Vector2.ZERO); ic.texture = icon; ic.custom_minimum_size = Vector2(120, 120); hb.add_child(ic)
	var l := _wrap(_lbl("", 32)); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(l)
	var b := _btn("", btn_col); b.custom_minimum_size = Vector2(300, 110); b.pressed.connect(on_buy); hb.add_child(b)
	return [l, b, ic, hb]

func _header(text: String, parent: Control = null) -> void:
	var l := _lbl(text, 40, Color(1, 0.85, 0.35)); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; (parent if parent else tab_box).add_child(l)

func _note(text: String, parent: Control = null, col := Color(0.85, 0.82, 0.9)) -> Label:
	var l := _wrap(_lbl(text, 28, col)); (parent if parent else tab_box).add_child(l); return l

func _hrow(parent: Control = null) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); (parent if parent else tab_box).add_child(h); return h

func _hbtn(h: Control, text: String, fn: Callable, col := Color(0.15, 0.35, 0.6)) -> Button:
	var b := _btn(text, col); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 96
	b.add_theme_font_size_override("font_size", 30); b.pressed.connect(fn); h.add_child(b); return b

func _subtabs() -> void:
	var h := _hrow()
	for i in 4:
		var b := _hbtn(h, G.tr_(["sub_hero", "sub_gear", "sub_pets", "sub_tree"][i]), func(): hero_sub = i; play("whoosh"); _refresh_tab(true),
			Color(0.5, 0.3, 0.1) if i == hero_sub else Color(0.28, 0.16, 0.36))
		b.custom_minimum_size.y = 80

func _tab_hero() -> void:
	var r := _row(tex("res://assets/sprites/hero.png"), func():
		if G.buy_hero(): _level_up_fx())
	row_updaters.append(func():
		r[0].text = "%s  %s %d\n%s: %s\n%s: %s" % [G.tr_("title"), G.tr_("lvl"), G.hero_lv, G.tr_("tap_dmg"), G.fmt(G.tap_dmg()), G.tr_("dps"), G.fmt(G.dps())]
		r[1].text = "%s\n%s" % [G.tr_("buy"), G.fmt(G.hero_cost())]; r[1].disabled = G.gold < G.hero_cost())
	var st := _note("")
	row_updaters.append(func():
		st.text = G.tr_("hero_stats") % ["%.1f" % (G.crit_chance() * 100), "%.1f" % G.crit_mult(), "%.0f" % ((G.tap_mult() - 1) * 100), "%.0f" % ((G.ally_mult() - 1) * 100), "%.0f" % ((G.gold_mult() - 1) * 100), "%.0f" % ((1 - G.cooldown_mult()) * 100)])
	for k in G.C.skills:
		_note("• %s — %s" % [G.tr_("s_" + k.id), G.tr_("unlock_at") % k.unlock_level], null, Color.WHITE)

# ---- gear ----
func _gear_name(g: Dictionary) -> String:
	return "%s «%s» +%d" % [G.tr_("slot_" + g.slot), G.tr_("set_" + g.set), int(g.lv)]

func _gear_stat_text(g: Dictionary) -> String:
	return G.tr_("gstat_" + G.K.gear.slot_stat[g.slot]) % ("%.0f" % (G.gear_value(g) * 100))

func _tab_gear() -> void:
	var top := _hrow()
	var ess := _lbl("", 32, Color(0.7, 1, 0.8)); ess.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(ess)
	var cb := _hbtn(top, "", func():
		var g: Dictionary = G.craft()
		if not g.is_empty(): toast(G.tr_("gear_drop") % _gear_name(g)); _celebrate(level_fx, Color.html(G.K.gear.rarity_colors[int(g.r)])), Color(0.2, 0.5, 0.15))
	row_updaters.append(func():
		ess.text = "%s: %d   %d/%d" % [G.tr_("essence"), G.essence, G.gear.size(), int(G.K.gear.inventory_cap)]
		cb.text = G.tr_("craft") % int(G.K.gear.craft_cost); cb.disabled = G.essence < int(G.K.gear.craft_cost))
	var sets := ""
	for sid in G.K.gear.sets:
		var n: int = G.set_count(sid)
		if n > 0: sets += "%s %d/4  " % [G.tr_("set_" + sid), n]
	_note(G.tr_("sets_info") + ("\n" + sets if sets != "" else ""))
	if G.gear.is_empty(): _note(G.tr_("gear_empty"), null, Color(1, 0.85, 0.6)); return
	var eq_ids: Array = G.equipped.values()
	var list: Array = G.gear.duplicate()
	list.sort_custom(func(a, b):
		var ea := eq_ids.has(int(a.id)); var eb := eq_ids.has(int(b.id))
		if ea != eb: return ea
		return int(a.r) * 100 + int(a.lv) > int(b.r) * 100 + int(b.lv))
	for g in list:
		var hb := _hrow()
		var ic := _sprite("res://assets/ui/gear_%s.png" % g.slot, Vector2.ZERO); ic.custom_minimum_size = Vector2(100, 100); hb.add_child(ic)
		var col := Color.html(G.K.gear.rarity_colors[int(g.r)])
		var l := _wrap(_lbl("", 28, col)); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(l)
		var on: bool = eq_ids.has(int(g.id))
		var eb := _btn(G.tr_("equipped") if on else G.tr_("equip"), Color(0.15, 0.35, 0.6)); eb.custom_minimum_size = Vector2(150, 96); eb.disabled = on
		eb.add_theme_font_size_override("font_size", 26); eb.pressed.connect(func(): G.equip(g); play("level")); hb.add_child(eb)
		var up := _btn("", Color(0.2, 0.5, 0.15)); up.custom_minimum_size = Vector2(150, 96); up.add_theme_font_size_override("font_size", 26)
		up.pressed.connect(func():
			if G.enhance(g): play("level"); _pulse(ic)); hb.add_child(up)
		var sv := _btn("♻", Color(0.5, 0.15, 0.15)); sv.custom_minimum_size = Vector2(90, 96); sv.disabled = on
		sv.pressed.connect(func(): G.salvage(g); play("coin")); hb.add_child(sv)
		row_updaters.append(func():
			l.text = "%s\n%s · %s" % [_gear_name(g), G.tr_("r%d" % int(g.r)), _gear_stat_text(g)]
			var mx: bool = int(g.lv) >= int(G.K.gear.enhance_max)
			up.text = G.tr_("max") if mx else "▲ %d" % G.enhance_cost(g); up.disabled = mx or G.essence < G.enhance_cost(g))

# ---- pets ----
func _tab_pets() -> void:
	if not G.pets_unlocked():
		_note(G.tr_("pets_locked") % int(G.K.pets.unlock_stage), null, Color(1, 0.85, 0.6)); return
	var h := _hrow()
	var el := _lbl("", 32, Color(1, 0.9, 0.6)); el.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(el)
	var hb := _hbtn(h, G.tr_("hatch"), func():
		var id: String = G.hatch()
		if id != "":
			_celebrate(level_fx, Color(1, 0.8, 0.4)); toast(G.tr_("hatched") % G.tr_("pet_" + id)); _update_pet()
			if not G.story_seen.has("pet1"): queue_story("pet1"), Color(0.2, 0.5, 0.15))
	var cost := int(G.K.pets.egg_gem_cost)
	var bb := _hbtn(h, "", func():
		if G.spend_gems(cost): G.eggs += 1; G.changed.emit(); G.save_game(), Color(0.55, 0.15, 0.45))
	row_updaters.append(func():
		el.text = "%s: %d" % [G.tr_("egg"), G.eggs]; hb.disabled = G.eggs <= 0
		bb.text = G.tr_("buy_egg") % cost; bb.disabled = G.gems < cost)
	_note(G.tr_("pets_info") % int(G.K.pets.strike_every))
	for p in G.K.pets.list:
		var pid: String = p.id
		var r := _row(tex("res://assets/sprites/pet_%s.png" % pid), func(): G.active_pet = pid; G.changed.emit(); G.save_game(); play("level"), Color(0.15, 0.35, 0.6))
		var lv: int = G.pets[pid]
		var v: float = float(p.per_level) * lv
		r[0].text = "%s  %s %d\n%s" % [G.tr_("pet_" + pid), G.tr_("lvl"), lv, G.tr_("gstat_" + p.stat) % ("%.1f" % (v * 100) if p.stat == "crit" else "%.0f" % (v * 100))]
		r[1].text = G.tr_("active") if G.active_pet == pid else (G.tr_("set_active") if lv > 0 else "—")
		r[1].disabled = lv == 0 or G.active_pet == pid
		if lv == 0: r[2].modulate = Color(0, 0, 0, 0.6)

# ---- skill tree ----
func _tab_tree() -> void:
	var h := _hrow()
	var pl := _wrap(_lbl("", 30, Color(0.7, 0.9, 1))); pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(pl)
	var rb := _hbtn(h, G.tr_("respec") % int(G.K.tree.respec_cost), func():
		if G.tree_respec(): play("prestige"), Color(0.5, 0.15, 0.15))
	row_updaters.append(func():
		pl.text = G.tr_("tree_points") % [G.tree_points() - G.tree_spent(), G.tree_points(), int(G.K.tree.stages_per_point)]
		rb.disabled = G.tree_spent() == 0 or G.gems < int(G.K.tree.respec_cost))
	for br in G.K.tree.branches:
		_header(G.tr_("br_" + br))
		for n in G.K.tree.branches[br]:
			var nid: String = n[0]; var per: float = n[1]
			var r := _row(tex("res://assets/ui/skill_%s.png" % {"blade": "blade", "command": "ward", "fortune": "goldrain"}[br]), func():
				if G.tree_buy(nid): play("level"), Color(0.2, 0.45, 0.6))
			r[2].custom_minimum_size = Vector2(90, 90)
			row_updaters.append(func():
				var lv: int = G.tree[nid]
				var v: float = per * lv
				var vs: String = ("%.0f" % v) if nid == "t_boss" else ("%.1f" % (v * 100))
				r[0].text = "%s  %d/%d\n%s" % [G.tr_("tn_" + nid), lv, int(G.K.tree.max), G.tr_("td_" + nid) % vs]
				var mx: bool = lv >= int(G.K.tree.max)
				r[1].text = G.tr_("max") if mx else "+1"; r[1].disabled = mx or G.tree_spent() >= G.tree_points())

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
		if G.comp[i] == 0: break

func r_ic(i: int) -> Control:
	var n := tab_box.find_child("ic%d" % i, true, false)
	return n if n else tab_box

func _tab_art() -> void:
	var pb := _btn("", Color(0.45, 0.15, 0.6)); pb.custom_minimum_size = Vector2(0, 100); tab_box.add_child(pb)
	var info := _note("")
	pb.pressed.connect(func():
		var first: bool = G.prestiges == 0
		var s: int = G.prestige()
		if s > 0:
			play("prestige"); _celebrate(prestige_fx, Color(0.6, 0.85, 1)); _banner(G.tr_("prestige_done") % G.fmt(s), Color(0.6, 0.85, 1))
			farming = false; boss_btn.visible = false; cur_biome = ""; spawn(); _refresh_tab(true)
			if first: queue_story("prestige1"))
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
		["g_egg", int(G.K.pets.egg_gem_cost), func(): G.eggs += 1; G.save_game(); toast(G.tr_("egg") + " +1")],
	]
	for s in sinks:
		var key: String = s[0]; var cost: int = s[1]; var fn: Callable = s[2]
		var r := _row(gem_icon, func():
			if G.spend_gems(cost): fn.call(); _celebrate(level_fx, Color(1, 0.5, 0.85)), Color(0.55, 0.15, 0.45))
		r[2].modulate = Color(1, 0.45, 0.8)
		if key == "g_egg": r[2].texture = tex("res://assets/sprites/pet_drake.png"); r[2].modulate = Color.WHITE
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
	if not Online.billing_ready: _note(G.tr_("billing_unavail"), null, Color(1, 0.75, 0.6))
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

# ============================== settings ==============================
func _slider(label_key: String, key: String) -> void:
	var h := _hrow()
	var l := _lbl(G.tr_(label_key), 30); l.custom_minimum_size.x = 330; h.add_child(l)
	var s := HSlider.new(); s.min_value = 0; s.max_value = 1; s.step = 0.05; s.value = float(G.settings[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER; s.custom_minimum_size.y = 70
	s.add_theme_constant_override("grabber_offset", 0); h.add_child(s)
	var pct := _lbl("%d%%" % int(s.value * 100), 30, Color(1, 0.9, 0.6)); pct.custom_minimum_size.x = 100; h.add_child(pct)
	s.value_changed.connect(func(v: float): G.settings[key] = v; pct.text = "%d%%" % int(v * 100); Sound.apply())
	s.drag_ended.connect(func(_c): G.save_game(); play("click", false))

func _toggle(label_key: String, key: String, after := Callable()) -> void:
	var b := _btn("", Color(0.22, 0.18, 0.34)); b.custom_minimum_size.y = 90; b.add_theme_font_size_override("font_size", 30); tab_box.add_child(b)
	var upd := func(): b.text = "%s:  %s" % [G.tr_(label_key), G.tr_("on") if G.settings[key] else G.tr_("off")]
	upd.call()
	b.pressed.connect(func():
		G.settings[key] = not G.settings[key]; G.save_game(); upd.call()
		if after.is_valid(): after.call()
		if key == "haptics" and G.settings[key]: Sound.haptic(40))

func _choice(label_key: String, key: String, values: Array, names: Array, after := Callable()) -> void:
	var h := _hrow()
	var l := _lbl(G.tr_(label_key), 30); l.custom_minimum_size.x = 330; h.add_child(l)
	for i in values.size():
		var v = values[i]
		var b := _hbtn(h, names[i], func():
			G.settings[key] = v; G.save_game(); play("click", false)
			if after.is_valid(): after.call()
			_refresh_tab(true), Color(0.5, 0.3, 0.1) if G.settings[key] == v else Color(0.22, 0.18, 0.34))
		b.custom_minimum_size.y = 84

func _tab_settings() -> void:
	_header(G.tr_("set_audio"))
	_slider("vol_master", "vol_master"); _slider("vol_music", "vol_music"); _slider("vol_sfx", "vol_sfx")
	_toggle("haptics", "haptics")
	_header(G.tr_("set_graphics"))
	_choice("quality", "quality", [0, 1, 2], [G.tr_("q_low"), G.tr_("q_med"), G.tr_("q_high")], apply_quality)
	_choice("fps", "fps", [30, 60], ["30", "60"], apply_quality)
	_toggle("battery", "battery", apply_quality)
	_toggle("dmg_numbers", "dmg_numbers")
	_toggle("shake", "shake")
	_header(G.tr_("set_notif"))
	_toggle("notif_offline", "notif_offline")
	_toggle("notif_skills", "notif_skills")
	_note(G.tr_("notif_note"), null, Color(0.7, 0.7, 0.8))
	_header(G.tr_("language"))
	var lh := _hrow()
	for lg in [["ru", "Русский"], ["en", "English"]]:
		_hbtn(lh, lg[1], func(): G.lang = lg[0]; G.save_game(); _tab_names(); _update_hud(); _refresh_tab(true),
			Color(0.5, 0.3, 0.1) if G.lang == lg[0] else Color(0.22, 0.18, 0.34))
	_header(G.tr_("set_account"))
	if not Online.gpgs_available:
		_note(G.tr_("gunavail"), null, Color(1, 0.75, 0.6))
	elif not Online.signed_in:
		var g := _btn(G.tr_("gsign"), Color(0.15, 0.35, 0.6)); g.pressed.connect(Online.sign_in); tab_box.add_child(g)
	else:
		_note(G.tr_("gsigned") + (" — " + Online.player_name if Online.player_name != "" else ""), null, Color(0.6, 1, 0.6))
		var row := _hrow()
		_hbtn(row, G.tr_("cloud_save"), func(): Online.save_cloud(true))
		_hbtn(row, G.tr_("cloud_load"), func(): Online.load_cloud(true))
		var row2 := _hrow()
		_hbtn(row2, G.tr_("achievements"), Online.show_achievements)
		_hbtn(row2, G.tr_("side_ranking"), _ranking)
		_note(G.tr_("signout_note"), null, Color(0.7, 0.7, 0.8))
	var rb := _btn(G.tr_("restore"), Color(0.3, 0.3, 0.4)); rb.pressed.connect(Online.restore); tab_box.add_child(rb)
	_header(G.tr_("set_about"))
	var ab := _hrow()
	_hbtn(ab, G.tr_("credits"), _credits, Color(0.3, 0.3, 0.4))
	_hbtn(ab, G.tr_("privacy_btn"), func(): OS.shell_open(str(G.S.get("privacy_url", "https://github.com/Shaman-ATTA/DL/blob/main/PRIVACY.md"))), Color(0.3, 0.3, 0.4))
	var badges := ""
	if G.owned.has("supporter"): badges += "  ★ " + G.tr_("supporter")
	if G.owned.has("vip"): badges += "  ♛ " + G.tr_("vip")
	_note("%s: %d%s\n%s: %d\n%s\n\nv%s" % [G.tr_("best"), G.max_stage, badges, G.tr_("achievements"), G.ach.size(), G.tr_("privacy"),
		ProjectSettings.get_setting("application/config/version", "1.2.0")])
	var rs := _btn(G.tr_("reset"), Color(0.5, 0.1, 0.1)); rs.pressed.connect(_confirm_reset); tab_box.add_child(rs)

func _credits() -> void:
	var b := _open_modal(G.tr_("credits"))
	var l := RichTextLabel.new(); l.bbcode_enabled = true; l.fit_content = true; l.custom_minimum_size.x = 900
	l.add_theme_font_size_override("normal_font_size", 28); l.add_theme_font_size_override("bold_font_size", 30)
	l.text = G.tr_("credits_text"); b.add_child(l)

func _confirm_reset() -> void:
	var b := _open_modal(G.tr_("reset"))
	_note(G.tr_("reset_warn"), b, Color(1, 0.7, 0.6))
	var step := [0]
	var yb := _btn(G.tr_("reset_yes"), Color(0.6, 0.1, 0.1)); yb.custom_minimum_size.y = 110; b.add_child(yb)
	yb.pressed.connect(func():
		step[0] += 1
		if step[0] == 1: yb.text = G.tr_("reset_again"); _pulse(yb); return
		G.reset_all(); get_tree().paused = false; get_tree().reload_current_scene())
	var nb := _btn(G.tr_("no"), Color(0.2, 0.5, 0.15)); nb.custom_minimum_size.y = 100; nb.pressed.connect(_close_modal); b.add_child(nb)

# ============================== modals ==============================
func _open_modal(title: String) -> VBoxContainer:
	if modal and is_instance_valid(modal): modal.queue_free()
	var root := Control.new(); add_child(root); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal = root
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.size = Vector2(1080, 1920); root.add_child(dim)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: _close_modal())
	var p := PanelContainer.new(); p.position = Vector2(50, 230); p.size = Vector2(980, 1380)
	p.add_theme_stylebox_override("panel", UI.panel(Color(0.16, 0.08, 0.24, 0.98))); root.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); p.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	var t_ := _lbl(title, 46, Color(1, 0.85, 0.35)); t_.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t_.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; top.add_child(t_)
	var x := _btn("✕", Color(0.5, 0.15, 0.15)); x.custom_minimum_size = Vector2(90, 90); x.pressed.connect(_close_modal); top.add_child(x)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	modal_box = VBoxContainer.new(); modal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; modal_box.add_theme_constant_override("separation", 16); sc.add_child(modal_box)
	p.pivot_offset = p.size / 2; p.scale = Vector2(0.85, 0.85); root.modulate.a = 0
	var tw := root.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	play("whoosh")
	return modal_box

func _close_modal() -> void:
	if not modal or not is_instance_valid(modal): return
	var m := modal; modal = null
	var tw := m.create_tween(); tw.tween_property(m, "modulate:a", 0.0, 0.15); tw.tween_callback(m.queue_free)

func _quests() -> void:
	var b := _open_modal(G.tr_("side_quests"))
	_note(G.tr_("quests_info") % [int(G.K.quests.reward_gems), int(G.K.quests.reward_essence)], b)
	for q in G.quests:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", UI.panel(Color(0.25, 0.4, 0.2, 0.9) if q.done else Color(0.22, 0.16, 0.32, 0.9))); b.add_child(p)
		var v := VBoxContainer.new(); p.add_child(v)
		v.add_child(_lbl(("✔ " if q.done else "") + G.tr_("q_" + q.k), 32))
		var pb := ProgressBar.new(); pb.max_value = int(q.goal); pb.value = min(int(q.p), int(q.goal)); pb.custom_minimum_size.y = 34; pb.show_percentage = false; v.add_child(pb)
		v.add_child(_lbl("%d / %d" % [min(int(q.p), int(q.goal)), int(q.goal)], 26, Color(0.85, 0.85, 0.9)))
	_note(G.tr_("quest_bonus") % int(G.K.quests.all_bonus_eggs) + ("  ✔" if G.quest_bonus else ""), b, Color(1, 0.9, 0.6))
	_note(G.tr_("quest_reset"), b, Color(0.7, 0.7, 0.8))

func _raid_menu() -> void:
	var b := _open_modal(G.tr_("raid_title"))
	var ic := _sprite("res://assets/sprites/boss_wyrm.png", Vector2.ZERO); ic.custom_minimum_size = Vector2(0, 380); b.add_child(ic)
	_note(G.tr_("raid_info") % int(G.K.raid.seconds), b)
	_note("%s: %d / %d\n%s: %s" % [G.tr_("raid_tickets"), G.raid_tickets, int(G.K.raid.tickets), G.tr_("raid_best"), G.raid_fmt(G.raid_best)], b, Color(1, 0.9, 0.6))
	var sb := _btn(G.tr_("raid_start"), Color(0.6, 0.2, 0.1)); sb.custom_minimum_size.y = 120; sb.disabled = G.raid_tickets <= 0 or raid or boss; b.add_child(sb)
	sb.pressed.connect(func(): _close_modal(); start_raid())
	if boss: _note(G.tr_("raid_after_boss"), b, Color(1, 0.7, 0.6))
	var rb := _btn(G.tr_("side_ranking"), Color(0.15, 0.35, 0.6)); rb.pressed.connect(func(): lb_board = "raid"; _ranking()); b.add_child(rb)

var lb_board := "stage"
var lb_span := 1
var lb_list: VBoxContainer
func _ranking() -> void:
	var b := _open_modal(G.tr_("side_ranking"))
	var h := _hrow(b)
	for bd in [["stage", "lb_stage"], ["raid", "lb_raid"]]:
		_hbtn(h, G.tr_(bd[1]), func(): lb_board = bd[0]; _ranking(), Color(0.5, 0.3, 0.1) if lb_board == bd[0] else Color(0.22, 0.18, 0.34))
	var h2 := _hrow(b)
	for i in 3:
		var sb := _hbtn(h2, G.tr_(["lb_day", "lb_week", "lb_all"][i]), func(): lb_span = i; _ranking(), Color(0.15, 0.35, 0.6) if lb_span == i else Color(0.22, 0.18, 0.34))
		sb.custom_minimum_size.y = 80
	var mine: String = ("%d" % G.max_stage) if lb_board == "stage" else G.raid_fmt(G.raid_best)
	_note(G.tr_("lb_mine") % mine + ("\n" + G.tr_("lb_weekly_note") if lb_span == 1 else ""), b, Color(1, 0.9, 0.6))
	lb_list = VBoxContainer.new(); lb_list.add_theme_constant_override("separation", 6); b.add_child(lb_list)
	if Online.leaderboards_live(lb_board):
		_note(G.tr_("lb_loading"), lb_list)
		Online.load_scores(lb_board, lb_span)
		var nb := _btn(G.tr_("lb_native"), Color(0.15, 0.35, 0.6)); nb.pressed.connect(func(): Online.show_native_board(lb_board, lb_span)); b.add_child(nb)
	else:
		var msg := "gunavail" if not Online.gpgs_available else ("lb_signin" if not Online.signed_in else "lb_noid")
		_note("📴 " + G.tr_("lb_offline") + "\n" + G.tr_(msg), lb_list, Color(1, 0.75, 0.6))
		if Online.gpgs_available and not Online.signed_in:
			var g := _btn(G.tr_("gsign"), Color(0.15, 0.35, 0.6)); g.pressed.connect(Online.sign_in); b.add_child(g)

func _on_scores(board: String, span: int, rows: Array) -> void:
	if not modal or not is_instance_valid(lb_list) or board != lb_board or span != lb_span: return
	for c in lb_list.get_children(): c.queue_free()
	if rows.is_empty(): _note(G.tr_("lb_empty"), lb_list); return
	for r in rows:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", UI.panel(Color(0.45, 0.32, 0.1, 0.95) if r.me else Color(0.22, 0.16, 0.32, 0.9))); lb_list.add_child(p)
		var hb := HBoxContainer.new(); p.add_child(hb)
		var medal: String = ["🥇", "🥈", "🥉"][int(r.rank) - 1] if int(r.rank) <= 3 else "#%d" % int(r.rank)
		var a := _lbl(medal, 32, Color(1, 0.85, 0.35)); a.custom_minimum_size.x = 110; hb.add_child(a)
		var n := _lbl(str(r.name), 30); n.size_flags_horizontal = Control.SIZE_EXPAND_FILL; n.clip_text = true; hb.add_child(n)
		hb.add_child(_lbl(("%d" % int(r.score)) if board == "stage" else G.raid_fmt(int(r.score)), 32, Color(0.7, 1, 0.8)))

func _reward_line(r: Dictionary) -> String:
	var parts := []
	for k in r:
		parts.append((G.tr_("warp_h") % int(r[k])) if k == "warp_h" else "+%d %s" % [int(r[k]), G.tr_(k if k != "eggs" else "egg")])
	return ", ".join(parts)

func _calendar() -> void:
	if story_open:
		get_tree().create_timer(1.0, false).timeout.connect(_calendar); return
	var b := _open_modal(G.tr_("side_calendar"))
	var today := Time.get_date_string_from_system()
	var claimed_today: bool = G.streak_day == today
	var done: int = G.streak
	if not claimed_today and (G.streak_day != G._yesterday() or G.streak >= 7): done = 0
	_note(G.tr_("cal_info"), b)
	var grid := GridContainer.new(); grid.columns = 4; grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10); b.add_child(grid)
	for i in G.K.streak.size():
		var cur: bool = (i == done and not claimed_today) or (claimed_today and i == done - 1)
		var col := Color(0.2, 0.45, 0.2, 0.95) if i < done else (Color(0.55, 0.35, 0.1, 0.95) if cur else Color(0.22, 0.16, 0.32, 0.9))
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", UI.panel(col)); p.custom_minimum_size = Vector2(215, 190); grid.add_child(p)
		var v := VBoxContainer.new(); p.add_child(v)
		var d := _lbl(G.tr_("cal_day") % (i + 1) + ("  ✔" if i < done else ""), 28, Color(1, 0.9, 0.6)); d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(d)
		var rl := _wrap(_lbl(_reward_line(G.K.streak[i]), 26)); rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; rl.custom_minimum_size.x = 195; v.add_child(rl)
	var cb := _btn(G.tr_("cal_claimed") if claimed_today else G.tr_("cal_claim"), Color(0.2, 0.5, 0.15)); cb.custom_minimum_size.y = 120; cb.disabled = claimed_today; b.add_child(cb)
	cb.pressed.connect(func():
		var r: Dictionary = G.claim_streak()
		if r.is_empty(): return
		toast(_reward_line(r)); _celebrate(level_fx, Color(1, 0.85, 0.3)); play("levelup", false); _update_hud(); _calendar())

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
	var l := _wrap(_lbl(t_, 40)); l.custom_minimum_size = Vector2(860, 0)
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

# ============================== screenshots ==============================
## Dev-only: `godot -- --shot=<file>,<tab>,<stage>,<hero>,<lang>`; tab 10 = story scene, 11 = wounded monster, 12 = settings.
var _shot_args := []
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_mode = true
			var p: PackedStringArray = a.substr(7).split(",")
			_shot_args = [p[0], int(p[1]), int(p[2]), int(p[3]), p[4] if p.size() > 4 else "ru"]
			call_deferred("_shot")

func _shot() -> void:
	var path: String = _shot_args[0]; var tab: int = _shot_args[1]; var st: int = _shot_args[2]; var hl: int = _shot_args[3]
	G.lang = _shot_args[4]
	G.stage = st; G.max_stage = st + 8; G.run_max = st + 8; G.hero_lv = hl; G.offline_gold = 0; G.gems = 340
	for i in G.comp.size(): G.comp[i] = max(0, hl - 25 * i)
	G.gold = G.hp(st) * 40; G.shards = 340; G.kills = 10 if tab == 11 else 3; G.essence = 120
	G.streak_day = Time.get_date_string_from_system()
	for c in get_tree().get_nodes_in_group("popups"): c.queue_free()
	_close_modal()
	for k in G.C.skills: skill_cd[k.id] = 0.0
	cur_biome = ""; spawn()
	_show_tab(4 if tab == 12 else (tab if tab < 5 else 1), true)
	for i in 50: await get_tree().process_frame
	overlay.color.a = 0; banner.visible = false; toast_lbl.modulate.a = 0
	enemy.modulate = Color.WHITE; enemy.scale = Vector2.ONE
	if tab == 11:
		set_process(false); enemy_hp = enemy_max * 0.2; _check_wounds(true); hp_bar.value = 200
		boss_left = 14.2
		for i in 3: _float_text(G.fmt(G.tap_dmg() * (6 if i == 1 else 1)), Vector2(560 + i * 100, 600 - i * 40), Color(1, 0.3, 0.2) if i == 1 else Color.WHITE, 76 if i == 1 else 52, i == 1)
		ichor_fx.position = enemy.position + Vector2(0, -enemy.size.y * 0.5); ichor_fx.restart(); ichor_fx.emitting = true
		hero.attack("overhead")
		for i in 12: await get_tree().process_frame
	elif tab == 10:
		shake = 0.0; battle.position = Vector2.ZERO
		var s := StoryOverlay.new(); add_child(s); s.start("boss10")
		for i in 160: await get_tree().process_frame
	elif tab == 12:
		for i in 10: await get_tree().process_frame
		tab_scroll.scroll_vertical = 420
	elif tab == 13:  # UI smoke test: every tab, sub-tab and modal
		for tb in 5:
			for sb in (4 if tb == 0 else 1):
				hero_sub = sb; _show_tab(tb, true)
				for i in 3: await get_tree().process_frame
				for u in row_updaters: u.call()
		for f in [_quests, _raid_menu, _ranking, _calendar, _credits, _confirm_reset]:
			f.call(); for i in 3: await get_tree().process_frame
		_close_modal()
		G.eggs = 2; G.max_stage = 30; G.gems = 500; hero_sub = 2; _show_tab(0, true); await get_tree().process_frame
		G.roll_gear(3); hero_sub = 1; _show_tab(0, true); await get_tree().process_frame
		for u in row_updaters: u.call()
		_on_scores("stage", 1, [{"rank": 1, "name": "A", "score": 50, "me": false}])
		start_raid(); for i in 60: await get_tree().process_frame
		print("UITEST OK"); get_tree().quit(); return
	if tab == 11: _update_hud(); hp_bar.value = 200
	toast_lbl.modulate.a = 0; banner.visible = false
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
