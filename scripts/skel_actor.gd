class_name SkelActor extends Actor
## Skeletal cut-out actor (Phase 4 pilot). The sprite becomes one skinned Polygon2D mesh
## driven by a Skeleton2D/Bone2D hierarchy, so there are no seams between parts. Weights come
## from distance to bone segments (smooth blending at joints). Motion layers, in this order:
##   1. AnimationPlayer clips (idle, attacks, hit, death, entrance), advanced manually
##   2. Actor springs from kick() (knockback, lean, squash) on the body and spine
##   3. Procedural jiggle on bones flagged "j" (cape, ear, flame, robe hems)
## It keeps the Actor API (setup, kick, hit_flash, attack, set_param, set_wounds, add_blade),
## so main.gd can swap between Actor and SkelActor per character.
const SKEL_SHADER := preload("res://assets/shaders/skel.gdshader")
static var _mesh_cache := {}

var rig_id := ""
var R: Dictionary
var body: Node2D        # springs
var root: Node2D        # animated root
var poly: Polygon2D
var skel: Skeleton2D
var bones := {}
var joint := {}         # bone -> texture px joint
var dirs := {}          # bone -> rest direction (unit)
var ap: AnimationPlayer
var sc := 1.0
var origin := Vector2.ZERO
var jig := {}           # bone -> [angle, vel, prev_pos, prev_vel]
var clip := "idle"
var base_breathe := 1.0
var _smear_t := -1.0
var _smear_def: Array = []
var smear: Polygon2D
var _tip_prev := Vector2.ZERO
var dead := false
var _bb_pending := true

func _init(id := "") -> void:
	rig_id = id
	R = Rigs.get_rig(id)

func setup(texture: Texture2D, box: Vector2, wound: Texture2D = null) -> void:
	tex_size = texture.get_size()
	var s: float = min(box.x / tex_size.x, box.y / tex_size.y)
	if body == null or abs(s - sc) > 0.001: _build(texture, s)
	size = (tex_size * sc).round()
	mat.set_shader_parameter("wound_tex", wound)
	set_wounds(0.0, 0.0, 0.0)
	mat.set_shader_parameter("dissolve", 0.0)
	dead = false; atk_t = -1.0; _bb_pending = true
	for k in jig: jig[k] = [0.0, 0.0, Vector2.ZERO, Vector2.ZERO]
	play_clip("idle", 0.0)

func set_texture(texture: Texture2D, box: Vector2, wound: Texture2D = null) -> void:
	setup(texture, box, wound)

func _p(px: Vector2) -> Vector2: return (px - origin) * sc

func _build(texture: Texture2D, s: float) -> void:
	if body: body.queue_free()
	sc = s; origin = Vector2(tex_size.x * 0.5, tex_size.y)
	body = Node2D.new(); body.name = "Body"; add_child(body)
	root = Node2D.new(); root.name = "Root"; body.add_child(root)
	poly = Polygon2D.new(); poly.name = "Mesh"; root.add_child(poly)
	skel = Skeleton2D.new(); skel.name = "Skel"; root.add_child(skel)
	mat = ShaderMaterial.new(); mat.shader = SKEL_SHADER; poly.material = mat
	bones.clear(); joint.clear(); dirs.clear(); jig.clear()
	for b in R.bones:
		var bn := Bone2D.new(); bn.name = b[0]
		var j := Vector2(b[2], b[3]); var tip := Vector2(b[4], b[5])
		joint[b[0]] = j; dirs[b[0]] = (tip - j).normalized()
		var par: Node = skel if b[1] == "" else bones[b[1]]
		var pj: Vector2 = origin if b[1] == "" else joint[b[1]]
		bn.position = (j - pj) * sc
		bn.rest = Transform2D(0.0, bn.position)
		bn.set_autocalculate_length_and_angle(false)
		bn.set_length(max(4.0, (tip - j).length() * sc)); bn.set_bone_angle((tip - j).angle())
		par.add_child(bn); bones[b[0]] = bn
		if "j" in String(b[7]): jig[b[0]] = [0.0, 0.0, Vector2.ZERO, Vector2.ZERO]
	var m: Dictionary = _mesh(texture)
	var verts := PackedVector2Array()
	for v in m.uv: verts.append(_p(v))
	poly.texture = texture
	poly.polygon = verts; poly.uv = m.uv; poly.polygons = m.polys
	poly.skeleton = poly.get_path_to(skel)
	for b in R.bones:
		if m.w.has(b[0]): poly.add_bone(skel.get_path_to(bones[b[0]]), m.w[b[0]])
	_build_anims()

