# Parcels in Transit (Godot)

A Godot 4.7 port of the Three.js / WebView game in `../tidyup`. It is a first-person old-town explorer: the town is buried in parcels, and you carry them to the depot.

## Running it

- **Editor:** open this folder in `D:\godot\Godot_v4.7.2-stable_win64.exe` and press F5.
- **Directly:** `D:\godot\Godot_v4.7.2-stable_win64.exe --path D:\projects\tidyup-godot`
- **Smoke test** (headless; picks up a parcel and stores it in the depot):
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --smoke`
- **Screenshots** of the test views (street, church, depot, night, pond, ducks, truck, castle, rooms and more); add `--only living_room,castle_near` to pick some:
  `Godot_v4.7.2-stable_win64_console.exe --path . -- --shot <folder>`
- **Drive test** (gets in the truck, drives, steers, brakes, gets out, saves a screenshot):
  `Godot_v4.7.2-stable_win64_console.exe --path . -- --drive <folder>`
- **Stairs test** (opens a front door, walks in and up to the landing):
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --stairs`
- **Gust test** (starts a gust, checks every loose parcel lands somewhere new): `... --path . -- --gust <folder>`
- **Moat test** (walks out over the drawbridge and back, raises it): `... --headless --path . -- --moat`
- **Save test** (plays a little and saves to a separate test file, then loads it back and reports): `... --headless --path . -- --savetest write`, then `... -- --savetest read`

## Saving and scoring

