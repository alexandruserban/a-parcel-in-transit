# Parcel Run (Godot)

A Godot 4.7 port of the Three.js / WebView game in `../tidyup`. It is a first-person old-town explorer: the town is buried in parcels, and you carry them to the depot.

## Running it

- **Editor:** open this folder in `D:\godot\Godot_v4.7.2-stable_win64.exe` and press F5.
- **Directly:** `D:\godot\Godot_v4.7.2-stable_win64.exe --path D:\projects\tidyup-godot`
- **Smoke test** (headless; picks up a parcel and stores it in the depot):
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --smoke`
- **Screenshots** of five views (street, church, depot, sunset, night):
  `Godot_v4.7.2-stable_win64_console.exe --path . -- --shot <folder>`

## Controls

| Action | Key |
|---|---|
| Move / look | WASD or arrow keys, mouse |
| Sprint / jump / crouch | Shift / Space / C |
| Interact, pick up, store in the depot | E or Enter |
| Drop a parcel | G |
| Flashlight | F |
| Skip time / weather | N / B |
| Map / sound | M / K |
| Menu | Esc |

## How it is built

Everything is generated in code, as in the web version. There are no models or textures.

| File | Ported from | What it does |
|---|---|---|
| `scripts/main.gd` | game.js | Game manager: backpack, depot, score, day/night, lamp light pool |
| `scripts/world.gd` | world.js, oldtown.js, gothic.js, warehouse.js, citywall.js, townsquares.js | Builds the town: streets, 50 houses, church, depot, wall and Nordtor, park, ponds, trees, mountains |
| `scripts/batch.gd` | `batchStatic()` | Merges static boxes, quads and cylinders into one mesh per material and 96 m chunk |
| `scripts/parcels.gd` | hoard.js, warehouse.js | The parcel piles (one MultiMesh per size), stacking, dropping, automatic depot storage |
| `scripts/player.gd` | player.js | CharacterBody3D with step-up for kerbs, head bob, footsteps, flashlight, interaction scan |
| `scripts/sky_cycle.gd` + `shaders/sky.gdshader` | sky.js | 20-minute day, keyframed sky colours, sun and moon, stars, clouds, weather |
| `scripts/sfx.gd` | audio.js | Sound effects synthesised into WAVs at start-up, the soundtrack, birds by day and crickets at night |
| `scripts/hud.gd`, `scripts/minimap.gd` | index.html, game.js | HUD, minimap, start and pause menu |
| `shaders/*.gdshader` | textures.js | Procedural cobbles, slabs, plaster and ashlar, roof tiles, grass, water, foliage, mountains, cardboard |

## Port status

Done in the first iteration:

- Same street grid, lot layout, house numbers and residents (doorbells work).
- Half-timbered houses and Gothic stepped-gable houses, with garages, driveways and garden walls.
- St. Marien, the six small squares, the Stadtpark, both ponds, linden avenues and street lanterns.
- The city wall with towers and the Nordtor. Its gates are shut for now.
- The Parcel Depot, with the full parcel loop: about 1,000 parcels, a 10-parcel backpack, automatic filing, dropping and stacking.
- Day/night cycle, weather, mountains, forest, minimap and music.

Still to port:

- [ ] House interiors (enterable houses, doors, stairs, furniture, room lights)
- [ ] Delivery truck
- [ ] Wind gusts that scatter parcels
- [ ] Moat, drawbridge and bridgehead; the castle on its crag
- [ ] Market stalls, fountain coin toss, church bells and clock
- [ ] Ducks, birds, chimney smoke, playground, park benches, pier
- [ ] Basketball hoops, mailboxes, garage workshops
- [ ] Graphics settings menu, touch controls, Android export
