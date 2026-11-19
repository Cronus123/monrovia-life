class_name TitleAccount
extends PanelContainer
## The title screen's account panel: sign in or create an account (email, password, display
## name), see who you're signed in as, change the display name, sign out - and, after
## signing in, the offer to load a cloud save that's newer than the one on this device.
## Playing as a guest stays the default; nothing here is needed to play.
## Works with a keyboard, touch (the browser's on-screen keyboard opens on the text boxes)
## and a gamepad (d-pad / stick between fields and buttons, A on a text box opens the
## on-screen keyboard where the platform has one, B goes back).

const YELLOW := Color("#f5c518")
const NAVY := Color(0.063, 0.102, 0.196)

var title                                 # proto3d/title.gd
var busy := false
static var _cloud_checked := false        # once per run (and again after each sign-in)

var _heading: Label
var _form: VBoxContainer                  # guest: sign in / create account
var _email: LineEdit
var _password: LineEdit
var _name: LineEdit
var _sign_in: Button
var _create: Button
var _signed: VBoxContainer                # signed in: name, sign out
var _who: Label
var _rename: LineEdit
var _rename_btn: Button
var _sign_out: Button
var _offer: VBoxContainer                 # a newer cloud save
var _offer_text: Label
var _offer_load: Button
var _offer_keep: Button
var _status: Label
var _back: Button
var _cloud_save = null                    # the save on offer


func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAVY, 0.97)
	sb.border_color = Color(YELLOW, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(20)
	sb.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	var half := minf(260.0, get_viewport_rect().size.x / 2.0 - 12.0)
	offset_left = -half
	offset_right = half
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 24)
	_heading.add_theme_color_override("font_color", YELLOW)
	col.add_child(_heading)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 6)
	col.add_child(_form)
	_email = _field(_form, "Email", "you@example.com")
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_password = _field(_form, "Password", "at least 6 characters")
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_name = _field(_form, "Display name (new accounts)", "3-20 letters, numbers, _")
	_name.max_length = 20
	_sign_in = _button(_form, "Sign in", _on_sign_in)
	_create = _button(_form, "Create account", _on_create)
	_email.text_submitted.connect(func(_t): _password.grab_focus())
	_password.text_submitted.connect(func(_t):
		if _name.text.strip_edges() == "":
			_on_sign_in()
		else:
			_name.grab_focus())
	_name.text_submitted.connect(func(_t): _on_create())

	_signed = VBoxContainer.new()
	_signed.add_theme_constant_override("separation", 6)
	col.add_child(_signed)
	_who = Label.new()
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_who.add_theme_font_size_override("font_size", 16)
	_signed.add_child(_who)
	_rename = _field(_signed, "Display name", "3-20 letters, numbers, _")
	_rename.max_length = 20
	_rename.text_submitted.connect(func(_t): _on_rename())
	_rename_btn = _button(_signed, "Change name", _on_rename)
	_sign_out = _button(_signed, "Sign out", _on_sign_out)

	_offer = VBoxContainer.new()
	_offer.add_theme_constant_override("separation", 6)
	col.add_child(_offer)
	_offer_text = Label.new()
	_offer_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offer_text.add_theme_font_size_override("font_size", 16)
	_offer.add_child(_offer_text)
	_offer_load = _button(_offer, "Load the cloud save", _on_offer_load)
	_offer_keep = _button(_offer, "Keep this device's save", close)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	col.add_child(_status)
	_back = _button(col, "Back", close)


func _field(parent: Control, label: String, hint: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_font_size_override("font_size", 18)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0.45)
	n.set_content_margin_all(8)
	var f := n.duplicate() as StyleBoxFlat
	f.border_color = YELLOW
	f.set_border_width_all(2)
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	# gamepad A on a text box: bring up the on-screen keyboard where there is one
	e.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventJoypadButton and ev.is_action_pressed("ui_accept") and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			DisplayServer.virtual_keyboard_show(e.text, Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT if not e.secret else DisplayServer.KEYBOARD_TYPE_PASSWORD))
	parent.add_child(e)
	return e


func _button(parent: Control, label: String, cb: Callable) -> Button:
	var b: Button = title._styled_button(label)
	b.name = label.replace(" ", "").replace("'", "")
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	_cloud_save = null
	_status.text = ""
	_show_view()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	_cloud_save = null
	title.account_closed()


