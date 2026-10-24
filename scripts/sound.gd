extends Node
## Audio + haptics autoload. Music/SFX buses with master/music/sfx volume, crossfading
## looped music tracks (assets/music/*.ogg, CC0 - see LICENSES.md) and pooled SFX players.
const SFX := ["tap", "crit", "coin", "boss", "level", "skill", "levelup", "prestige", "dissolve", "click", "whoosh", "sting"]
var _sfx := {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _cur := ""
var _tw: Tween
var _streams := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus(); var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus); AudioServer.set_bus_send(i, "Master")
	for s in SFX:
		var p := AudioStreamPlayer.new(); p.stream = load("res://assets/audio/%s.wav" % s); p.bus = "SFX"
		p.max_polyphony = 3; add_child(p); _sfx[s] = p
	_sfx["click"].volume_db = -6
	_a = AudioStreamPlayer.new(); _b = AudioStreamPlayer.new()
	for p in [_a, _b]: p.bus = "Music"; p.volume_db = -80; add_child(p)
	apply()

func _s() -> Dictionary: return Game.settings

## Re-applies bus volumes from settings (0..1 linear).
func apply() -> void:
	var st := _s()
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.0001, float(st.vol_master))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(max(0.0001, float(st.vol_music) * 0.55)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(max(0.0001, float(st.vol_sfx))))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), float(st.vol_music) <= 0.001)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), float(st.vol_sfx) <= 0.001)

func play(s: String, vary := true) -> void:
	if not _sfx.has(s) or float(_s().vol_sfx) <= 0.001: return
	var p: AudioStreamPlayer = _sfx[s]
	p.pitch_scale = randf_range(0.92, 1.08) if vary else 1.0; p.play()

## Crossfade to a looped track ("menu", "forest", "cave", "lava", "ice", "boss", "raid", "story").
func music(track: String, fade := 1.2) -> void:
	if track == _cur: return
	_cur = track
	if not _streams.has(track):
		var st: AudioStreamOggVorbis = load("res://assets/music/%s.ogg" % track)
		if st == null: return
		st.loop = true; _streams[track] = st
	var nxt := _b if _a.playing and _a.volume_db > -60 else _a
	var old := _a if nxt == _b else _b
	nxt.stream = _streams[track]; nxt.volume_db = -40; nxt.play()
	if _tw: _tw.kill()
	_tw = create_tween().set_parallel()
	_tw.tween_property(nxt, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(old, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE)
	_tw.chain().tween_callback(old.stop)

func current() -> String: return _cur

func haptic(ms := 25, amp := 0.5) -> void:
	if _s().haptics and OS.has_feature("mobile"): Input.vibrate_handheld(ms, amp)
