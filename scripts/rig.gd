class_name Actor extends Node2D
## Deformable 2D actor: textured grid mesh + actor.gdshader. GDScript damped springs give
## secondary motion (knockback, lean, squash) and keyframed attack poses with anticipation,
## strike and overshooting follow-through. The hero also gets a cut-out blade layer that is
## pinned to the deformed hands, plus a glow copy and a pooled Line2D weapon trail.
const SHADER := preload("res://assets/shaders/actor.gdshader")
const GX := 10
const GY := 14
static var _meshes := {}

var mi: MeshInstance2D
var mat: ShaderMaterial
var size := Vector2(400, 400)
var tex_size := Vector2(1, 1)
# springs: value, velocity
var kx := 0.0; var kxv := 0.0          # knockback offset (px)
var ln := 0.0; var lnv := 0.0          # lean
var sq := 0.0; var sqv := 0.0          # squash
var hop := 0.0; var hopv := 0.0        # vertical offset (px)
var lean_target := 0.0
var squash_target := 0.0
var tilt_target := 0.0
var tilt := 0.0
var stiff := 170.0
var damp := 13.0
# idle
var breathe_amp := 0.02
var breathe_speed := 2.2
var bob := 6.0
var hover := 0.0
var t := 0.0
var flash_v := 0.0
var flip := false
# hero extras
var blade: Sprite2D
var blade_glow: Sprite2D
var trail: Line2D
var hand := Vector2.ZERO               # mesh-space hand position
var blade_rest := 0.0
var blade_ang := 0.0
var _prev_ang := 0.0
var _trail_pts := PackedVector2Array()
var _trail_on := true
# attack keyframes: [time, blade, lean, squash, step, hop]
var atk: Array = []
var atk_t := -1.0
var step := 0.0
var _from := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

const ATTACKS := {
	"slash":   [[0.06, -0.9, -0.06, 0.07, -12, 0], [0.12, 1.55, 0.13, -0.09, 55, 0], [0.30, 0, 0, 0, 0, 0]],
	"upper":   [[0.06, 1.1, 0.05, 0.09, -6, 0], [0.12, -1.5, -0.09, -0.11, 40, -18], [0.30, 0, 0, 0, 0, 0]],
	"thrust":  [[0.07, 0.45, -0.11, 0.06, -28, 0], [0.13, 0.8, 0.16, -0.06, 120, 0], [0.32, 0, 0, 0, 0, 0]],
	"spin":    [[0.05, -0.4, 0.0, 0.06, 0, 0], [0.22, 6.6, 0.08, -0.05, 70, -30], [0.36, 6.283, 0, 0, 0, 0]],
	"overhead":[[0.10, -2.3, -0.13, 0.14, -14, 0], [0.17, 1.9, 0.2, -0.16, 80, -40], [0.40, 0, 0, 0, 0, 0]],
}

func setup(texture: Texture2D, box: Vector2, wound: Texture2D = null) -> void:
	if mi == null:
		mi = MeshInstance2D.new(); add_child(mi)
		mat = ShaderMaterial.new(); mat.shader = SHADER; mi.material = mat
	set_texture(texture, box, wound)

func set_texture(texture: Texture2D, box: Vector2, wound: Texture2D = null) -> void:
	tex_size = texture.get_size()
	var s: float = min(box.x / tex_size.x, box.y / tex_size.y)
	size = (tex_size * s).round()
	mi.texture = texture
	mi.mesh = _grid(size)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("wound_tex", wound)
	set_wounds(0.0, 0.0, 0.0)
	mat.set_shader_parameter("dissolve", 0.0)

static func _grid(sz: Vector2) -> ArrayMesh:
	var key := Vector2i(sz)
	if _meshes.has(key): return _meshes[key]
	var verts := PackedVector2Array(); var uvs := PackedVector2Array(); var idx := PackedInt32Array()
	for j in GY + 1:
		for i in GX + 1:
			var u := float(i) / GX; var v := float(j) / GY
			verts.append(Vector2((u - 0.5) * sz.x, (v - 1.0) * sz.y)); uvs.append(Vector2(u, v))
	for j in GY:
		for i in GX:
			var a := j * (GX + 1) + i
			idx.append_array([a, a + 1, a + GX + 1, a + 1, a + GX + 2, a + GX + 1])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m

## Cut-out weapon. pivot is in blade-texture pixels, hand_px/offset_px in body-texture pixels.
func add_blade(btex: Texture2D, pivot: Vector2, hand_px: Vector2, trail_parent: Node) -> void:
	var s: float = size.x / tex_size.x
	hand = Vector2((hand_px.x / tex_size.x - 0.5) * size.x, (hand_px.y / tex_size.y - 1.0) * size.y)
	blade_glow = Sprite2D.new(); blade_glow.texture = btex; blade_glow.centered = false; blade_glow.offset = -pivot
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; blade_glow.material = add
	blade_glow.modulate = Color(0.4, 0.8, 1.0, 0.0); add_child(blade_glow)
	blade = Sprite2D.new(); blade.texture = btex; blade.centered = false; blade.offset = -pivot
	blade.scale = Vector2(s, s); blade_glow.scale = Vector2(s, s) * 1.06; add_child(blade)
	# tip direction in blade-local space (texture top-right corner relative to pivot)
	blade.set_meta("tip", (Vector2(btex.get_width() - 12, 12) - pivot) * s)
	trail = Line2D.new(); trail.width = 46
	var c := Curve.new(); c.add_point(Vector2(0, 1)); c.add_point(Vector2(1, 0)); trail.width_curve = c
	var g := Gradient.new(); g.set_color(0, Color(0.75, 0.95, 1, 0.9)); g.set_color(1, Color(0.3, 0.6, 1, 0)); trail.gradient = g
	trail.joint_mode = Line2D.LINE_JOINT_ROUND; trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var tm := CanvasItemMaterial.new(); tm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; trail.material = tm
	trail_parent.add_child(trail)
	_trail_pts.resize(12)

