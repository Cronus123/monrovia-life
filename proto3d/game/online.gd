class_name Online
extends Node
## Player accounts, play sessions and cloud saves on Supabase (REST API over HTTPRequest).
##
## One instance lives under the scene tree's root for the whole run (Online.get_instance()),
## so it survives going from the title screen to the city and back. Everything is optional:
## when the server can't be reached (offline, blocked, down) every call returns an error
## result and the game carries on as a guest with its local save.
##
## Only the refresh token (plus the email and display name, for the menu) is remembered, in
## user://online.cfg. The password is never stored.
##
## Calls return a Dictionary: {"ok": bool, "code": HTTP status (0 = no connection),
## "data": parsed JSON or null, "error": short text for the player}.

const URL := "https://nnrafzauvpbyzesijzsk.supabase.co"
const KEY := "sb_publishable_y3OEq46M8tvuUr-9GQJCTg_I0VkzEmW"     # publishable: safe in the client
const TOKEN_FILE := "user://online.cfg"
const TIMEOUT := 12.0
const HEARTBEAT_S := 30.0
const MAX_SAVE_BYTES := 250000       # the server's limit is 256 KB of jsonb
const NAME_RE := "^[A-Za-z0-9_ ]{3,20}$"

signal changed                        # signed in / out, name or connection state changed

static var _inst: Online

var user_id := ""
var email := ""
var display_name := ""
var access_token := ""
var refresh_token := ""
var expires_at := 0.0                 # unix time
var session_id := ""                  # current play session (start_session)
var offline := false                  # the last call couldn't reach the server
var token_file := TOKEN_FILE          # tests point this into tests/output
## How requests are sent: func(method: int, url: String, headers: PackedStringArray,
## body: String) -> [result, code, body_text]. Tests swap in a fake (no network).
var transport: Callable
var _refreshing := false
var _upload_busy := false
var _upload_next = null               # newest save waiting while one uploads
var _js_unload_set := false


## The shared instance (created on first use, kept under the tree's root).
static func get_instance() -> Online:
	if _inst == null or not is_instance_valid(_inst):
		_inst = Online.new()
		_inst.name = "Online"
		if DisplayServer.get_name() != "headless":   # tests never pick up a real saved account
			_inst.load_tokens()
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(_inst)
	return _inst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func signed_in() -> bool:
	return refresh_token != "" and user_id != ""


# ------------------------------------------------------------------ transport
func _send(method: int, url: String, headers: PackedStringArray, body: String) -> Array:
	if transport.is_valid():
		return await transport.call(method, url, headers, body)
	if not is_inside_tree():
		await get_tree_safe()
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	req.use_threads = not OS.has_feature("web")
	add_child(req)
	if req.request(url, headers, method, body) != OK:
		req.queue_free()
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, ""]
	var r: Array = await req.request_completed
	req.queue_free()
	return [r[0], r[1], (r[3] as PackedByteArray).get_string_from_utf8()]


## Waits (a frame at a time) until this node is in the tree - it's added deferred.
func get_tree_safe() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	while not is_inside_tree() and tree != null:
		await tree.process_frame


func _headers(auth: bool, extra: Array = []) -> PackedStringArray:
	var h := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json", "Accept: application/json"])
	h.append("Authorization: Bearer " + (access_token if auth and access_token != "" else KEY))
	for e in extra:
		h.append(String(e))
	return h


## One REST call. `auth`: send the player's access token (refreshed first if it's about to
## run out, and once more after a 401).
func call_api(method: int, path: String, body = null, auth := true, extra: Array = []) -> Dictionary:
	if auth:
		if refresh_token == "":
			return _fail(401, "Not signed in.")
		if access_token == "" or Time.get_unix_time_from_system() > expires_at - 60.0:
			var rr := await refresh()
			if not rr["ok"]:
				return rr
	var text := "" if body == null else JSON.stringify(body)
	var r: Array = await _send(method, URL + path, _headers(auth, extra), text)
	if auth and int(r[1]) == 401 and refresh_token != "":
		var rr := await refresh()
		if not rr["ok"]:
			return rr
		r = await _send(method, URL + path, _headers(auth, extra), text)
	return _result(int(r[0]), int(r[1]), String(r[2]))


