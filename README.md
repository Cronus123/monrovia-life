# Monrovia Life: Streets

An original open-world crime-action game set in a real-scale, 3D central Monrovia, Liberia,
from Mamba Point to Sinkor, built from OpenStreetMap. It's a LibGamer community game, and all of
its characters are fictional; shops and restaurants have made-up names.

The original top-down 2D version of the game is still in this project (`main.tscn`, `scripts/`)
and is tagged `v0.1-2d` in Git.

## What's in it
- **Real-scale Monrovia (about 5.6 × 5 km):** every street and building footprint from
  OpenStreetMap, real terrain, the Atlantic, the Mesurado River and Providence Island, street
  names, and landmarks such as the Executive Mansion, Capitol Building, Centennial Pavilion,
  Temple of Justice, University of Liberia and JFK Medical Center. The city streams in around you.
- **Traffic:** taxis, kekes, cars, SUVs, trucks and police patrols drive on the right, stop at
  traffic lights on the main roads, give way at other junctions, and honk if you block them.
- **Cars:** take any car (pull the driver out), a tyre model with real slides and power oversteer,
  weight transfer and anti-roll bars, per-vehicle handling (a light, tippy keke; heavy trucks),
  crash damage that dents the body where you hit, breaks headlights and knocks parts off, engine
  smoke, fire and explosions, an in-car radio with three stations, and drive-by shooting.
- **Physics:** people go limp (ragdolls) when hit and get up where they land; lamp posts and
  street signs topple, bins, drums, crates and market stalls scatter; climb low walls; swim
  (with limited breath) in the sea and the river.
- **Police:** a wanted level of 1 to 5 stars. Cruisers route through the streets to you, officers
  chase you on foot and shoot from 2 stars. Lose them out of sight or at a respray shop. Get caught
  and you're **ARRESTED**; run out of health and you're **DOWN AND OUT**, waking at JFK Medical Center.
- **Weapons:** fists (three-hit combos), baseball bat, machete, pistol, SMG and shotgun, with
  magazines and reloads (R), aiming over the shoulder (right mouse), recoil, muzzle flash and
  shell casings; a weapon wheel (hold Tab or LB: slow motion while you choose) and an ammo display.
  Weapon shops sell all of them, plus body armour. Dodge roll on C, crouch on Ctrl.
- **Animation:** Quaternius's Universal Animation Library retargeted onto the characters: smoother
  walking, jogging and sprinting, crouching, swimming, two-handed aiming that follows the camera up
  and down, upper-body reloads while moving, jab/cross/hook punch combos and hit reactions.
- **Missions:** Auntie Musu's 5-mission story, starting at Waterside (yellow M).
- **Big Talk Dweh:** Honourable Kpakolo "Big Talk" Dweh, an original fictional loudmouth who goes
  from shouting on a crate at Waterside to a radio show, a campaign (convoy, rallies, rice and
  T-shirts), a walled house off 16th Street in Sinkor and a final election-night choice: expose his
  stolen road fund, or help make him "Senator Dweh". His own jobs, lines and grudges; all data-driven
  (`proto3d/game/data/bigtalk.json`). He and his "Big Talk Progress Party" are made up.
- **Street life:** sellers at market stalls, people chatting outside shops, kids playing football on
  open ground, vendors pushing wheelbarrows, people sheltering under awnings when it rains, kekes
  pulling over for passengers, and more or fewer people out depending on the time of day.
- **Skills & perks:** Stamina, Driving, Shooting, Strength and Swimming grow as you use them;
  reputation from jobs unlocks perks (Market Mouth, Keke King, Hustler, Bush Runner, Cool Head,
  Roadside Mechanic, Big Talk Connect). See them in the pause menu; B uses a perk ability.
- **Side jobs and daily life:** taxi fares to real named places, cookshops that heal you, keke and
  taxi rental, and a safehouse in Fiamah, Sinkor, where you sleep and save.
- **World:** day and night with street lights and moonlight, drifting clouds, sunsets, stars,
  rain that wets the streets (puddles, reflections), an animated sea with shore foam, swaying
  palms, trees and grass, detailed buildings (zinc roofs with eaves, parapets, water tanks, AC
  units, balconies, shopfronts with awnings and made-up business names), city ambience, a
  minimap and a full map drawn from the real map data.

## Graphics quality
Settings → Display → Graphics quality. Measured on a GeForce GTX 760 at 1280 × 720 with
V-sync off (`tests/perf_presets.gd`, on foot, driving, rain and night):

| Preset | Renderer | Effects | Avg FPS | 1% low |
|---|---|---|---|---|
| Low | Compatibility (OpenGL) | no shadows, effects or grass | 178 | 109 |
| Medium (default) | Forward+ (Vulkan) | shadows, ambient occlusion, glow, auto exposure, motion blur | 106 | 96 |
| High | Forward+ (Vulkan) | + light bounce (SSIL), screen-space reflections, volumetric light shafts, longer view | 76 | 60 |

Switching to or from Low changes the renderer, so the game asks for a restart.

