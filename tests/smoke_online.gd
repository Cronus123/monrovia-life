extends SceneTree
## Player accounts, play sessions and cloud saves (proto3d/game/online.gd) without the
## network: a fake transport plays the Supabase server and records every request.
##  - input checks, sign-up (with and without email confirmation), sign-in, wrong password,
##    unconfirmed email, the refresh token remembered (never the password), refresh when the
##    access token runs out and after a 401, sign-out
##  - start_session / heartbeat (ok, kicked, banned) / end_session, with the device, input
##    scheme and district
##  - cloud saves: upsert of your own row, size limit, fetch, which save is newer
##  - offline: every call fails gracefully and the game stays a guest game
##  - in the city: New Game starts a session, saves upload, the heartbeat runs, a kick shows
##    the reason and goes back to the title; nothing is sent for guests
## Run: Godot.exe --headless --path . --script res://tests/smoke_online.gd

const OUT := "res://tests/output/online"

var failures := 0
var checks := 0
var on: Online
var reqs: Array = []               # [method, url, headers, body]
var replies: Array = []           # queued [result, code, body] (else the default handler)
var server_offline := false
var heartbeat_reply := {"ok": true}
var cloud_rows: Array = []
var m


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEONLINE CHECK FAILED: ", what)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	run()


## The fake server.
func fake(method: int, url: String, headers: PackedStringArray, body: String) -> Array:
	await process_frame
	reqs.append([method, url, headers, body])
	if server_offline:
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, ""]
	if not replies.is_empty():
		return replies.pop_front()
	var path := url.trim_prefix(Online.URL)
	if path.begins_with("/auth/v1/token?grant_type=refresh_token"):
		return [0, 200, JSON.stringify({"access_token": "acc-2", "refresh_token": "ref-2", "expires_in": 3600,
			"user": {"id": "u-1", "email": "player@example.com"}})]
	if path.begins_with("/auth/v1/token?grant_type=password"):
		return [0, 200, JSON.stringify({"access_token": "acc-1", "refresh_token": "ref-1", "expires_in": 3600,
			"user": {"id": "u-1", "email": "player@example.com", "user_metadata": {"display_name": "Kollie_99"}}})]
	if path.begins_with("/rest/v1/profiles") and method == HTTPClient.METHOD_GET:
		return [0, 200, JSON.stringify([{"display_name": null}])]
	if path.begins_with("/rest/v1/profiles") and method == HTTPClient.METHOD_PATCH:
		return [0, 204, ""]
	if path == "/rest/v1/rpc/start_session":
		return [0, 200, JSON.stringify("11111111-2222-3333-4444-555555555555")]
	if path == "/rest/v1/rpc/heartbeat":
		return [0, 200, JSON.stringify(heartbeat_reply)]
	if path == "/rest/v1/rpc/end_session":
		return [0, 204, ""]
	if path.begins_with("/rest/v1/saves") and method == HTTPClient.METHOD_POST:
		return [0, 201, ""]
	if path.begins_with("/rest/v1/saves") and method == HTTPClient.METHOD_GET:
		return [0, 200, JSON.stringify(cloud_rows)]
	if path == "/auth/v1/logout":
		return [0, 204, ""]
	return [0, 404, "{}"]


func last(path_start: String) -> Array:
	for i in range(reqs.size() - 1, -1, -1):
		if String(reqs[i][1]).trim_prefix(Online.URL).begins_with(path_start):
			return reqs[i]
	return []


## The save data in the newest upload ({} if none).
func uploaded() -> Dictionary:
	for i in range(reqs.size() - 1, -1, -1):
		if String(reqs[i][1]).contains("/rest/v1/saves") and reqs[i][0] == HTTPClient.METHOD_POST:
			var d = JSON.parse_string(String(reqs[i][3]))
			return d["data"] if d is Dictionary else {}
	return {}


func header(req: Array, name: String) -> String:
	for h in req[2]:
		if String(h).to_lower().begins_with(name.to_lower() + ":"):
			return String(h).substr(name.length() + 1).strip_edges()
	return ""


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func new_online() -> Online:
	var o := Online.new()
	o.token_file = OUT + "/online.cfg"
	o.transport = fake
	root.add_child(o)
	Online._inst = o                      # what the game's Online.get_instance() returns
	return o


