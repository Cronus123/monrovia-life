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
- **Weapons:** fists, a pistol and body armour from the weapon shops.
- **Missions:** Auntie Musu's 5-mission story, starting at Waterside (yellow M).
- **Big Talk Dweh:** Honourable Kpakolo "Big Talk" Dweh, an original fictional loudmouth who goes
  from shouting on a crate at Waterside to a radio show, a campaign (convoy, rallies, rice and
  T-shirts), a walled house off 16th Street in Sinkor and a final election-night choice: expose his
  stolen road fund, or help make him "Senator Dweh". His own jobs, lines and grudges; all data-driven
  (`proto3d/game/data/bigtalk.json`). He and his "Big Talk Progress Party" are made up.
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
3. Open `project.godot` in Godot and run `proto3d/main_city.tscn` (F6), or export the
   **Windows 3D City** preset (`build/windows-city/MonroviaCity.exe`).

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
| Map | M | Back |
| Pause (save, settings, quit) | Esc | Start |

**Settings** (from the start and pause menus): volumes for master, music, sound effects and
ambience; resolution, fullscreen, V-sync; graphics quality (Low, Medium, High); mouse/stick
sensitivity, invert Y, field of view; key bindings.

## Rebuilding the data
The tools run with **Blender 5.3** and its bundled Python (no other installs needed).

| What | Command |
|---|---|
| Download map + elevation data | `powershell -ExecutionPolicy Bypass -File tools\fetch_map_data.ps1` |
| Build the city tiles, road graph, places, minimap | `"<Blender>\5.3\python\bin\python.exe" -I tools\build_osm_city.py` |
| Synthesise all sound effects and music | `"<Blender>\5.3\python\bin\python.exe" -I tools\make_audio.py` |
| Vehicle models | `"<Blender>\blender.exe" -b blender\monrovia_city.blend -P tools\export_district.py` |
| Default controls into project.godot | `Godot_console.exe --headless --path . --script res://proto3d/game/write_input_map.gd` |

`<Blender>` is `C:\Program Files\Blender Foundation\Blender 5.3`. The area built is set by
`BUILD_BBOX` at the top of `tools/build_osm_city.py` (widen it to add Congo Town and beyond).
Game places (Auntie Musu, shops, taxi destinations) are in `proto3d/game/data/places_src.json`,
missions in `missions.json`, shop menus in `shops.json`.

## Tests
`powershell -ExecutionPolicy Bypass -File tools\check.ps1` runs eight checks: Godot import, start-up,
the 2D game, the 3D district, the city streaming, a play-through of every game system (economy,
save, settings, input, audio, HUD, clock, traffic and traffic lights, cars, weapons and drive-bys,
shops, taxi, missions, police, arrest, hospital) and the physics (vehicle tuning, tyres, crash
damage, props, ragdolls, climbing, swimming) and the Big Talk storyline. It fails on any error or warning.
`tests/perf_presets.gd` measures FPS per quality preset; `tests/capture_game.gd` takes screenshots.

## Project layout
- `proto3d/main_city.tscn`, `main_city.gd` — the game; `proto3d/game/` — one script per system
  (game state, clock, road graph, traffic, traffic lights, police, weapons, effects, shops, taxi,
  missions, save, settings, input, audio, HUD).
- `proto3d/world_streamer.gd` — streams the city tiles; `proto3d/city/` — generated city data.
- `proto3d/` — player, cars, camera, characters; `proto3d/audio/` — synthesised sounds and music.
- `tools/` — data and asset generators; `tests/` — automated checks and screenshot captures.

## Credits
See `CREDITS.md`. Map data © OpenStreetMap contributors (ODbL); the generated city tiles are a
derived database under the ODbL. People: Quaternius' CC0 Ultimate Animated Character Pack. All
other art, sound and music are original and generated by this project's tools.
