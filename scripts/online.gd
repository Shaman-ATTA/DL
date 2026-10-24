extends Node
## Wraps Google Play Games Services (sign-in, cloud save, achievements, leaderboard)
## and Google Play Billing. Every call is a safe no-op when the plugins are absent
## (desktop, debug builds without Play services, or devices without Google Play).

signal status_changed
signal toast(text: String)
signal cloud_conflict(cloud: Dictionary)   # cloud save has more progress than local
signal purchase_granted(product_id: String)

var gpgs_available := false
var signed_in := false
var billing_ready := false
var prices: Dictionary = {}       # product_id -> formatted price
var _sign: Node; var _snap: Node; var _ach: Node; var _lb: Node
var _billing: Node
var _cfg: Dictionary
var _products: Dictionary = {}    # id -> config dict
var _pending_cloud_save := false
var _manual_load := false

func _ready() -> void:
	_cfg = Game.S
	for p in _cfg.billing.products: _products[p.id] = p
	for p in _products.values(): prices[p.id] = p.fallback_price
	Game.achievement.connect(_on_local_achievement)
	_init_pgs()
	_init_billing()

# ---------------- Play Games ----------------
func _init_pgs() -> void:
	if not OS.has_feature("android") or not has_node("/root/GodotPlayGameServices"): return
	var pgs: Node = get_node("/root/GodotPlayGameServices")
	if pgs.initialize() != 0: return
	gpgs_available = true
	_sign = PlayGamesSignInClient.new(); add_child(_sign)
	_snap = PlayGamesSnapshotsClient.new(); add_child(_snap)
	_ach = PlayGamesAchievementsClient.new(); add_child(_ach)
	_lb = PlayGamesLeaderboardsClient.new(); add_child(_lb)
	_sign.user_authenticated.connect(_on_auth)
	_snap.game_loaded.connect(_on_cloud_loaded)
	_snap.game_saved.connect(func(ok: bool, _n: String, _d: String):
		if ok and _pending_cloud_save: toast.emit(Game.tr_("cloud_saved"))
		_pending_cloud_save = false)
	_snap.conflict_emitted.connect(func(_c): load_cloud(false))
	_sign.is_authenticated()

func _on_auth(ok: bool) -> void:
	signed_in = ok
	status_changed.emit()
	if ok:
		load_cloud(false)
		for k in Game.ach: _push_achievement(k)
		submit_stage()

func sign_in() -> void:
	if gpgs_available: _sign.sign_in()
	else: toast.emit(Game.tr_("gunavail"))

func save_cloud(manual := true) -> void:
	if not signed_in: return
	_pending_cloud_save = manual
	var bytes := JSON.stringify(Game.to_dict()).to_utf8_buffer()
	_snap.save_game(_cfg.play_games.cloud_save_name, "Stage %d" % Game.max_stage, bytes, 0, Game.max_stage)

func load_cloud(manual := true) -> void:
	if not signed_in: return
	_manual_load = manual
	_snap.load_game(_cfg.play_games.cloud_save_name, false)

