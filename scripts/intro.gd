extends Control
## Animated intro: shard dust, rays, elastic shard reveal, dragon fly-by, flash,
## letter-by-letter logo drop, then a menu that slides up. Tap skips to the menu.
var G
var shard: TextureRect
var rays: TextureRect
var dragon: TextureRect
var flash: ColorRect
var logo_box: Control
var menu: VBoxContainer
var sub: Label
var skip_lbl: Label
var sign_btn: Button
var burst: CPUParticles2D
var dust: CPUParticles2D
var seq: Tween
var menu_shown := false
var leaving := false
var t := 0.0

func _ready() -> void:
	G = Game
	theme = UI.make_theme()
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.02, 0.06); bg.size = Vector2(1080, 1920); add_child(bg)
	var art := TextureRect.new(); art.texture = load("res://assets/bg/lava.jpg"); art.size = Vector2(1080, 1920)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.35, 0.25, 0.5, 0.0); add_child(art)
	var vig := TextureRect.new(); vig.texture = load("res://assets/ui/vignette.png"); vig.size = Vector2(1080, 1920)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; add_child(vig)
	dust = UI.particles(load("res://assets/ui/dot.png"), 70, 6.0, Color(0.6, 0.8, 1, 0.8), false)
	dust.position = Vector2(540, 1950); dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(560, 20); dust.gravity = Vector2(0, -40); dust.spread = 25
	dust.initial_velocity_min = 60; dust.initial_velocity_max = 200; dust.preprocess = 4.0; dust.emitting = true
	add_child(dust)
	rays = TextureRect.new(); rays.texture = load("res://assets/ui/rays.png"); rays.size = Vector2(1400, 1400)
	rays.position = Vector2(540 - 700, 640 - 700); rays.pivot_offset = Vector2(700, 700)
	rays.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; rays.modulate = Color(0.6, 0.85, 1, 0)
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; rays.material = add
	add_child(rays)
	shard = TextureRect.new(); shard.texture = load("res://assets/ui/shard.png"); shard.size = Vector2(380, 380)
	shard.position = Vector2(540 - 190, 640 - 190); shard.pivot_offset = Vector2(190, 190)
	shard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; shard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shard.scale = Vector2.ZERO; add_child(shard)
	dragon = TextureRect.new(); dragon.texture = load("res://assets/sprites/boss_dragon.png"); dragon.size = Vector2(900, 900)
	dragon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; dragon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dragon.modulate = Color(0, 0, 0, 0.85); dragon.position = Vector2(-1100, 200); dragon.pivot_offset = Vector2(450, 450)
	dragon.rotation = -0.2; add_child(dragon)
	burst = UI.particles(load("res://assets/ui/spark.png"), 90, 1.4, Color(1, 0.8, 0.4))
	burst.position = Vector2(540, 640); burst.gravity = Vector2(0, 250); burst.initial_velocity_min = 400; burst.initial_velocity_max = 1100
	add_child(burst)
	logo_box = Control.new(); logo_box.position = Vector2(0, 930); logo_box.size = Vector2(1080, 330); add_child(logo_box)
	_build_logo()
	sub = UI.lbl(G.tr_("subtitle"), 40, Color(0.85, 0.9, 1)); sub.position = Vector2(0, 1250); sub.size = Vector2(1080, 60)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub.modulate.a = 0; add_child(sub)
	menu = VBoxContainer.new(); menu.position = Vector2(190, 1380); menu.size = Vector2(700, 420)
	menu.add_theme_constant_override("separation", 22); add_child(menu); menu.modulate.a = 0
	var play := UI.btn(G.tr_("play"), Color(0.75, 0.35, 0.08)); play.custom_minimum_size = Vector2(700, 150)
	play.add_theme_font_size_override("font_size", 64); play.pressed.connect(_go); menu.add_child(play)
	sign_btn = UI.btn(G.tr_("gsign"), Color(0.15, 0.35, 0.6)); sign_btn.custom_minimum_size = Vector2(700, 100)
	sign_btn.pressed.connect(func(): Online.sign_in()); menu.add_child(sign_btn)
	var lang := UI.btn("Русский / English", Color(0.3, 0.18, 0.4)); lang.custom_minimum_size = Vector2(700, 90)
	lang.pressed.connect(func():
		G.lang = "en" if G.lang == "ru" else "ru"; G.save_game(); get_tree().reload_current_scene())
	menu.add_child(lang)
	Online.status_changed.connect(_status)
	_status()
	skip_lbl = UI.lbl(G.tr_("tap_skip"), 30, Color(1, 1, 1, 0.6)); skip_lbl.position = Vector2(0, 1830); skip_lbl.size = Vector2(1080, 50)
	skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(skip_lbl)
	flash = ColorRect.new(); flash.size = Vector2(1080, 1920); flash.color = Color(1, 0.95, 0.85, 0); flash.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(flash)
	Sound.play("sting", false); Sound.music("menu", 0.5)
	# --- sequence
	seq = create_tween()
	seq.tween_property(art, "modulate:a", 1.0, 1.2)
	seq.parallel().tween_property(rays, "modulate:a", 0.55, 1.0).set_delay(0.3)
	seq.parallel().tween_property(shard, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(0.3)
	seq.tween_callback(func(): Sound.play("whoosh", false))
	seq.tween_property(dragon, "position", Vector2(1300, -250), 1.0).set_trans(Tween.TRANS_SINE)
	seq.parallel().tween_property(dragon, "scale", Vector2(1.5, 1.5), 1.0)
	seq.tween_callback(_flash_burst)
	seq.tween_interval(0.25)
	seq.tween_callback(_drop_letters)
	seq.tween_interval(1.0)
	seq.tween_callback(_show_menu)

func _status() -> void:
	if not is_instance_valid(sign_btn): return
	sign_btn.visible = Online.gpgs_available
	sign_btn.text = G.tr_("gsigned") if Online.signed_in else G.tr_("gsign")
	sign_btn.disabled = Online.signed_in

func _build_logo() -> void:
	var title: String = "Легенды Драконьего Осколка" if G.lang == "ru" else "Dragonshard Legends"
	var words: PackedStringArray = title.split(" ")
	var lines: Array = [title] if G.lang == "en" else [words[0], words[1] + " " + words[2]]
	var f: Font = load("res://assets/fonts/RuslanDisplay-Regular.ttf")
	var size := 96
	for line in lines: size = min(size, int(96.0 * 1000.0 / max(1.0, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x)))
	var y := 0.0
	for line in lines:
		var w: float = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var x: float = 540 - w / 2
		for ch in line:
			var l := UI.lbl(ch, size, Color(1, 0.82, 0.35)); l.add_theme_font_override("font", f)
			l.add_theme_color_override("font_outline_color", Color(0.35, 0.08, 0.02)); l.add_theme_constant_override("outline_size", 16)
			l.position = Vector2(x, y - 260); l.modulate.a = 0
			l.set_meta("target", Vector2(x, y))
			logo_box.add_child(l)
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		y += size * 1.35

func _drop_letters() -> void:
	var i := 0
	for l in logo_box.get_children():
		var tw := l.create_tween().set_parallel()
		tw.tween_property(l, "position", l.get_meta("target"), 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT).set_delay(i * 0.035)
		tw.tween_property(l, "modulate:a", 1.0, 0.25).set_delay(i * 0.035)
		i += 1

func _flash_burst() -> void:
	burst.restart(); burst.emitting = true
	var tw := create_tween(); tw.tween_property(flash, "color:a", 0.85, 0.06); tw.tween_property(flash, "color:a", 0.0, 0.5)

func _show_menu() -> void:
	if menu_shown: return
	menu_shown = true
	var tw := create_tween().set_parallel()
	tw.tween_property(sub, "modulate:a", 1.0, 0.5)
	menu.position.y = 1560
	tw.tween_property(menu, "position:y", 1380.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(menu, "modulate:a", 1.0, 0.4)
	tw.tween_property(skip_lbl, "modulate:a", 0.0, 0.3)

func _skip() -> void:
	if menu_shown: return
	if seq and seq.is_valid(): seq.kill()
	shard.scale = Vector2.ONE; rays.modulate.a = 0.55; dragon.visible = false
	for l in logo_box.get_children(): l.position = l.get_meta("target"); l.modulate.a = 1
	_show_menu()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed: _skip()

func _process(dt: float) -> void:
	t += dt
	rays.rotation += dt * 0.15
	shard.position.y = 450 + sin(t * 1.6) * 14
	shard.rotation = sin(t * 0.9) * 0.05
	if menu_shown:
		for i in logo_box.get_child_count():
			var l: Control = logo_box.get_child(i)
			l.position.y = l.get_meta("target").y + sin(t * 2.5 + i * 0.35) * 5

func _go() -> void:
	if leaving: return
	leaving = true
	var tw := create_tween()
	tw.tween_property(flash, "color", Color(0, 0, 0, 1), 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

## Dev: `-- --intro-shot=<file>,<lang>` saves a frame of the finished intro.
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--intro-shot="):
			var p: PackedStringArray = a.substr(13).split(",")
			call_deferred("_ishot", p[0])
		elif a.begins_with("--shot="):
			call_deferred("_go")

func _ishot(path: String) -> void:
	await get_tree().create_timer(0.2).timeout
	_skip()
	for i in 60: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