func _result(result: int, code: int, text, error := "") -> Dictionary:
	var data = null
	if text is String and text != "":
		var j := JSON.new()
		if j.parse(text) == OK:
			data = j.data
	var was_offline := offline
	offline = result != HTTPRequest.RESULT_SUCCESS or code == 0
	var ok := not offline and code >= 200 and code < 300
	if error == "" and not ok:
		error = _error_text(code, data)
	if offline != was_offline:
		changed.emit()
	return {"ok": ok, "code": code, "data": data, "error": error}


## A result made here, without asking the server (bad input, not signed in...).
static func _fail(code: int, error: String) -> Dictionary:
	return {"ok": code >= 200 and code < 300, "code": code, "data": null, "error": error}


## A short message for the player from Supabase's error replies.
static func _error_text(code: int, data) -> String:
	if code == 0:
		return "Can't reach the server. You can keep playing as a guest."
	var msg := ""
	var err_code := ""
	if data is Dictionary:
		for k in ["msg", "message", "error_description", "error"]:
			if data.has(k) and data[k] is String and String(data[k]) != "":
				msg = String(data[k])
				break
		err_code = String(data.get("error_code", data.get("code", "")))
	var low := msg.to_lower()
	if err_code == "email_not_confirmed" or low.contains("email not confirmed"):
		return "Check your email and confirm your account, then sign in."
	if err_code == "invalid_credentials" or low.contains("invalid login"):
		return "Wrong email or password."
	if err_code == "user_already_exists" or low.contains("already registered"):
		return "There's already an account with that email. Sign in instead."
	if err_code == "weak_password" or low.contains("password should"):
		return "Choose a longer password (at least 6 characters)."
	if err_code == "23505" or low.contains("duplicate key"):
		return "That display name is taken. Try another."
	if low.contains("banned"):
		return "This account is banned."
	if code == 429 or err_code == "over_request_rate_limit" or err_code == "over_email_send_rate_limit":
		return "Too many tries. Wait a minute and try again."
	if msg != "":
		return msg
	return "The server said no (HTTP %d)." % code


# ------------------------------------------------------------------ accounts
static func valid_email(e: String) -> bool:
	var at := e.find("@")
	return at > 0 and e.find(".", at) > at + 1 and not e.contains(" ") and e.length() <= 254


static func valid_name(n: String) -> bool:
	var re := RegEx.create_from_string(NAME_RE)
	return re.search(n) != null


## Create an account. If the project needs email confirmation there's no session yet:
## {"ok": true, "confirm": true}. Otherwise the player is signed in and named.
func sign_up(mail: String, password: String, name: String) -> Dictionary:
	mail = mail.strip_edges()
	name = name.strip_edges()
	if not valid_email(mail):
		return _fail(400, "Enter a valid email address.")
	if password.length() < 6:
		return _fail(400, "Choose a longer password (at least 6 characters).")
	if not valid_name(name):
		return _fail(400, "Display name: 3 to 20 letters, numbers, spaces or _.")
	var r := await call_api(HTTPClient.METHOD_POST, "/auth/v1/signup",
		{"email": mail, "password": password, "data": {"display_name": name}}, false)
	if not r["ok"]:
		return r
	var d = r["data"]
	if d is Dictionary and d.has("access_token"):
		_take_session(d)
		display_name = name
		var n := await set_display_name(name)
		if not n["ok"]:
			r["name_error"] = n["error"]
		save_tokens()
		changed.emit()
		return r
	r["confirm"] = true
	email = mail
	display_name = name
	return r


func sign_in(mail: String, password: String) -> Dictionary:
	mail = mail.strip_edges()
	if not valid_email(mail):
		return _fail(400, "Enter a valid email address.")
	if password == "":
		return _fail(400, "Enter your password.")
	var r := await call_api(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password",
		{"email": mail, "password": password}, false)
	if not r["ok"]:
		return r
	_take_session(r["data"])
	await fetch_profile()
	# a name chosen at sign-up while email confirmation was pending
	if display_name == "" and r["data"] is Dictionary:
		var meta = (r["data"] as Dictionary).get("user", {}).get("user_metadata", {})
		var wanted := String(meta.get("display_name", "")) if meta is Dictionary else ""
		if valid_name(wanted):
			var n := await set_display_name(wanted)
			if not n["ok"]:
				r["name_error"] = n["error"]
	save_tokens()
	changed.emit()
	return r