func _on_cloud_loaded(s) -> void:
	if s == null or s.content.is_empty():
		if _manual_load: toast.emit(Game.tr_("cloud_none"))
		return
	var d = JSON.parse_string(s.content.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY: return
	if _manual_load or Game.progress_score(d) > Game.progress_score(Game.to_dict()):
		cloud_conflict.emit(d)   # UI asks the player before overwriting local progress

func apply_cloud(d: Dictionary) -> void:
	# Never lose purchases: merge owned unlocks and processed tokens.
	var owned := Game.owned.duplicate(); var tokens := Game.processed_tokens.duplicate()
	Game.from_dict(d)
	Game.owned.merge(owned); Game.processed_tokens.merge(tokens)
	Game.save_game(); Game.changed.emit(); Game.gems_changed.emit()

func _on_local_achievement(key: String) -> void:
	_push_achievement(key)

func _push_achievement(key: String) -> void:
	var id: String = _cfg.play_games.achievements.get(key, "")
	if signed_in and id != "": _ach.unlock_achievement(id)

func submit_stage() -> void:
	var id: String = _cfg.play_games.leaderboard_max_stage
	if signed_in and id != "": _lb.submit_score(id, Game.max_stage)

func show_achievements() -> void:
	if signed_in: _ach.show_achievements()
	else: sign_in()

func show_leaderboard() -> void:
	var id: String = _cfg.play_games.leaderboard_max_stage
	if signed_in and id != "": _lb.show_leaderboard(id)
	elif signed_in: _lb.show_all_leaderboards()
	else: sign_in()

# ---------------- Billing ----------------
func _init_billing() -> void:
	if not OS.has_feature("android") or not Engine.has_singleton("GodotGooglePlayBilling"): return
	_billing = BillingClient.new(); add_child(_billing)
	_billing.connected.connect(_on_billing_connected)
	_billing.disconnected.connect(func(): billing_ready = false; status_changed.emit())
	_billing.connect_error.connect(func(_c, _m): billing_ready = false; status_changed.emit())
	_billing.query_product_details_response.connect(_on_details)
	_billing.query_purchases_response.connect(_on_purchases)
	_billing.on_purchase_updated.connect(_on_purchases)
	_billing.consume_purchase_response.connect(func(_r): pass)
	_billing.acknowledge_purchase_response.connect(func(_r): pass)
	_billing.start_connection()

func _on_billing_connected() -> void:
	billing_ready = true
	_billing.query_product_details(PackedStringArray(_products.keys()), BillingClient.ProductType.INAPP)
	_billing.query_purchases(BillingClient.ProductType.INAPP)   # restores + finishes interrupted purchases
	status_changed.emit()

func _on_details(r: Dictionary) -> void:
	if r.get("response_code", -1) != 0: return
	for p in r.get("product_details", []):
		var offers: Array = p.get("one_time_purchase_offer_details_list", [])
		if offers.size() > 0: prices[p.product_id] = offers[0].get("formatted_price", prices.get(p.product_id, ""))
	status_changed.emit()

func buy(id: String) -> void:
	if not billing_ready:
		toast.emit(Game.tr_("billing_unavail")); return
	var r: Dictionary = _billing.purchase(id)
	if r.get("response_code", 0) != 0 and r.get("response_code", 0) != 1:
		toast.emit(str(r.get("debug_message", "Error")))

func restore() -> void:
	if not billing_ready:
		toast.emit(Game.tr_("billing_unavail")); return
	_billing.query_purchases(BillingClient.ProductType.INAPP)
	toast.emit(Game.tr_("restored"))

func _on_purchases(r: Dictionary) -> void:
	if r.get("response_code", -1) != 0: return
	for p in r.get("purchases", []):
		var state: int = int(p.get("purchase_state", 0))
		if state == 2:
			toast.emit(Game.tr_("pending")); continue
		if state != 1: continue
		var token: String = p.get("purchase_token", "")
		for pid in p.get("product_ids", []):
			if not _products.has(pid): continue
			var cfg: Dictionary = _products[pid]
			if cfg.type == "consumable":
				if not Game.processed_tokens.has(token): _grant(pid, cfg, token)
				_billing.consume_purchase(token)
			else:
				if not Game.owned.has(pid): _grant(pid, cfg, token)
				if not p.get("is_acknowledged", false): _billing.acknowledge_purchase(token)

func _grant(pid: String, cfg: Dictionary, token: String) -> void:
	var qty: int = max(1, int(cfg.get("quantity", 1)))
	Game.processed_tokens[token] = true
	if cfg.type != "consumable": Game.owned[pid] = true
	if cfg.has("unlock"): Game.owned[cfg.unlock] = true
	if cfg.get("unlock", "") == "supporter": Game.owned["aura_gold"] = true
	if int(cfg.gems) > 0: Game.gems += int(cfg.gems) * qty
	Game.save_game(); Game.gems_changed.emit(); Game.changed.emit()
	purchase_granted.emit(pid)
	toast.emit(Game.tr_("buy_ok"))
	save_cloud(false)
