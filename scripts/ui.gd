class_name UI
## Shared styled-UI helpers: theme, labels, buttons with press "juice", particles.
const GOLD := Color(0.95, 0.75, 0.3)
static var _font: Font
static var _cache := {}

static func font() -> Font:
	if _font == null: _font = load("res://assets/fonts/Philosopher-Bold.ttf")
	return _font

static func make_theme() -> Theme:
	var th := Theme.new(); th.default_font = font(); th.default_font_size = 38
	var sbv := StyleBoxFlat.new(); sbv.bg_color = Color(0.95, 0.75, 0.3, 0.5); sbv.set_corner_radius_all(6)
	th.set_stylebox("grabber", "VScrollBar", sbv); th.set_stylebox("grabber_highlight", "VScrollBar", sbv)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return th

static func panel(col: Color, border := GOLD, radius := 18) -> StyleBoxFlat:
	var key := "%s|%s|%d" % [col, border, radius]
	if _cache.has(key): return _cache[key]
	var sb := StyleBoxFlat.new(); sb.bg_color = col
	sb.set_corner_radius_all(radius); sb.border_color = border; sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 6; sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	_cache[key] = sb
	return sb

static func lbl(t: String, size := 38, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.1))
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l

static func btn(t: String, col := Color(0.55, 0.25, 0.1)) -> Button:
	var b := Button.new(); b.text = t
	var top := col.lightened(0.25)
	b.add_theme_stylebox_override("normal", panel(col, GOLD))
	b.add_theme_stylebox_override("hover", panel(col.lightened(0.1), top))
	b.add_theme_stylebox_override("pressed", panel(col.darkened(0.2), GOLD))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", panel(Color(0.28, 0.26, 0.3), Color(0.5, 0.45, 0.4)))
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.1))
	b.add_theme_constant_override("outline_size", 8)
	juice(b)
	return b

## Squash on press, springy release; click sound via Game.
static func juice(b: Button) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.button_down.connect(func():
		var t := b.create_tween(); t.tween_property(b, "scale", Vector2(0.92, 0.9), 0.06))
	b.button_up.connect(func():
		var t := b.create_tween(); t.tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func(): Game.click.emit())

static func particles(tex: Texture2D, amount: int, life: float, col: Color, one_shot := true) -> CPUParticles2D:
	var p := CPUParticles2D.new(); p.texture = tex; p.amount = amount; p.lifetime = life
	p.one_shot = one_shot; p.explosiveness = 0.95 if one_shot else 0.0; p.emitting = false
	p.direction = Vector2.UP; p.spread = 180; p.gravity = Vector2(0, 600)
	p.initial_velocity_min = 300; p.initial_velocity_max = 750
	p.scale_amount_min = 0.4; p.scale_amount_max = 1.1
	var g := Gradient.new(); g.set_color(0, col); g.set_color(1, Color(col.r, col.g, col.b, 0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; p.material = mat
	return p