## Play
1. Install **Godot 4.7** (standard version) from https://godotengine.org/download.
2. Build the city data once (see below) — it isn't stored in Git because it's large.
3. Open `project.godot` in Godot and press F5: the title screen (`proto3d/title.tscn`) loads
   the city behind its menu. Or export the **Windows 3D City** preset
   (`build/windows-city/MonroviaCity.exe`).

A **new game** starts with Auntie Musu's tutorial, *Welcome to Monrovia* (walk, take the
taxi, drive to a cookshop, buy food, pick up a bat, hit a training dummy, open the weapon
wheel, rest at the safehouse to save). Turn it off in Settings > Gameplay.

**Playtesting:** press **F8** any time to report a bug. It takes a screenshot, asks for a
note and saves a folder in the game's user data (`%APPDATA%/Godot/app_userdata/Monrovia Life- Streets/bug_reports/`)
(screenshot, report with version, place, position and FPS, and the end of the log). Nothing
is uploaded: send the folder to the developers. The version is on the title screen.

## Browser version
`powershell -ExecutionPolicy Bypass -File tools\export_web.ps1` exports the **Web City** preset to
`build\web-city\`: the page, the engine (`index.wasm`, about 38 MB, ~9 MB gzipped) and the game
(`index.pck`, about 16 MB), plus the city tiles in `city\hi` and `city\lo` (650 files, ~280 MB)
that the game downloads over HTTP as you move (about 12.5 MB for the starting area).
It runs on the Compatibility (WebGL 2) renderer at the Low preset with lighter browser versions
of the city, sky and sea shaders. Saves live in the browser; the title screen has Export save
and Import save. F8 bug reports download a .txt and a .png.

Upload the whole folder to any static host: no special headers (single-threaded build), .wasm
served as `application/wasm`, files up to ~40 MB, about 660 files. Long cache times for
`city/*.glb` and gzip/brotli compression help. For Apache hosts (IONOS) the export writes
`.htaccess` (types, gzip, the page/engine/game always revalidated) and `city\.htaccess` (gzip
and a week's cache for the tiles and `city\meta\*.json`); GitHub Pages ignores both.

**Fast start:** the title menu shows as soon as the engine has started, over a drawn skyline;
the city streams in behind it and fades in when the tiles near the camera are ready. New Game
pressed before that waits for the starting area with a progress bar (Esc / B cancels). Each
detailed tile's metadata (`city\meta\*.json`: sidewalk paths, parking, trees, signs) is fetched
with the tile instead of being packed into `index.pck`, and the long music and ambience loops
are Ogg Vorbis (`tools\wav_to_ogg.py`).

**Offline cache:** the page is built from a custom HTML shell (`web\shell.html`) that registers
`sw.js` (template in `web\sw.js`). `tools\export_web.ps1` copies it into the build with
`BUILD` set to the Git commit (so each update replaces the cached engine and game) and `TILES`
set to a hash of the tile files (so players only download the city again when it changes).

Test it locally: `"<Blender>\5.3\python\bin\python.exe" -I tools\serve_web.py` and open
http://127.0.0.1:8060/. `tools\bench_web.ps1` runs a first-visit benchmark in a fresh Microsoft
Edge window (`?bench=1`: load time, FPS walking/sprinting/driving, download size, screenshots to
`build\screens\web\`).

## Accounts and cloud saves
Playing as a guest is the default: saves stay on the device, as before. **Sign in / Create
account** on the title screen takes an email, a password and a display name (3-20 letters,
numbers, spaces or _). Signed in, the game also saves to the cloud (every manual save and
autosave), and on sign-in it offers a cloud save that's newer than the one on the device. Only
the refresh token is kept on the device (`user://online.cfg`), never the password.
While you play, the game keeps a play session open on the server (a heartbeat every 30 s with
the input scheme and the district); if the server ends the session (kick or ban) the game says
why and goes back to the title. If the server can't be reached the game plays on as a guest.
The backend is Supabase (`proto3d/game/online.gd`, REST API over HTTPRequest; the publishable
key in it is meant for clients). The browser build ends the session when the tab closes.

## Controls
Every control can be changed in **Settings → Controls** (saved to `user://settings.cfg`).

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / drive | WASD or arrows | Left stick; RT accelerate, LT brake |
| Look / aim | Mouse | Right stick |
| Run | Shift | L3 |
| Jump / handbrake | Space | A |
| Shoot or punch (drive-by in a car) | Left mouse button | RB |
| Get in / out of a car | F | Y |
| Use shops, talk, missions | E | X |
| Horn | H | B |
| Change radio station | R | D-pad right |
| Taxi hire light | T | D-pad up |
| Camera view (third / first person) | V | R3 |
| Switch weapon | Q, 1, 2 | LB |
| Map | M | View (Back) |
| Pause (resume, settings, save, quit to title) | Esc | Start |
| Perk ability | B | hold View |
| Report a bug | F8 | pause menu > Report a bug |

**Settings** (from the start and pause menus): volumes for master, music, sound effects and
ambience; resolution, fullscreen, V-sync; graphics quality (Low, Medium, High); mouse/stick
sensitivity, invert Y, field of view; key bindings.

## Phones, tablets and gamepads
The game works out what it's running on at start-up (in the browser it reads the navigator through
`JavaScriptBridge`; `?device=phone`, `tablet` or `desktop` in the address pretends to be one):

- **Touch controls** (phones and tablets): a joystick under the left thumb (push it to the rim to
  run; in a car it steers and accelerates), drag on the right of the screen to look, and buttons in
  the right thumb's reach: Shoot, Jump/Brake, Aim, Car, Use, Weapon, Reload, Crouch, Roll (in a car:
  Horn, Radio, Hire). Small buttons along the top pause, open the map, switch the camera and use
  the perk. They show only while touch is being used.
- **Tablets** get bigger buttons that use both bottom corners (reload, crouch and roll by the left
  thumb), and phones and tablets draw the HUD and menus bigger. Everything stays inside the
  screen's safe area (notches, rounded corners, the home bar). Phones ask to be turned sideways.
- **Gamepads** (Xbox and PlayStation, in the browser too): every action, plus the title, pause,
  shop and settings menus (d-pad or left stick, A / Cross to choose, B / Circle back, LB / RB to
  change settings tab). Tap View for the map, hold it for the perk ability; the LB wheel picks
  weapons.
- **Switching**: the controls follow whatever you used last, keyboard and mouse, touch or a
  gamepad, and the on-screen prompts change with them ("[F]", "(Y)", "(Car)"). Settings > Controls >
  Control scheme fixes one (Auto / Keyboard / Touch / Gamepad).
- **Light mode** (on by itself on phones): 67% 3D resolution, no shadows, a shorter streaming
  radius, less traffic and fewer people. Settings > Display can turn it on or off for any device and
  set the 3D resolution by hand.
## Rebuilding the data
The tools run with **Blender 5.3** and its bundled Python (no other installs needed).

| What | Command |
|---|---|
| Download map + elevation data | `powershell -ExecutionPolicy Bypass -File tools\fetch_map_data.ps1` |
| Build the city tiles, road graph, places, minimap | `"<Blender>\5.3\python\bin\python.exe" -I tools\build_osm_city.py` |
| Audit the built tiles (buildings on roads, floating or sunk props) | `"<Blender>\5.3\python\bin\python.exe" -I tools\audit_city.py --strict` |
| Synthesise all sound effects and music | `"<Blender>\5.3\python\bin\python.exe" -I tools\make_audio.py` |
| Vehicle models | `"<Blender>\blender.exe" -b blender\monrovia_city.blend -P tools\export_district.py` |
| Default controls into project.godot | `Godot_console.exe --headless --path . --script res://proto3d/game/write_input_map.gd` |

`<Blender>` is `C:\Program Files\Blender Foundation\Blender 5.3`. The area built is set by
`BUILD_BBOX` at the top of `tools/build_osm_city.py` (widen it to add Congo Town and beyond).
Game places (Auntie Musu, shops, taxi destinations) are in `proto3d/game/data/places_src.json`,
missions in `missions.json`, shop menus in `shops.json`.

## Tests
`powershell -ExecutionPolicy Bypass -File tools\check.ps1` runs sixteen checks: Godot import, start-up,
the 2D game, the 3D district, the city streaming, a play-through of every game system (economy,
save, settings, input, audio, HUD, clock, traffic and traffic lights, cars, weapons and drive-bys,
shops, taxi, missions, police, arrest, hospital) and the physics (vehicle tuning, tyres, crash
damage, props, ragdolls, climbing, swimming) the Big Talk storyline, the weapons, skills/perks/street life, the leg animation, driving (every vehicle laps a test ground), the playtest build (title screen, tutorial, pause menu, bug report) the browser build (tiles streamed over HTTP, export preset, browser shaders) and devices (phone/tablet detection, touch controls, gamepad menus, control switching, light mode) and accounts (sign-in, tokens, play sessions, kicks, cloud saves and offline play, against a fake server: no network). It fails on any error or warning.
`tests/world_audit.gd` sweeps the city for physics/road/prop/people problems; `tests/perf_presets.gd` measures FPS per quality preset; `tests/capture_game.gd` takes screenshots.

## Project layout
- `proto3d/main_city.tscn`, `main_city.gd` — the game; `proto3d/game/` — one script per system
  (game state, clock, road graph, traffic, traffic lights, police, weapons, effects, shops, taxi,
  missions, save, settings, input, audio, HUD).
- `proto3d/world_streamer.gd` — streams the city tiles; `proto3d/city/` — generated city data.
- `proto3d/` — player, cars, camera, characters; `proto3d/audio/` — synthesised sounds and music.
- `tools/` — data and asset generators; `tests/` — automated checks and screenshot captures.
- `web/` — the browser build's HTML shell and offline cache (`sw.js`).

## Credits
See `CREDITS.md`. Map data © OpenStreetMap contributors (ODbL); the generated city tiles are a
derived database under the ODbL. People: Quaternius' CC0 Ultimate Animated Character Pack. All
other art, sound and music are original and generated by this project's tools.