## Grid mesh over the opaque part of the texture + per-bone weights (cached per rig).
func _mesh(texture: Texture2D) -> Dictionary:
	if _mesh_cache.has(rig_id): return _mesh_cache[rig_id]
	var img := texture.get_image()
	if img.is_compressed(): img.decompress()
	var cell: int = R.cell
	var nx := int(ceil(tex_size.x / cell)); var ny := int(ceil(tex_size.y / cell))
	var idx := {}; var uv := PackedVector2Array(); var polys := []
	var W := int(tex_size.x); var H := int(tex_size.y)
	for cy in ny:
		for cx in nx:
			var solid := false
			for sy in range(cy * cell, min(H, (cy + 1) * cell + 1), 3):
				for sx in range(cx * cell, min(W, (cx + 1) * cell + 1), 3):
					if img.get_pixel(sx, sy).a > 0.02: solid = true; break
				if solid: break
			if not solid: continue
			var q := []
			for c in [Vector2i(cx, cy), Vector2i(cx + 1, cy), Vector2i(cx + 1, cy + 1), Vector2i(cx, cy + 1)]:
				if not idx.has(c):
					idx[c] = uv.size(); uv.append(Vector2(min(c.x * cell, W), min(c.y * cell, H)))
				q.append(idx[c])
			polys.append(PackedInt32Array([q[0], q[1], q[2]])); polys.append(PackedInt32Array([q[0], q[2], q[3]]))
	# weights: inverse distance^4 to each bone segment, top 3 kept, normalised
	var segs := []
	for b in R.bones:
		if "n" in String(b[7]): continue
		segs.append([b[0], Vector2(b[2], b[3]), Vector2(b[4], b[5]), float(b[6])])
	var w := {}
	for sg in segs: w[sg[0]] = PackedFloat32Array(); w[sg[0]].resize(uv.size())
	for i in uv.size():
		var p: Vector2 = uv[i]; var ws := []
		for sg in segs:
			var a: Vector2 = sg[1]; var ab: Vector2 = sg[2] - a
			var f: float = clamp((p - a).dot(ab) / max(1.0, ab.length_squared()), 0.0, 1.0)
			var d: float = p.distance_to(a + ab * f) / sg[3]
			ws.append([1.0 / pow(d + 10.0, 4.0), sg[0]])
		ws.sort_custom(func(x, y): return x[0] > y[0])
		var tot: float = ws[0][0] + ws[1][0] + ws[2][0]
		for k in 3: w[ws[k][1]][i] = ws[k][0] / tot
	var res := {"uv": uv, "polys": polys, "w": w}
	_mesh_cache[rig_id] = res
	return res

func _path(n: Node) -> NodePath: return get_path_to(n)

func _build_anims() -> void:
	if ap: ap.queue_free()
	ap = AnimationPlayer.new(); ap.name = "Anim"; add_child(ap)
	ap.root_node = ap.get_path_to(self)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lib := AnimationLibrary.new()
	var reset := Animation.new(); reset.length = 0.01
	for bn in bones:
		var b: Bone2D = bones[bn]
		_track(reset, NodePath(String(_path(b)) + ":rotation"), [[0, 0.0]])
		_track(reset, NodePath(String(_path(b)) + ":position"), [[0, b.rest.origin]])
		_track(reset, NodePath(String(_path(b)) + ":scale"), [[0, Vector2.ONE]])
	_track(reset, NodePath(String(_path(root)) + ":position"), [[0, Vector2.ZERO]])
	_track(reset, NodePath(String(_path(root)) + ":rotation"), [[0, 0.0]])
	_track(reset, NodePath(String(_path(root)) + ":scale"), [[0, Vector2.ONE]])
	lib.add_animation("RESET", reset)
	for cname in R.clips:
		var c: Dictionary = R.clips[cname]
		var a := Animation.new(); a.length = c.len
		a.loop_mode = Animation.LOOP_LINEAR if c.get("loop", false) else Animation.LOOP_NONE
		for key in c.keys:
			var parts: PackedStringArray = String(key).split(".")
			var node: Node2D = root if parts[0] == "root" else bones[parts[0]]
			var prop: String = {"rot": "rotation", "pos": "position", "scl": "scale"}[parts[1]]
			var keys := []
			for k in c.keys[key]:
				var v = k[1]
				match parts[1]:
					"rot": v = float(v)
					"pos": v = (node.rest.origin if node is Bone2D else Vector2.ZERO) + Vector2(v[0], v[1]) * sc
					"scl": v = Vector2(v[0], v[1])
				keys.append([float(k[0]), v])
			_track(a, NodePath(String(_path(node)) + ":" + prop), keys)
		lib.add_animation(cname, a)
	ap.add_animation_library("", lib)
	ap.animation_finished.connect(_on_clip_done)