The game saves where you left off to `user://save.json` (on Windows `%APPDATA%\Godot\app_userdata\Parcels in Transit\`): your position, the time of day and weather, score, backpack, every parcel's position, what's in the depot, and the truck and its cargo. It saves every 30 seconds, when you pause, when you switch away and when you quit, and picks up there the next time you start. The pause menu shows your progress (time played, parcels in the depot and picked up, distances, gusts, doorbells) and has a New game button.

You score 50 points for every parcel filed in the depot (carried in, or unloaded from the truck), and 50 for the first ring at each house's doorbell. Picking up and putting down parcels scores nothing, and filed parcels stay in the depot.

## Android build (phones)

The Android export preset builds an arm64 APK, landscape and full screen. Building it needs the Godot 4.7.2 export templates, the Android SDK and a JDK (set under Editor Settings > Export > Android).

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-debug "Android" export/ParcelsInTransit.apk
adb install -r export/ParcelsInTransit.apk
```

On a phone the game shows touch controls: a joystick under your left thumb (push past the rim to sprint), drag on the right side to look, and Use / Jump / Crouch / Light / Drop buttons. II or the back button pauses. Phones get lighter graphics, like the web version's Low preset. Run the desktop build with `-- --mobile` to try the phone layout.

## Controls

| Action | Key |
|---|---|
| Move / look | WASD or arrow keys, mouse |
| Sprint / jump / crouch | Shift / Space / C |
| Interact, pick up, store in the depot, open doors | E or Enter |
| Drop a parcel | G |
| Flashlight | F |
| Skip time / weather | N / B |
| Map / sound | M / K |
| Menu | Esc |
| Truck: drive / brake / horn / camera / wipers / get out | WASD / Space / Q / V / R / E |

## How it is built

The town is generated in code, as in the web version. The textures are the web game's own: `tools/export_textures.py` runs `../tidyup/js/textures.js` (and the old-town files that extend it) in headless Chrome and saves every texture to `assets/textures/` as PNGs, with bump maps converted to normal maps. Run it again whenever the web textures change:

```
python tools/export_textures.py
```

Then open the project once (or run `--import`) so Godot re-imports them. The `_nrm` files must keep `compress/normal_map=1` in their `.import` files.

| File | Ported from | What it does |
|---|---|---|
| `scripts/main.gd` | game.js | Game manager: backpack, depot, score, day/night, lamp light pool |
| `scripts/world.gd` | world.js, oldtown.js, gothic.js, warehouse.js, citywall.js, townsquares.js | Builds the town: streets, house lots, church, depot, wall and Nordtor, park, ponds, trees, mountains |
| `scripts/houses.gd` | houses.js, oldtown.js, gothic.js | The houses: shells with windows, doors, stairs, furnished rooms, garages and workshops, roofs, timber frames and Gothic fronts. The unchanging parts are built once and stamped into each house |
| `scripts/castle.gd` | castle.js | The castle crag, walls, towers, gatehouse, keep, Palas, banner, track and slope forest |
| `scripts/truck.gd` | truck.js | The drivable delivery truck |
| `scripts/moat.gd` | moat.js | The moat, drawbridge and bridgehead |
| `scripts/lights.gd` | (new) | Church tower floodlights and the park's carnival festoons |
| `scripts/ducks.gd`, `scripts/birds.gd` | ducks.js, birds.js | Mallards on the ponds; bird flocks and hawks |
| `scripts/batch.gd` | `batchStatic()` | Merges static geometry into one mesh per material and chunk; also polygons, prisms, arch frames and any mesh, with optional vertex colours |
| `scripts/trees.gd` | buildTree, randomCard, _buildWillowTree, buildMountains | Card trees (lindens, deciduous, blossom, pines, willows) merged into a few meshes, swaying in the wind; the far mountain forest |
| `scripts/parcels.gd` | hoard.js, warehouse.js | The parcel piles (one MultiMesh per size), stacking, dropping, automatic depot storage |
| `scripts/player.gd` | player.js | CharacterBody3D with step-up for kerbs, head bob, footsteps, flashlight, interaction scan |
| `scripts/sky_cycle.gd` + `shaders/sky.gdshader` | sky.js | 20-minute day, keyframed sky colours, sun and moon, stars, clouds, weather |
| `scripts/sfx.gd` | audio.js | Sound effects synthesised into WAVs at start-up, the soundtrack, birds by day and crickets at night |
| `scripts/hud.gd`, `scripts/minimap.gd` | index.html, game.js | HUD, minimap, start and pause menu |
| `shaders/textured*.gdshader` | textures.js materials | The exported textures at the web version's tile sizes, plus its world-space ground and stone tints |
| `shaders/*.gdshader` (others) | sky.js, world.js | Sky, water, swaying foliage, mountains, parcels |

## Port status

Done in the first iteration:

- Same street grid, lot layout, house numbers and residents (doorbells work).
- Half-timbered houses and Gothic stepped-gable houses, with garages, driveways and garden walls.
- St. Marien, the six small squares, the Stadtpark, both ponds, linden avenues and street lanterns.
- The city wall with towers and the Nordtor. Its gates are shut for now.
- The Parcel Depot, with the full parcel loop: about 1,000 parcels, a 10-parcel backpack, automatic filing, dropping and stacking.
- Day/night cycle, weather, mountains, forest, minimap and music.
- Enterable houses: front doors that open, stairs to the upper floor, furnished rooms, room lights, see-through windows that glow at night, garages with four kinds of open workshop.
- The drivable delivery truck (load the backpack at the back, unload in the depot).
- The castle on its crag, with the track up from the north gate.
- Ducks on the ponds, bird flocks and hawks, and the moon's full surface.
- Wind gusts that scatter the loose parcels across town.
- The moat, the drawbridge (lever in the Nordtor passage) and the bridgehead you can walk out to.
- Night lighting beyond the web version: the floodlit castle, the church tower, and carnival lights in the Stadtpark.

Still to port:

- [ ] Market stalls, fountain coin toss, church bells and clock
- [ ] Pier and benches at the ponds; chimney smoke, playground, park flower beds and fountain plaza
- [ ] Billboard clouds (the Godot sky draws its own clouds for now)
- [ ] Basketball hoops, mailboxes
- [ ] Graphics settings menu (phones use fixed Low-style settings for now)