## Get a new access token with the remembered refresh token (on start and when it runs out).
## An invalid token signs the player out; no connection keeps it for next time.
func refresh() -> Dictionary:
	if refresh_token == "":
		return _fail(401, "Not signed in.")
	if _refreshing:                              # another call is refreshing: wait for it
		while _refreshing:
			await (Engine.get_main_loop() as SceneTree).process_frame
		return _fail(200 if access_token != "" else 401, "" if access_token != "" else "Not signed in.")
	_refreshing = true
	var r := await call_api(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": refresh_token}, false)
	_refreshing = false
	if r["ok"] and r["data"] is Dictionary:
		_take_session(r["data"])
		save_tokens()
	elif int(r["code"]) >= 400 and int(r["code"]) < 500:
		_clear(true)                               # revoked or expired: back to guest
		r["error"] = "Your sign-in ran out. Sign in again to use cloud saves."
	return r


func sign_out() -> void:
	if access_token != "":
		await call_api(HTTPClient.METHOD_POST, "/auth/v1/logout", {}, true)
	_clear(true)


func _take_session(d: Dictionary) -> void:
	access_token = String(d.get("access_token", ""))
	refresh_token = String(d.get("refresh_token", refresh_token))
	expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))
	var u = d.get("user", {})
	if u is Dictionary:
		user_id = String(u.get("id", user_id))
		email = String(u.get("email", email))


func _clear(forget: bool) -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	session_id = ""
	expires_at = 0.0
	if forget:
		display_name = ""
		if FileAccess.file_exists(token_file):
			DirAccess.remove_absolute(token_file)
	_set_js_unload()
	changed.emit()


func save_tokens() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "refresh_token", refresh_token)
	cfg.set_value("account", "user_id", user_id)
	cfg.set_value("account", "email", email)
	cfg.set_value("account", "display_name", display_name)
	cfg.save(token_file)


func load_tokens() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(token_file) != OK:
		return
	refresh_token = String(cfg.get_value("account", "refresh_token", ""))
	user_id = String(cfg.get_value("account", "user_id", ""))
	email = String(cfg.get_value("account", "email", ""))
	display_name = String(cfg.get_value("account", "display_name", ""))


func fetch_profile() -> Dictionary:
	var r := await call_api(HTTPClient.METHOD_GET, "/rest/v1/profiles?id=eq.%s&select=display_name" % user_id)
	if r["ok"] and r["data"] is Array and not (r["data"] as Array).is_empty():
		var n = r["data"][0].get("display_name")
		display_name = String(n) if n != null else ""
	return r


func set_display_name(name: String) -> Dictionary:
	name = name.strip_edges()
	if not valid_name(name):
		return _fail(400, "Display name: 3 to 20 letters, numbers, spaces or _.")
	var r := await call_api(HTTPClient.METHOD_PATCH, "/rest/v1/profiles?id=eq.%s" % user_id,
		{"display_name": name}, true, ["Prefer: return=minimal"])
	if r["ok"]:
		display_name = name
		save_tokens()
		changed.emit()
	return r


# ------------------------------------------------------------------ play sessions
static func input_name() -> String:
	if InputMode.is_touch():
		return "touch"
	if InputMode.is_pad():
		return "gamepad"
	return "keyboard"


static func platform_name() -> String:
	var p := OS.get_name()
	if OS.has_feature("web"):
		p = "Web"
		for f in ["web_windows", "web_macos", "web_linuxbsd", "web_android", "web_ios"]:
			if OS.has_feature(f):
				p += " " + f.trim_prefix("web_")
	return p.left(60)


func start_session() -> Dictionary:
	session_id = ""
	var r := await call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/start_session",
		{"p_device": DeviceProfile.kind, "p_input": input_name(), "p_platform": platform_name()})
	if r["ok"] and r["data"] is String:
		session_id = String(r["data"])
	_set_js_unload()
	return r


