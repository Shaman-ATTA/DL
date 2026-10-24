class_name StoryOverlay extends Control
## Cutscene overlay: letterbox bars, sliding portraits, typewriter dialogue, tap to advance,
## Skip button. Pauses the game tree while open and plays the story music.
signal finished
static var _data: Dictionary
var lines: Array = []
var idx := -1
var portrait: TextureRect
var name_lbl: Label
var text_lbl: RichTextLabel
var hint: Label
var top_bar: ColorRect
var bot_bar: ColorRect
var dim: ColorRect
var _type_tw: Tween
var _prev_music := ""
var _left := true

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	return _data

static func has_scene(id: String) -> bool: return data().scenes.has(id)

func start(id: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	lines = data().scenes[id]
	size = Vector2(1080, 1920); mouse_filter = Control.MOUSE_FILTER_STOP
	dim = ColorRect.new(); dim.size = size; dim.color = Color(0.02, 0.01, 0.05, 0); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(dim)
	top_bar = ColorRect.new(); top_bar.color = Color.BLACK; top_bar.size = Vector2(1080, 180); top_bar.position.y = -180; add_child(top_bar)
	bot_bar = ColorRect.new(); bot_bar.color = Color.BLACK; bot_bar.size = Vector2(1080, 180); bot_bar.position.y = 1920; add_child(bot_bar)
	for c in [top_bar, bot_bar]: c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait = TextureRect.new(); portrait.size = Vector2(620, 620); portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.pivot_offset = Vector2(310, 620); add_child(portrait)
	var box := PanelContainer.new(); box.position = Vector2(40, 1210); box.size = Vector2(1000, 460)
	box.add_theme_stylebox_override("panel", UI.panel(Color(0.1, 0.05, 0.16, 0.95))); box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(box)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(v)
	name_lbl = UI.lbl("", 44, Color(1, 0.85, 0.35)); v.add_child(name_lbl)
	text_lbl = RichTextLabel.new(); text_lbl.fit_content = true; text_lbl.custom_minimum_size = Vector2(960, 300)
	text_lbl.add_theme_font_size_override("normal_font_size", 40); text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_lbl.add_theme_color_override("default_color", Color(1, 0.97, 0.9)); v.add_child(text_lbl)
	hint = UI.lbl("▼", 36, Color(1, 0.85, 0.35, 0.8)); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(hint)
	var skip := UI.btn(Game.tr_("skip"), Color(0.3, 0.2, 0.4)); skip.position = Vector2(780, 40); skip.size = Vector2(260, 100)
	skip.process_mode = Node.PROCESS_MODE_ALWAYS; skip.pressed.connect(_end); add_child(skip)
	gui_input.connect(_on_input)
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.65, 0.35)
	tw.tween_property(top_bar, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bot_bar, "position:y", 1740.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_prev_music = Sound.current(); Sound.music("story", 0.8)
	get_tree().paused = true
	_next()

func _on_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed:
		if _type_tw and _type_tw.is_running():
			_type_tw.kill(); text_lbl.visible_ratio = 1.0
		else: _next()

func _next() -> void:
	idx += 1
	if idx >= lines.size(): _end(); return
	var l: Dictionary = lines[idx]; var d := data()
	var who: String = l.who
	var nm: Array = d.names.get(who, [who, who])
	name_lbl.text = nm[1] if Game.lang == "ru" else nm[0]
	text_lbl.text = l.get(Game.lang, l.en)
	text_lbl.visible_ratio = 0.0
	var left := who == "hero"
	var new_tex: Texture2D = load(d.portraits.get(who, d.portraits.hero))
	var changed := portrait.texture != new_tex
	portrait.texture = new_tex
	portrait.flip_h = not left and who in ["morvath", "wyrm"]
	var x := 40.0 if left else 420.0
	if changed or idx == 0:
		portrait.position = Vector2(x + (-300 if left else 300), 600); portrait.modulate.a = 0; portrait.scale = Vector2(0.96, 0.96)
		var pt := create_tween().set_parallel()
		pt.tween_property(portrait, "position:x", x, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pt.tween_property(portrait, "modulate:a", 1.0, 0.25)
		pt.tween_property(portrait, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# small "talk" bounce on the same speaker
		var bt := create_tween(); bt.tween_property(portrait, "scale", Vector2(1.03, 0.97), 0.08); bt.tween_property(portrait, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC)
	_type_tw = create_tween()
	_type_tw.tween_property(text_lbl, "visible_ratio", 1.0, max(0.4, text_lbl.text.length() * 0.028))
	Sound.play("click")

func _end() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	get_tree().paused = false
	if _prev_music != "": Sound.music(_prev_music, 0.8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func(): finished.emit(); queue_free())