func _track(a: Animation, path: NodePath, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_VALUE); a.track_set_path(t, path)
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	a.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k in keys: a.track_insert_key(t, k[0], k[1])

func has_clip(n: String) -> bool: return ap != null and ap.has_animation(n)

func play_clip(n: String, blend := 0.06) -> void:
	if not has_clip(n) or (dead and n != "death"): return
	clip = n
	ap.play(n, blend)
	if n == "idle": ap.speed_scale = 1.0
	var c: Dictionary = R.clips[n]
	if c.has("smear"): _smear_def = c.smear; _smear_t = 0.0
	if n != "idle" and c.has("smear") == false: _smear_t = -1.0

func _on_clip_done(n: StringName) -> void:
	if dead: return
	if not R.clips.get(String(n), {}).get("hold", false): play_clip("idle", 0.18)

## Actor API ------------------------------------------------------------------------------
func attack(kind: String) -> void:
	var map := {"spin": "overhead"}
	var n: String = map.get(kind, kind)
	if not has_clip(n): n = "attack" if has_clip("attack") else "slash"
	play_clip(n, 0.04)

func kick(knock: float, lean_i: float, squash_i: float, hop_i := 0.0) -> void:
	super.kick(knock, lean_i, squash_i, hop_i)
	# big hits (crits, wound breaks) play the authored hit reaction on top of the springs
	if knock >= 600 and not dead and clip in ["idle", "hit"] and has_clip("hit"): play_clip("hit", 0.03)

func die() -> void:
	if has_clip("death"):
		play_clip("death", 0.05); dead = true

func entrance() -> void:
	if has_clip("entrance"): play_clip("entrance", 0.0)

func add_blade(btex: Texture2D, pivot: Vector2, hand_px: Vector2, trail_parent: Node) -> void:
	var hb: Bone2D = bones[R.hand]
	blade_glow = Sprite2D.new(); blade_glow.texture = btex; blade_glow.centered = false; blade_glow.offset = -pivot
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; blade_glow.material = add
	blade_glow.modulate = Color(0.4, 0.8, 1.0, 0.0)
	blade = Sprite2D.new(); blade.texture = btex; blade.centered = false; blade.offset = -pivot
	for s in [blade_glow, blade]:
		s.position = (hand_px - joint[R.hand]) * sc
		s.scale = Vector2(sc, sc) * (1.06 if s == blade_glow else 1.0)
		hb.add_child(s)
	blade.set_meta("tip", Vector2(btex.get_width() - 12, 12) - pivot)
	trail = Line2D.new(); trail.width = 46
	var c := Curve.new(); c.add_point(Vector2(0, 1)); c.add_point(Vector2(1, 0)); trail.width_curve = c
	var g := Gradient.new(); g.set_color(0, Color(0.75, 0.95, 1, 0.9)); g.set_color(1, Color(0.3, 0.6, 1, 0)); trail.gradient = g
	trail.joint_mode = Line2D.LINE_JOINT_ROUND; trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var tm := CanvasItemMaterial.new(); tm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; trail.material = tm
	trail_parent.add_child(trail)
	_trail_pts.resize(12)
	# smear: crescent arc flashed along the swing (classic smear frame)
	smear = Polygon2D.new(); var sm := CanvasItemMaterial.new(); sm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	smear.material = sm; smear.visible = false; trail_parent.add_child(smear)