func set_trails(on: bool) -> void:
	_trail_on = on
	if trail: trail.visible = on

func set_wounds(a: float, b: float, c: float) -> void:
	mat.set_shader_parameter("wound1", a); mat.set_shader_parameter("wound2", b); mat.set_shader_parameter("wound3", c)

func set_param(n: String, v) -> void: mat.set_shader_parameter(n, v)

## Spring impulse: knockback px/s, lean, squash (positive = wide/short), hop px/s.
func kick(knock: float, lean_i: float, squash_i: float, hop_i := 0.0) -> void:
	kxv += knock; lnv += lean_i; sqv += squash_i; hopv += hop_i

func hit_flash(v := 0.85) -> void: flash_v = max(flash_v, v)

func attack(kind: String) -> void:
	atk = ATTACKS[kind]; atk_t = 0.0
	_from = [0.0, blade_ang, lean_target, squash_target, step, hop]

func _ease(x: float) -> float: return 1.0 - pow(1.0 - x, 3.0)

func _eval_attack(dt: float) -> void:
	if atk_t < 0: return
	atk_t += dt
	var prev: Array = _from; var pt := 0.0
	for k in atk:
		if atk_t <= k[0]:
			var f: float = clamp((atk_t - pt) / max(0.001, k[0] - pt), 0.0, 1.0)
			# last segment overshoots (follow-through), others ease-out cubic (snappy)
			var e: float = (1.0 + 2.70158 * pow(f - 1.0, 3.0) + 1.70158 * pow(f - 1.0, 2.0)) if k == atk[-1] else _ease(f)
			blade_ang = lerp(float(prev[1]), float(k[1]), e)
			lean_target = lerp(float(prev[2]), float(k[2]), e)
			squash_target = lerp(float(prev[3]), float(k[3]), e)
			step = lerp(float(prev[4]), float(k[4]), e)
			hop = lerp(float(prev[5]), float(k[5]), e)
			return
		prev = k; pt = k[0]
	atk_t = -1.0; blade_ang = 0.0; lean_target = 0.0; squash_target = 0.0; step = 0.0; hop = 0.0

## Same deformation as the vertex shader (static part) so attachments follow the mesh.
func deform(v: Vector2, lean_v: float, sq_v: float, br: float) -> Vector2:
	var h: float = clamp(-v.y / size.y, 0.0, 1.0)
	v.y *= 1.0 - sq_v
	v.x *= 1.0 + sq_v * 0.8 * (0.4 + 0.6 * h)
	var chest := exp(-pow((h - 0.62) / 0.22, 2.0))
	v.x *= 1.0 + br * chest
	v.y -= br * size.y * 0.04 * h
	v.x += lean_v * h * h * size.y
	return v.rotated(tilt)

func _process(dt: float) -> void:
	if mi == null: return
	t += dt
	_eval_attack(dt)
	var k := stiff; var c := damp
	kxv += (-k * kx - c * kxv) * dt; kx += kxv * dt
	lnv += (-k * (ln - lean_target) - c * lnv) * dt; ln += lnv * dt
	sqv += (-k * 1.4 * (sq - squash_target) - c * sqv) * dt; sq += sqv * dt
	if atk_t < 0:
		hopv += (-k * hop - c * hopv) * dt; hop += hopv * dt
	tilt = lerp(tilt, tilt_target, min(1.0, dt * 6.0))
	var br := sin(t * breathe_speed) * breathe_amp
	var lean_total := ln + sin(t * breathe_speed * 0.5) * 0.01
	var sq_total := sq + sin(t * breathe_speed + 1.0) * breathe_amp * 0.6
	mi.position = Vector2(kx + step, hop + sin(t * breathe_speed) * bob - abs(sin(t * 1.7)) * hover)
	mat.set_shader_parameter("lean", lean_total)
	mat.set_shader_parameter("squash", sq_total)
	mat.set_shader_parameter("breathe", br)
	mat.set_shader_parameter("tilt", tilt)
	if flash_v > 0:
		flash_v = max(0.0, flash_v - dt * 6.0); mat.set_shader_parameter("flash", flash_v)
	if blade:
		var p := deform(hand, lean_total, sq_total, br) + mi.position
		blade.position = p; blade.rotation = blade_rest + blade_ang + tilt + lean_total * 0.8
		blade_glow.position = p; blade_glow.rotation = blade.rotation
		var spd: float = abs(blade_ang - _prev_ang) / max(dt, 0.001); _prev_ang = blade_ang
		var glow_a: float = clamp(spd / 25.0, 0.0, 0.8)
		blade_glow.modulate.a = lerp(blade_glow.modulate.a, glow_a, 0.5)
		if trail and _trail_on:
			var tip: Vector2 = blade.get_meta("tip")
			var gp := trail.get_parent() as CanvasItem
			var world := gp.get_global_transform().affine_inverse() * (get_global_transform() * (p + tip.rotated(blade.rotation)))
			for i in range(_trail_pts.size() - 1, 0, -1): _trail_pts[i] = _trail_pts[i - 1]
			_trail_pts[0] = world
			if atk_t < 0 and spd < 1.0:
				for i in _trail_pts.size(): _trail_pts[i] = world
			trail.points = _trail_pts
			trail.modulate.a = clamp(spd / 10.0, 0.0, 1.0)
