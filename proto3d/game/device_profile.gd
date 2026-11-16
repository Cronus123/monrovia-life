class_name DeviceProfile
extends RefCounted
## What the game is running on, worked out once at start-up: a phone, a tablet or a
## desktop/laptop, whether it has a touch screen, and the screen's safe area (notches,
## rounded corners, home bar). The browser build reads the browser's navigator through
## JavaScriptBridge; the desktop build reads the OS. Everything else (touch overlay,
## UI scale, light graphics) is decided from this.
##
## Testing: the browser build takes ?device=phone|tablet|desktop in the page address to
## pretend to be one (handy at desktop sizes); tests call classify() directly.

const PHONE := "phone"
const TABLET := "tablet"
const DESKTOP := "desktop"

## UI scale on top of the 1280x720 canvas stretch: phones and tablets are held further
## away / have smaller screens, so text and buttons are drawn bigger.
const UI_SCALE := {PHONE: 1.5, TABLET: 1.2, DESKTOP: 1.0}

static var kind := DESKTOP
static var touch := false             # has a touch screen
static var info := {}                 # what detection saw (for bug reports and tests)
static var _detected := false


## Detects once; later calls return the cached result.
static func detect(force: bool = false) -> String:
	if _detected and not force:
		return kind
	_detected = true
	info = read_platform()
	kind = classify(info)
	touch = bool(info.get("touch", false))
	return kind


static func is_phone() -> bool:
	return kind == PHONE


static func is_tablet() -> bool:
	return kind == TABLET


static func is_handheld() -> bool:
	return kind != DESKTOP


static func ui_scale() -> float:
	return float(UI_SCALE.get(kind, 1.0))


## Platform facts in one dictionary: ua, mobile (UA-CH hint), touch_points, touch,
## coarse (pointer: coarse), screen_w / screen_h (CSS px), dpr, override, platform.
static func read_platform() -> Dictionary:
	var d := {"platform": OS.get_name()}
	if OS.has_feature("web"):
		var js := """(function(){var n=navigator,s=screen,m=window.matchMedia;
			var o=(new URLSearchParams(location.search)).get('device')||'';
			return JSON.stringify({ua:n.userAgent||'',mobile:!!(n.userAgentData&&n.userAgentData.mobile),
			touch_points:n.maxTouchPoints||0,touch:('ontouchstart' in window)||(n.maxTouchPoints||0)>0,
			coarse:!!(m&&m('(pointer: coarse)').matches),screen_w:s.width||0,screen_h:s.height||0,
			dpr:window.devicePixelRatio||1,override:o});})()"""
		var res = JavaScriptBridge.eval(js, true)
		if typeof(res) == TYPE_STRING:
			var parsed = JSON.parse_string(res)
			if typeof(parsed) == TYPE_DICTIONARY:
				d.merge(parsed, true)
		return d
	var ds := DisplayServer.get_name()
	d["touch"] = ds != "headless" and DisplayServer.is_touchscreen_available()
	d["mobile"] = OS.has_feature("mobile")
	d["touch_points"] = 5 if d["touch"] else 0
	d["coarse"] = OS.has_feature("mobile")
	if ds != "headless":
		var sz := DisplayServer.screen_get_size()
		var sc := maxf(DisplayServer.screen_get_scale(), 1.0)
		d["screen_w"] = sz.x / sc
		d["screen_h"] = sz.y / sc
		d["dpr"] = sc
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--device="):
			d["override"] = a.substr(9)
	return d


## Phone / tablet / desktop from the facts above. Pure, so tests can feed it made-up
## devices. Rules: an explicit override wins; iPad and Android tablets are tablets
## (iPadOS reports a Mac user agent, but a Mac has no touch points); a phone is a mobile
## user agent or a touch-only screen whose short side is under 600 CSS px.
static func classify(d: Dictionary) -> String:
	var o := String(d.get("override", "")).to_lower()
	if o in [PHONE, TABLET, DESKTOP]:
		return o
	var ua := String(d.get("ua", "")).to_lower()
	var points := int(d.get("touch_points", 0))
	var coarse := bool(d.get("coarse", false))
	var short_side := minf(float(d.get("screen_w", 0)), float(d.get("screen_h", 0)))
	if ua.contains("ipad") or (ua.contains("macintosh") and points > 1):
		return TABLET
	if ua.contains("tablet") or ua.contains("kindle") or ua.contains("silk/") or ua.contains("playbook"):
		return TABLET
	if ua.contains("android") and not ua.contains("mobile"):
		return TABLET                        # Android tablets drop "Mobile" from the UA
	if ua.contains("iphone") or ua.contains("ipod") or ua.contains("windows phone") or (ua.contains("android") and ua.contains("mobile")):
		return PHONE
	if bool(d.get("mobile", false)):
		return PHONE if short_side < 600.0 or short_side == 0.0 else TABLET
	# no telling user agent (desktop app, privacy browsers): go by a touch-first screen
	if coarse and points > 0 and short_side > 0.0:
		return PHONE if short_side < 600.0 else TABLET
	return DESKTOP


## Safe-area insets in window pixels: Vector4(left, top, right, bottom).
static func safe_insets() -> Vector4:
	if OS.has_feature("web"):
		var js := """(function(){var d=document.createElement('div');
			d.style.cssText='position:fixed;left:0;top:0;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
			document.body.appendChild(d);var c=getComputedStyle(d),r=window.devicePixelRatio||1;
			var v=[c.paddingLeft,c.paddingTop,c.paddingRight,c.paddingBottom].map(function(x){return (parseFloat(x)||0)*r;});
			d.remove();return v.join(',');})()"""
		var res = JavaScriptBridge.eval(js, true)
		if typeof(res) == TYPE_STRING:
			var p := String(res).split(",")
			if p.size() == 4:
				return Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
		return Vector4.ZERO
	if DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	return Vector4(safe.position.x, safe.position.y, maxf(0.0, win.x - safe.end.x), maxf(0.0, win.y - safe.end.y))


## Insets converted to canvas (virtual) units for a viewport, with a small minimum margin
## on handhelds so nothing sits right on a rounded corner.
static func safe_margins(vp: Viewport) -> Vector4:
	var px := safe_insets()
	var win := Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else vp.get_visible_rect().size
	var vis := vp.get_visible_rect().size
	var k := vis.x / maxf(win.x, 1.0)
	var m := Vector4(px.x * k, px.y * k, px.z * k, px.w * k)
	if is_handheld():
		var floor_m := 8.0
		m = Vector4(maxf(m.x, floor_m), maxf(m.y, floor_m), maxf(m.z, floor_m), maxf(m.w, floor_m))
	return m


static func portrait(vp: Viewport) -> bool:
	var s := vp.get_visible_rect().size
	return s.y > s.x