func _show_smear(a0: float, a1: float, rk: float) -> void:
	if smear == null or not _trail_on: return
	var gp := smear.get_parent() as CanvasItem
	var hb: Bone2D = bones[R.hand]
	var c: Vector2 = gp.get_global_transform().affine_inverse() * hb.global_position
	var r: float = 260.0 * sc / 0.65 * rk * get_global_transform().get_scale().x
	var pts := PackedVector2Array(); var cols := PackedColorArray(); var n := 18
	for i in n + 1:
		var f := float(i) / n; var a: float = lerp(a0, a1, f)
		pts.append(c + Vector2(cos(a), sin(a)) * r); cols.append(Color(0.8, 0.95, 1.0, 0.85 * f))
	for i in range(n, -1, -1):
		var f := float(i) / n; var a: float = lerp(a0, a1, f)
		pts.append(c + Vector2(cos(a), sin(a)) * r * (1.0 - 0.38 * f * f)); cols.append(Color(0.4, 0.7, 1.0, 0.0))
	smear.polygon = pts; smear.vertex_colors = cols; smear.visible = true; smear.modulate.a = 1.0
	var tw := smear.create_tween(); tw.tween_property(smear, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func(): smear.visible = false)

func set_wounds(a: float, b: float, c: float) -> void:
	if mat: super.set_wounds(a, b, c)

func _process(dt: float) -> void:
	if body == null: return
	t += dt
	if _bb_pending: base_breathe = breathe_speed; _bb_pending = false
	if clip == "idle": ap.speed_scale = breathe_speed / max(0.01, base_breathe)
	else: ap.speed_scale = 1.0
	ap.advance(dt)
	# springs (inherited state) -> body transform and spine
	var k := stiff; var c := damp
	kxv += (-k * kx - c * kxv) * dt; kx += kxv * dt
	lnv += (-k * (ln - lean_target) - c * lnv) * dt; ln += lnv * dt
	sqv += (-k * 1.4 * (sq - squash_target) - c * sqv) * dt; sq += sqv * dt
	hopv += (-k * hop - c * hopv) * dt; hop += hopv * dt
	tilt = lerp(tilt, tilt_target, min(1.0, dt * 6.0))
	body.position = Vector2(kx, hop - abs(sin(t * 1.7)) * hover + sin(t * 1.3) * bob * 0.5)
	body.rotation = tilt
	body.scale = Vector2(1.0 + sq * 0.6, 1.0 - sq)
	if bones.has("chest"): bones["chest"].rotation += ln * 0.7
	if bones.has("head"): bones["head"].rotation += ln * 0.35
	# jiggle: acceleration perpendicular to the bone swings it the other way
	var J: Dictionary = R.jiggle
	for bn in jig:
		var s: Array = jig[bn]; var b: Bone2D = bones[bn]
		var gp: Vector2 = to_local(b.global_position)
		var v: Vector2 = (gp - s[2]) / max(dt, 0.001)
		if s[2] == Vector2.ZERO: v = Vector2.ZERO
		var acc: Vector2 = v - s[3]
		s[2] = gp; s[3] = v
		var d: Vector2 = dirs[bn].rotated(b.global_rotation - global_rotation)
		var torque: float = d.x * acc.y - d.y * acc.x
		s[1] += (-J.k * s[0] - J.c * s[1]) * dt - torque * J.gain
		s[0] = clamp(s[0] + s[1] * dt, -0.6, 0.6)
		b.rotation += s[0]
	if flash_v > 0:
		flash_v = max(0.0, flash_v - dt * 6.0); mat.set_shader_parameter("flash", flash_v)
	# smear frame
	if _smear_t >= 0.0:
		_smear_t += dt
		if _smear_t >= _smear_def[0]:
			_show_smear(_smear_def[1], _smear_def[2], _smear_def[3]); _smear_t = -1.0
	if blade:
		var tipl: Vector2 = blade.get_meta("tip")
		var tipw: Vector2 = blade.get_global_transform() * tipl
		var spd: float = tipw.distance_to(_tip_prev) / max(dt, 0.001); _tip_prev = tipw
		blade_glow.modulate.a = lerp(blade_glow.modulate.a, clamp(spd / 4000.0, 0.0, 0.8), 0.5)
		if trail and _trail_on:
			var gp2 := trail.get_parent() as CanvasItem
			var world := gp2.get_global_transform().affine_inverse() * tipw
			for i in range(_trail_pts.size() - 1, 0, -1): _trail_pts[i] = _trail_pts[i - 1]
			_trail_pts[0] = world
			if clip == "idle" and spd < 300.0:
				for i in _trail_pts.size(): _trail_pts[i] = world
			trail.points = _trail_pts
			trail.modulate.a = clamp(spd / 2500.0, 0.0, 1.0)