func _show_view() -> void:
	var on := Online.get_instance()
	var offer := _cloud_save != null
	_offer.visible = offer
	_form.visible = not offer and not on.signed_in()
	_signed.visible = not offer and on.signed_in()
	_back.visible = not offer
	if offer:
		_heading.text = "Cloud save"
		_offer_load.grab_focus.call_deferred()
	elif on.signed_in():
		_heading.text = "Account"
		_who.text = "Signed in as %s\n%s\nYour game saves to this device and the cloud." % [on.display_name if on.display_name != "" else "(no name yet)", on.email]
		_rename.text = on.display_name
		_sign_out.grab_focus.call_deferred()
	else:
		_heading.text = "Sign in"
		if _email.text == "" and on.email != "":
			_email.text = on.email
		(_email if _email.text == "" else _password).grab_focus.call_deferred()


func _set_busy(on: bool, text := "") -> void:
	busy = on
	for b in [_sign_in, _create, _sign_out, _rename_btn, _offer_load]:
		(b as Button).disabled = on
	if text != "":
		_status.text = text


# ------------------------------------------------------------------ actions
func _on_sign_in() -> void:
	if busy:
		return
	_set_busy(true, "Signing in...")
	var r: Dictionary = await Online.get_instance().sign_in(_email.text, _password.text)
	_set_busy(false)
	if not r["ok"]:
		_status.text = String(r["error"])
		return
	_password.text = ""
	_status.text = String(r.get("name_error", ""))
	await _after_sign_in()


func _on_create() -> void:
	if busy:
		return
	_set_busy(true, "Creating your account...")
	var r: Dictionary = await Online.get_instance().sign_up(_email.text, _password.text, _name.text)
	_set_busy(false)
	if not r["ok"]:
		_status.text = String(r["error"])
		return
	_password.text = ""
	if r.get("confirm", false):
		_status.text = "Account created. Open the email we sent to %s to confirm it, then sign in here." % _email.text.strip_edges()
		_sign_in.grab_focus()
		return
	_status.text = String(r.get("name_error", ""))
	await _after_sign_in()


func _after_sign_in() -> void:
	var offered := await check_cloud(true)
	if not offered:
		if _status.text == "":
			close()
		else:
			_show_view()                         # e.g. the name was taken: fix it here


func _on_rename() -> void:
	if busy:
		return
	_set_busy(true, "Saving...")
	var r: Dictionary = await Online.get_instance().set_display_name(_rename.text)
	_set_busy(false)
	_status.text = "Name saved." if r["ok"] else String(r["error"])
	_show_view()


func _on_sign_out() -> void:
	if busy:
		return
	_set_busy(true, "Signing out...")
	await Online.get_instance().sign_out()
	_set_busy(false)
	_status.text = "Signed out. You're playing as a guest; your local save is still here."
	_show_view()


func _on_offer_load() -> void:
	if _cloud_save == null:
		return
	var text := JSON.stringify(_cloud_save)
	if not title.import_save_text(text):
		_status.text = "That cloud save couldn't be loaded."
		return
	get_tree().reload_current_scene()       # the menu now offers Continue with it


# ------------------------------------------------------------------ start-up and cloud
## From the title's _ready: signed in last time? Get a fresh token in the background, then
## look for a newer cloud save. Offline: the game just stays a guest game for now.
func start() -> void:
	var on := Online.get_instance()
	if not on.signed_in():
		return
	if on.access_token == "":
		var r: Dictionary = await on.refresh()
		if not r["ok"]:
			return
		await on.fetch_profile()
		on.save_tokens()
		on.changed.emit()
	if not _cloud_checked:
		await check_cloud(false)


## Offers the cloud save if it's newer than this device's (or there's none here).
## Returns true if the offer is showing.
func check_cloud(after_sign_in: bool) -> bool:
	_cloud_checked = true
	var on := Online.get_instance()
	if not on.signed_in():
		return false
	var r: Dictionary = await on.fetch_save()
	if not r["ok"] or r["save"] == null or not is_inside_tree() or title._starting:
		return false
	var local := local_save_time()
	if SaveSystem.has_save() and float(r["unix"]) <= local + 2.0:
		return false
	_cloud_save = r["save"]
	var save: Dictionary = _cloud_save
	_offer_text.text = "Your cloud save (%s, saved %s) is newer than the save on this device%s.\nLoad it?" % [
		GameState.money_text(int(save.get("money", 0))), _when(float(r["unix"])),
		"" if SaveSystem.has_save() else " (there isn't one yet)"]
	_status.text = ""
	if not after_sign_in:
		title._menu.visible = false
	_show_view()
	visible = true
	return true


## When this device's save was made (unix seconds), 0 without one.
static func local_save_time(path: String = SaveSystem.PATH) -> float:
	if not FileAccess.file_exists(path):
		return 0.0
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.has("saved_unix"):
		return float(d["saved_unix"])
	return float(FileAccess.get_modified_time(path))


static func _when(unix: float) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