## {ok, kicked?, banned?, reason?} from the server, or an error result when offline.
func heartbeat(district: String) -> Dictionary:
	if session_id == "":
		return _fail(400, "No session.")
	var r := await call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/heartbeat",
		{"p_session": session_id, "p_input": input_name(), "p_district": district.left(60) if district != "" else null})
	if r["ok"] and r["data"] is Dictionary:
		var d: Dictionary = r["data"]
		r["kicked"] = bool(d.get("kicked", false))
		r["banned"] = bool(d.get("banned", false))
		r["reason"] = String(d.get("reason", "")) if d.get("reason") != null else ""
		if r["kicked"] or r["banned"]:
			session_id = ""
			_set_js_unload()
	return r


func end_session() -> Dictionary:
	if session_id == "":
		return _fail(200, "")
	var sid := session_id
	session_id = ""
	_set_js_unload()
	return await call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/end_session", {"p_session": sid})


## Browser: when the tab closes, end the session with a keep-alive request (best effort -
## the server also treats a session as gone after 90 s without a heartbeat).
func _set_js_unload() -> void:
	if not OS.has_feature("web"):
		return
	var info := {"url": URL + "/rest/v1/rpc/end_session", "key": KEY, "token": access_token, "session": session_id}
	var js := "window.monroviaSession = %s;" % JSON.stringify(info)
	if not _js_unload_set:
		_js_unload_set = true
		js += """window.addEventListener('pagehide', function () {
			var s = window.monroviaSession;
			if (!s || !s.session || !s.token) return;
			try { fetch(s.url, {method: 'POST', keepalive: true, headers: {'apikey': s.key,
				'Authorization': 'Bearer ' + s.token, 'Content-Type': 'application/json'},
				body: JSON.stringify({p_session: s.session})}); } catch (e) {}
		});"""
	JavaScriptBridge.eval(js, true)


# ------------------------------------------------------------------ cloud saves
## Upload a save (the local save file's contents). Only one upload at a time; a newer save
## made meanwhile replaces any waiting one.
func upload_save(data: Dictionary) -> Dictionary:
	if not signed_in():
		return _fail(401, "Not signed in.")
	var text := JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _fail(413, "Save is too big for the cloud.")
	if _upload_busy:
		_upload_next = data
		return {"ok": true, "code": 202, "data": null, "error": "", "queued": true}
	_upload_busy = true
	var row := {"user_id": user_id, "data": data, "version": int(data.get("version", 1)),
		"updated_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())) + "Z"}
	var r := await call_api(HTTPClient.METHOD_POST, "/rest/v1/saves?on_conflict=user_id", row, true,
		["Prefer: resolution=merge-duplicates,return=minimal"])
	_upload_busy = false
	if _upload_next != null:
		var nxt: Dictionary = _upload_next
		_upload_next = null
		return await upload_save(nxt)
	return r


## The cloud save: {"ok": true, "save": Dictionary or null (none yet), "unix": when it was saved}.
func fetch_save() -> Dictionary:
	var r := await call_api(HTTPClient.METHOD_GET, "/rest/v1/saves?user_id=eq.%s&select=data,version,updated_at" % user_id)
	r["save"] = null
	r["unix"] = 0.0
	if r["ok"] and r["data"] is Array and not (r["data"] as Array).is_empty():
		var row: Dictionary = r["data"][0]
		if row.get("data") is Dictionary and not (row["data"] as Dictionary).is_empty():
			r["save"] = row["data"]
			r["unix"] = save_time(row["data"], String(row.get("updated_at", "")))
	return r


## When a save was made (unix seconds): its own saved_unix, else the server's updated_at.
static func save_time(save: Dictionary, updated_at := "") -> float:
	if save.has("saved_unix"):
		return float(save["saved_unix"])
	if updated_at != "":
		var s := updated_at.replace("T", " ")
		for cut in ["+", "Z", "."]:
			var i := s.find(cut, 10)
			if i > 0:
				s = s.left(i)
		return float(Time.get_unix_time_from_datetime_string(s))
	return 0.0
