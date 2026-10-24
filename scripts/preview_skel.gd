extends Node2D
## Headless preview reel for the skeletal pilot. Run with Movie Maker:
## godot --write-movie out.avi --fixed-fps 30 res://scenes/preview_skel.tscn -- --rig=hero|goblin|boss_lich
var a: SkelActor
var lbl: Label
var rig := "hero"
var steps := []
var wound_tex: Texture2D

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rig="): rig = arg.substr(6)
	var bgname: String = {"hero": "forest", "goblin": "cave", "boss_lich": "ice"}[rig]
	var bg := Sprite2D.new(); bg.texture = load("res://assets/bg/%s.jpg" % bgname); bg.centered = false
	var vs := get_viewport_rect().size
	bg.scale = Vector2.ONE * max(vs.x / bg.texture.get_width(), vs.y / bg.texture.get_height()); add_child(bg)
	var sh := ColorRect.new(); sh.color = Color(0, 0, 0, 0.35); sh.size = Vector2(380, 50); add_child(sh)
	a = SkelActor.new(rig); add_child(a)
	var big := rig == "boss_lich"
	a.position = Vector2(vs.x * 0.5, vs.y * 0.86); sh.position = a.position - Vector2(190, 25)
	var spr: String = "hero_body" if rig == "hero" else rig
	if rig != "hero": wound_tex = load("res://assets/wounds/%s.png" % rig)
	a.setup(load("res://assets/sprites/%s.png" % spr), Vector2(620, 620) if big else (Vector2(560, 480) if rig == "hero" else Vector2(560, 560)), wound_tex)
	if rig == "hero":
		a.add_blade(load("res://assets/sprites/hero_blade.png"), Vector2(18, 196), Vector2(445, 250), self)
		a.set_param("rim_color", Color(1.0, 0.85, 0.55)); a.set_param("rim_dir", Vector2(0.7, -0.7))
		a.breathe_speed = 2.2; a.bob = 3.0
	else:
		a.set_param("rim_color", Color(0.8, 0.9, 1.0))
		a.set_param("ichor", Color(0.75, 0.05, 0.08) if rig == "goblin" else Color(0.5, 1.0, 0.45))
		a.set_param("ichor_glow", 0.0 if rig == "goblin" else 1.0)
		a.set_param("edge_color", Color(1, 0.6, 0.2)); a.breathe_speed = 3.0 if rig == "goblin" else 1.5
		a.bob = 8 if rig == "goblin" else 12; a.hover = 0 if rig == "goblin" else 8
		a.stiff = 210 if rig == "goblin" else 140
	lbl = Label.new(); lbl.position = Vector2(24, 20); lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK); lbl.add_theme_constant_override("outline_size", 8)
	add_child(lbl)
	if rig == "hero":
		steps = [["idle", 2.4], ["slash", 0.9], ["upper", 0.9], ["thrust", 0.9], ["overhead", 1.1], ["combo", 2.0], ["hit", 1.0], ["idle", 1.0]]
	else:
		steps = ([["entrance", 2.2]] if big else []) + [["idle", 2.4], ["hits", 1.6], ["wound1", 1.0], ["wound2", 1.0], ["wound3", 1.4], ["attack", 1.6 if big else 1.2], ["crit hit", 1.0], ["death", 1.8]]
	_run()

func _run() -> void:
	for s in steps:
		lbl.text = "%s — %s" % [rig, s[0]]
		match s[0]:
			"slash", "upper", "thrust", "overhead": a.attack(s[0])
			"combo":
				for k in ["slash", "upper", "thrust", "slash", "overhead"]:
					a.attack(k); await get_tree().create_timer(0.36).timeout
				continue
			"hit": a.kick(-900, -1.2, 1.5); a.hit_flash(0.8)
			"hits":
				for i in 4:
					a.kick(520, 1.4, 2.2, -90); a.hit_flash(0.7); await get_tree().create_timer(0.38).timeout
				continue
			"wound1", "wound2", "wound3":
				var key: String = s[0]
				a.create_tween().tween_method(func(v: float): a.set_param(key, v), 0.0, 1.0, 0.3)
				a.kick(700, 2.0, -1.5, -200); a.hit_flash(0.8); a.set_param("darken", 0.08 * int(key.right(1)))
				if key == "wound3": a.tilt_target = 0.07; a.breathe_speed *= 1.6
			"attack": a.play_clip("attack")
			"crit hit": a.kick(1144, 3.1, 4.8, -200); a.hit_flash(0.95)
			"entrance":
				a.modulate = Color(0, 0, 0, 0); a.entrance()
				a.create_tween().tween_property(a, "modulate", Color.WHITE, 0.6)
			"death":
				a.die(); a.kick(900, 3.0, -2.5, -400)
				var tw := a.create_tween(); tw.tween_interval(0.3)
				tw.tween_method(func(v: float): a.set_param("dissolve", v), 0.0, 1.0, 0.6)
		await get_tree().create_timer(s[1]).timeout
	get_tree().quit()
