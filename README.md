# Monrovia Life: Streets (Godot 4, 2D)

An original top-down open-world crime-action game set on a stylized map of Monrovia, Liberia. It's a LibGamer community game, and all of its characters are fictional.

## Open and play
1. Install **Godot 4.3 or newer** (the standard version, not .NET) from https://godotengine.org/download.
2. In the Godot Project Manager, click **Import**, choose this folder's `project.godot`, and then click **Run** (F5).

## Art made in Blender
The vehicles and people are low-poly models that `tools/make_sprites.py` builds in Blender and renders as top-down sprites into `sprites/`. To change them or render them again:

```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b -P tools\make_sprites.py
```

Then switch back to Godot, and it re-imports the new PNGs. If the `sprites/` folder is missing, the game falls back to its built-in drawn shapes.

## Controls
| Action | Key |
|---|---|
| Walk / drive | WASD or arrow keys (hold Shift to run) |
| Aim / shoot or punch | Mouse / left click |
| Get in, take or leave a car | F |
| Use shops, talk, take missions | E |
| Taxi hire light (in a taxi or keke) | T |
| Switch weapon | Q, 1, 2 |
| Handbrake | Space |
| Map | M |
| Pause / save | Esc |

## What's in it
- **The map:** Mamba Point, Downtown and Broad Street, Waterside, Providence Island, Capitol Hill, Bushrod Island, Sinkor, Congo Town, Gardnersville, ELWA Junction, Paynesville and Red Light, with landmarks.
- **Cars:** take any car from traffic. That includes kekes, taxis, SUVs, trucks, sports cars and police cars.
- **Police:** a wanted level of 1 to 5 stars. Police cars chase you and officers get out on foot, and at higher levels they shoot. You can lose them by staying out of sight or by using a respray shop. If they catch you, you're **ARRESTED**. If your health runs out, you're **DOWN AND OUT** and wake up at JFK.
- **Weapons and gear:** fists, a pistol and body armor (from the weapon shops). Cash drops are scattered around.
- **Missions:** a 5-mission story for Auntie Musu, who stands at Waterside (yellow M).
- **Side jobs and daily life:** taxi fares, cookshops that restore your health, and a safehouse in Sinkor where you save your game.
- **World:** day and night with headlights and street lamps, rain, a minimap and a full map.

## Put it online at a subdomain (for example play.libgamer.com)
1. In Godot, open **Project → Export**. Godot asks you to download its export templates the first time; accept.
2. Pick the **Web** preset (it's already set up with thread support off, so it works on any static host) and click **Export Project**. The files go to `build/web/`.
3. Upload the `build/web` folder to a static host. Cloudflare Pages and Netlify both have free plans, and you can drag and drop the folder.
4. In the host's dashboard, add the custom domain `play.libgamer.com`. Then, at your domain registrar's DNS settings, add the **CNAME** record the host gives you (for example `play` → `your-project.pages.dev`).
5. HTTPS turns on automatically after DNS updates, which usually takes a few minutes to an hour.