func run() -> void:
	await process_frame
	if FileAccess.file_exists(OUT + "/online.cfg"):
		DirAccess.remove_absolute(OUT + "/online.cfg")
	on = new_online()

	print("accounts")
	var r: Dictionary = await on.sign_up("not-an-email", "secret12", "Kollie")
	check(not r["ok"] and String(r["error"]).contains("email") and reqs.is_empty(), "a bad email is caught before sending")
	r = await on.sign_up("player@example.com", "123", "Kollie")
	check(not r["ok"] and String(r["error"]).contains("password"), "a short password too")
	r = await on.sign_up("player@example.com", "secret12", "K!")
	check(not r["ok"] and String(r["error"]).contains("Display name"), "and a bad display name")
	check(Online.valid_name("Big Talk_1") and not Online.valid_name("ab") and not Online.valid_name("x".repeat(21)), "display names: 3-20 of A-Z a-z 0-9 _ space")
	# a project with email confirmation: the account exists but there's no session yet
	replies.append([0, 200, JSON.stringify({"id": "u-1", "email": "player@example.com", "confirmation_sent_at": "2026-11-17T20:00:00Z"})])
	r = await on.sign_up("player@example.com", "secret12", "Kollie_99")
	var req: Array = last("/auth/v1/signup")
	var sent = JSON.parse_string(String(req[3]))
	check(r["ok"] and r.get("confirm", false) and not on.signed_in(), "sign-up waiting for email confirmation: not signed in yet")
	check(sent["email"] == "player@example.com" and sent["data"]["display_name"] == "Kollie_99" and header(req, "apikey") == Online.KEY,
		"sign-up sends the email, the display name and the publishable key")
	replies.append([0, 400, JSON.stringify({"code": 400, "error_code": "email_not_confirmed", "msg": "Email not confirmed"})])
	r = await on.sign_in("player@example.com", "secret12")
	check(not r["ok"] and String(r["error"]).contains("confirm"), "signing in before confirming says so: %s" % r["error"])
	replies.append([0, 400, JSON.stringify({"code": 400, "error_code": "invalid_credentials", "msg": "Invalid login credentials"})])
	r = await on.sign_in("player@example.com", "wrong")
	check(not r["ok"] and String(r["error"]) == "Wrong email or password.", "a wrong password")
	r = await on.sign_in("player@example.com", "secret12")
	check(r["ok"] and on.signed_in() and on.user_id == "u-1" and on.access_token == "acc-1", "sign-in")
	var patch := last("/rest/v1/profiles?id=eq.u-1")
	check(not patch.is_empty() and patch[0] == HTTPClient.METHOD_PATCH and JSON.parse_string(String(patch[3])) == {"display_name": "Kollie_99"}
		and header(patch, "Authorization") == "Bearer acc-1" and on.display_name == "Kollie_99",
		"the name chosen at sign-up is set on the profile after the first sign-in (as the player)")
	var cfg_text := FileAccess.get_file_as_string(OUT + "/online.cfg")
	check(cfg_text.contains("ref-1") and not cfg_text.contains("secret12") and not cfg_text.contains("acc-1"),
		"the refresh token is remembered, never the password (or the access token)")
	var again := Online.new()
	again.token_file = OUT + "/online.cfg"
	again.load_tokens()
	check(again.signed_in() and again.refresh_token == "ref-1" and again.display_name == "Kollie_99", "and read back on the next start")
	again.free()

	print("tokens")
	on.expires_at = Time.get_unix_time_from_system() - 10.0
	var n := reqs.size()
	r = await on.fetch_profile()
	check(String(reqs[n][1]).contains("grant_type=refresh_token") and JSON.parse_string(String(reqs[n][3]))["refresh_token"] == "ref-1"
		and on.access_token == "acc-2" and header(reqs[n + 1], "Authorization") == "Bearer acc-2",
		"an expired access token is refreshed first")
	replies.append([0, 401, JSON.stringify({"message": "JWT expired"})])
	n = reqs.size()
	r = await on.fetch_profile()
	check(r["ok"] and reqs.size() == n + 3 and String(reqs[n + 1][1]).contains("refresh_token"), "a 401 refreshes and retries once")
	replies.append([0, 400, JSON.stringify({"error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"})])
	on.access_token = ""
	r = await on.refresh()
	check(not r["ok"] and not on.signed_in() and not FileAccess.file_exists(OUT + "/online.cfg"), "a revoked refresh token signs out (back to guest)")
	r = await on.sign_in("player@example.com", "secret12")

	print("sessions")
	r = await on.start_session()
	req = last("/rest/v1/rpc/start_session")
	sent = JSON.parse_string(String(req[3]))
	check(r["ok"] and on.session_id == "11111111-2222-3333-4444-555555555555", "start_session returns the session id")
	check(sent["p_device"] in ["phone", "tablet", "desktop"] and sent["p_input"] in ["keyboard", "touch", "gamepad"] and String(sent["p_platform"]) != "",
		"with the device, input scheme and platform (%s)" % str(sent))
	r = await on.heartbeat("Sinkor")
	sent = JSON.parse_string(String(last("/rest/v1/rpc/heartbeat")[3]))
	check(r["ok"] and not r["kicked"] and sent["p_session"] == on.session_id and sent["p_district"] == "Sinkor", "heartbeat with the district")
	heartbeat_reply = {"ok": false, "kicked": true, "reason": "Removed by an admin"}
	r = await on.heartbeat("Sinkor")
	check(r["kicked"] and r["reason"] == "Removed by an admin" and on.session_id == "", "a kick comes back with its reason")
	heartbeat_reply = {"ok": false, "banned": true, "reason": "cheating"}
	await on.start_session()
	r = await on.heartbeat("")
	check(r["banned"] and r["reason"] == "cheating", "and a ban")
	heartbeat_reply = {"ok": true}
	await on.start_session()
	r = await on.end_session()
	check(r["ok"] and on.session_id == "" and JSON.parse_string(String(last("/rest/v1/rpc/end_session")[3]))["p_session"] == "11111111-2222-3333-4444-555555555555",
		"end_session")

	print("cloud saves")
	var save := {"version": 1, "money": 4321, "pos": [1, 2, 3], "saved_unix": 1800000000}
	r = await on.upload_save(save)
	req = last("/rest/v1/saves")
	sent = JSON.parse_string(String(req[3]))
	check(r["ok"] and req[0] == HTTPClient.METHOD_POST and String(req[1]).contains("on_conflict=user_id")
		and header(req, "Prefer").contains("resolution=merge-duplicates") and sent["user_id"] == "u-1" and sent["data"]["money"] == 4321,
		"upload = upsert of the player's own row")
	r = await on.upload_save({"version": 1, "money": 1, "junk": "x".repeat(300000)})
	check(not r["ok"] and r["code"] == 413, "saves over the server's 256 KB limit aren't sent")
	cloud_rows = []
	r = await on.fetch_save()
	check(r["ok"] and r["save"] == null, "no cloud save yet")
	cloud_rows = [{"data": save, "version": 1, "updated_at": "2027-01-15T08:00:00.123+00:00"}]
	r = await on.fetch_save()
	check(r["save"] is Dictionary and int(r["save"]["money"]) == 4321 and r["unix"] == 1800000000.0, "fetch the cloud save and when it was made")
	check(Online.save_time({}, "2027-01-15T08:00:00.123+00:00") == float(Time.get_unix_time_from_datetime_string("2027-01-15 08:00:00")),
		"(older saves: the server's updated_at)")
	var local := OUT + "/local_save.json"
	var f := FileAccess.open(local, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "money": 5, "saved_unix": 1700000000}))
	f.close()
	check(TitleAccount.local_save_time(local) == 1700000000.0 and TitleAccount.local_save_time(OUT + "/none.json") == 0.0,
		"this device's save time, to offer a newer cloud save")

	print("offline")
	server_offline = true
	r = await on.heartbeat("x")
	r = await on.fetch_save()
	check(not r["ok"] and r["code"] == 0 and on.offline and String(r["error"]).contains("guest"), "offline: calls fail with a guest-play message")
	r = await on.upload_save(save)
	check(not r["ok"] and on.signed_in(), "and the account is kept for when the connection is back")
	server_offline = false
	r = await on.fetch_save()
	check(r["ok"] and not on.offline, "back online")
	await on.sign_out()
	check(not on.signed_in() and not last("/auth/v1/logout").is_empty() and not FileAccess.file_exists(OUT + "/online.cfg"), "sign out")

	await city_checks()

	if failures == 0:
		print("SMOKEONLINE TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKEONLINE TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)


func city_checks() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json"):
		print("  (city not generated: skipping the in-game checks)")
		return
	print("in the city")
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.title_mode = true
	m.save_path = OUT + "/save.json"
	root.add_child(m)
	check(await until(func(): return m.ready_done, 120.0), "the city loads")
	# a guest: nothing is sent
	var n := reqs.size()
	m.start_from_title(false)
	await until(func(): return not m._busy, 60.0)
	m.save_game()
	for i in 5:
		await process_frame
	check(reqs.size() == n and FileAccess.file_exists(OUT + "/save.json"), "guests: saved locally, nothing sent online")
	# signed in
	await on.sign_in("player@example.com", "secret12")
	n = reqs.size()
	await m.start_online_session()
	check(not last("/rest/v1/rpc/start_session").is_empty() and reqs.size() > n and m._heartbeat != null and not m._heartbeat.is_stopped()
		and is_equal_approx(m._heartbeat.wait_time, 30.0), "signed in: a session starts and a 30 s heartbeat runs")
	reqs.clear()                         # (the uploads above had saved_unix too)
	m.save_game()
	check(await until(func(): return uploaded().has("saved_unix"), 5.0),
		"saving uploads the save to the cloud too")
	await m._on_heartbeat()
	var hb = JSON.parse_string(String(last("/rest/v1/rpc/heartbeat")[3]))
	check(hb["p_district"] == m.shops.district_at(m.focus_pos()) and hb["p_input"] == "keyboard", "the heartbeat sends the district (%s) and input" % hb["p_district"])
	heartbeat_reply = {"ok": false, "kicked": true, "reason": "Server restarting for an update"}
	await m._on_heartbeat()
	check(m.hud.menu_open and paused and m._heartbeat.is_stopped(), "kicked: the game pauses and says why")
	heartbeat_reply = {"ok": true}
	paused = false
	m.hud.close_menu()
	await m.start_online_session()
	n = reqs.size()
	m._end_online_session()
	check(await until(func(): return not last("/rest/v1/rpc/end_session").is_empty() and reqs.size() > n, 5.0) and on.session_id == "",
		"quitting ends the session")
	# the server can't be reached: the game goes on
	server_offline = true
	await m.start_online_session()
	m.save_game()
	await m._on_heartbeat()
	check(not m.hud.menu_open and not paused and m.player.active, "offline: no session, no upload, and the game carries on")
	server_offline = false
	m.queue_free()
	await process_frame
