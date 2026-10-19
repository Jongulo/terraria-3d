# Terraria 3D

A first-person, voxel 3D take on Terraria built with Godot 4.7 and a Rust voxel core,
using the original game's art, sounds, music and fonts extracted from **your own**
Terraria install. No Terraria assets are stored in this repository.

## Setup

Requirements: Godot 4.7, Rust (cargo), ffmpeg, python3, and Terraria installed through Steam.

```sh
./extract_assets.sh            # or: ./extract_assets.sh /path/to/Terraria
./build.sh                     # builds rust/voxel_core and installs game/bin/libvoxel_core.so
godot --path game              # play
```

`extract_assets.sh` converts the XNB/XACT content into `game/assets/terraria/`:
PNG textures (LZX and DXT decoding, alpha un-premultiplied), WAV sound effects, OGG music
(MS-ADPCM wave bank via ffmpeg, named by sound bank cue), Terraria's bitmap fonts, and
`ids.json` with item/NPC/tile/projectile IDs and English names read from `Terraria.exe`'s
.NET metadata and embedded localization.

### Keep Terraria's assets out of git

Two folders hold Terraria-derived files and must never be committed: `game/assets/terraria/`
(the extracted assets) and `game/data/tuned/` (tuned models cached whole, coloured from the
sprites; their patches in `game/data/tuned_patches/` are what's committed). `.gitignore` covers
both. Check it before committing, after extracting, and whenever `.gitignore` changes:

```sh
for p in game/assets/terraria game/data/tuned; do
  git check-ignore -q "$p/x" && echo "ignored: $p" || echo "NOT IGNORED: $p (fix .gitignore before committing)"
done
git ls-files game/assets/terraria game/data/tuned | grep . && echo "TRACKED: untrack these (git rm -r --cached)" || echo "nothing from them is tracked"
```

Both should print `ignored:`, then `nothing from them is tracked`. (`.gitignore` doesn't stop git
tracking files it already tracks, hence the second check.)

## Controls

Defaults below; every action except Escape can be rebound under **Settings → Controls**
(title screen or pause menu). Bindings follow physical key positions, so WASD stays in
place on any keyboard layout, and the menu shows your layout's labels. Settings also has
mouse sensitivity, invert Y, field of view, view distance, far view, **UI scale (50–200%)** and volumes.

Better Grass (like OptiFine's, Fancy): a grass block's side shows the grass top when the block
beside it, one step down, is the same grass, so grassy hillsides are green all the way down their
steps. Sides over a bigger drop keep Terraria's dirt with a grass fringe. This works for every grass
(forest, jungle, Corruption, Crimson, ash).

Far terrain (level of detail): past the view distance the world goes on, drawn coarser the farther
it is, out to the **Far view** distance (Options; 32 chunks by default, off at 0). It comes in rings:
2-block cells to twice the view distance, then 4-block cells to four times it, then 8-block cells
beyond, as a quadtree so the rings meet without overlaps or holes, and a ring stays until what
replaces it has loaded, so nothing blinks out as you move. Far terrain is meshed from the world in
each block's average colour (grass tops green, dirt sides brown; grass sides green, to match Better
Grass below), with water surfaces, lit by the
world's light (dark at night, caves left out), and the haze starts at the full-detail edge so it
fades into the distance.

Trees and placeables have levels of detail too. Canopies within 64 blocks are drawn with their
chosen method; farther ones as a single sprite facing you, out to the edge of the far view. Trees
past the full-detail chunks (whose trunk blocks aren't drawn) get a trunk sprite from the bottom of
the trunk up to the canopy (leaning to a palm's), so a far forest is Terraria's trees, not bare
canopies. Placeables more than 2 chunks away with a heavy 3D method (hull, hull top, lathe, Claude, extruded,
flat) are drawn as their crossed sprite, and switch back as you walk up. On a 1024-block world, view distance 6 with
far view 48 ran at about 210 FPS where view distance 12 alone ran at 15 (a quarter of the chunks and
draw calls), while seeing four times as far.

| Key | Action |
| --- | --- |
| WASD / Space | Move / jump (hold for higher jumps) |
| Mouse / LMB | Look / use held item (mine, chop, attack, shoot, place, drink). Like Terraria, tools, buckets and blocks keep going while held; weapons and potions take a click each (Settings: Autofire makes everything keep going) |
| RMB | Talk to town NPCs; open chests, barrels, dressers and trash cans; open and close doors; set your spawn at a bed; check a clock; write on a sign |
| 1-0, mouse wheel | Select hotbar slot |
| Tab | Inventory and crafting (click to move stacks, right-click takes one, shift-click quick-moves; right-click armor or an accessory to put it on) |
| H | Quick heal |
| T | Throw held item |
| F12 | Screenshot without the HUD (saved to `~/.local/share/godot/app_userdata/Terraria 3D/screenshots/`) |
| Shift (hold) | Drop through platforms |
| Esc | Pause menu (resume, game mode, settings, save, save & exit) |
| Space twice (creative) | Start / stop flying (Space up, Shift down) |
| MMB (creative) | Pick block: the targeted block into the hotbar |

### Creative mode

Movement follows Terraria's own code (`Player.Update`, `HorizontalMovement`, `JumpMovement`),
converted at 1 px/tick = 2.5 blocks/s, since a tile is 2/3 of a block.

- **Running:** you reach 7.5 blocks/s in about 0.6 s. When you let go, you slow by 30 blocks/s
  every second on the ground, half that in the air.
- **Boots:** Hermes, Flurry and Dunerider Boots keep speeding up on the ground, slowly, to 15 blocks/s.
- **Jumping:** a jump keeps its upward speed while you hold jump, for 15 ticks. A full jump goes
  about 4.1 blocks (6 tiles); a tap goes lower.
  - Shiny Red Balloon: 7.2 blocks.
  - Cloud in a Bottle: a double jump of 0.75 of a full jump.
  - Blizzard in a Bottle: a double jump of 1.5.
- **Gravity:** 60 blocks/s², with a top falling speed of 25 blocks/s.
- **Fall damage:** 10 for each tile fallen beyond 25 (16.7 blocks).
- **Water and lava:** halve how far you move, with half gravity and a slow sink (12.5 blocks/s).
  Like Terraria, you can't swim: you sink to the bottom and jump only off it (about 2.9 blocks,
  Terraria's 4.3 tiles) or with a double jump you haven't used yet. Getting out of deep water means
  climbing out where it's shallow. Terraria's Flippers, which let you swim, aren't in yet.
- **Ice and cobwebs:** use Terraria's multipliers.

Creative mode works like Minecraft's. You pick **Game mode: Creative** when creating a world,
or switch any time with the pause menu's game mode button. The mode is saved with the world.

- **No damage:** hits, falls, drowning and lava do nothing, and life and mana are hidden.
- **Flying:** double-tap jump to fly, and touch the ground to land.
- **Breaking:** blocks break in one hit (even altars), and nothing drops.
- **Nothing used up:** placed blocks, ammo, potions, mana and buckets stay.
- **Starting out:** a creative world starts empty-handed.
- **Inventory (Tab):** shows every item under the hotbar, in tabs (Blocks, Tools, Weapons,
  Accessories, Armor, Consumables, Materials) with a search box. The full inventory has its own tab.
  - Click takes a full stack.
  - Right-click takes one.
  - Shift+click puts a stack straight into the inventory.
  - Clicking the palette with something held deletes it.

## Test world

**Create Test World** on the title screen builds a flat sandbox for trying everything:

- **North:** chests holding every item (full stacks, sorted by category); crafting stations at spawn.
- **East:** an enemy arena walled 5 blocks high (above a zombie's best jump), entered through a
  wooden door, with a spawner per enemy type
  and the Eye of Cthulhu.
  Right-click a spawner to spawn one; Shift+right-click toggles auto-spawning (up to 3 alive).
- **Southeast of spawn:** two target dummies that never die and show your DPS.
- **West:** a 6-deep water pool with a natural waterfall, hammer-spring tanks (water already
  flowing, lava ready to hammer), a fenced lava pit and obsidian.
- **Above the plaza:** two floating islands (fly up with F3): a house island with a Skyware chest
  and a lake island, both in the Space layer.
- **South-west / south-east:** a small Corruption and Crimson patch, with Shadow Orbs and
  Crimson Hearts to smash.
- **North-west / north / north-east:** a small Snow, Desert and Jungle patch.
- **South-east, down the shaft past the tower:** a mud cavern with the Glowing Mushroom biome grown
  in it (mushroom grass, giant and small glowing mushrooms, vines; its music and enemies).
- **North of the trees:** the forest's plants and debris: a meadow with one of each, a sunflower
  patch, a pond with lily pads and cattails, and a grassy ledge with vines under it.
- **East of the forest garden:** a furnished wooden house (door, table with a candle, chair, bed,
  clock, barrel, chandelier, sawmill and loom). The dark room has cobwebs in its corners.
- **North of the house:** a library (bookcases, piano, a dresser with a candelabra, a trash can, a
  silver chandelier) with a lamp post outside. Tiki torches and a sign with a message stand by
  the house door.
- **East of the house:** hammered blocks: half blocks, a ramp staircase, an arch with
  upside-down ramps and two grass ramps.
- **Far west:** the Dungeon's entrance (blue brick), its door facing spawn, with the Old Man, and a
  small Dungeon under it (a quarter of the generator's layout steps).
- **South-west of spawn:** a staircase of wooden platforms up to a floating platform floor.
- **South:** one of every block, an ore wall labelled with required pickaxe power, a 25-block
  staircase tower with a water landing pool for fall tests, and a sealed dark room.

You start with top-tier gear, max life and mana. Hotkeys: **F1** help, **F2** god mode, **F3** fly
(Space up, Shift down), **F4** day/night, **F5** remove enemies, **F6** clear dropped items,
**F7** natural spawns (off by default), **F8** heal. Enemies spawned here don't flee at daytime.

### The same test world in Terraria

`tools/terraria_test_world.py` builds a Terraria world laid out like the test world, for
comparing the two side by side. It starts from a fresh Journey-mode world made by Terraria's own
dedicated server, so its biomes, Dungeon, floating islands and cabins are real. It then flattens a
forest strip at spawn and builds every section in a row, west to east:

- garden
- house, library, hammered blocks
- liquid lab, dark room
- chests holding every item in `items.json`, the crafting plaza at spawn
- dummies
- arena: wired statues on switches stand in for the spawners; statue enemies drop nothing
- town, with its six NPCs housed
- fall-test tower, platforms
- block gallery, with the ore wall in its top row

Journey's enemy strength is set to Normal (1×), and Journey powers stand in for the debug keys.

```sh
cd ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Terraria
./TerrariaServer.bin.x86_64 -config server.txt   # autocreate=1, difficulty=3, seed=3003, world=...;
                                                 # stop it once it says "Server started"
python3 -I tools/terraria_test_world.py template.wld ~/.var/app/com.valvesoftware.Steam/.local/share/Terraria/Worlds/3D_Compare.wld "3D Compare"
```

`tools/terraria_wld.py` reads and writes Terraria 1.4.5 world files (version 326). The world can be
checked by loading it with the dedicated server and having it save; nothing should change.

## Placeables

**Styles:** Terraria draws one plant tile in several frames (tall grass in 6, flowers in 38, vines
in 26...). Here each frame is its own block (`flowers_2` ... `flowers_38`, marked `variant_of` in
blocks.json), so the placeable picker gives each its own model; the plants, vines, rocks, twigs,
lily pads, cattails, cobwebs, icicles, stalactites, pots, dungeon books and glowing mushrooms all
have theirs. Worldgen places the plain block, then as its last step turns each into a random one
of its styles (the same every time for its spot); everything else treats a style as its block
(drops, sounds, being replaced when you build). A world saved before this gets its plants' styles
the first time it's loaded.

Besides the blocks, stations and chests, Terraria's furniture and decor (built from its item and
tile data, each with Terraria's recipe):
- **Furniture in every wood** (wood, Boreal, Palm, Rich Mahogany, Ebonwood, Shadewood, Ash,
  Cactus): tables, chairs, work benches (they all work as a work bench), beds, pianos, dressers
  (storage), sofas and benches, bathtubs, bookcases, sinks, and the lights: candles, candelabras,
  chandeliers, lamps, lanterns. Tables and chairs count for housing; lights light rooms.
- **Blocks:** red, obsidian, hellstone, iridescent, demonite, crimtane, snow, ice, sandstone,
  ebonstone and crimstone bricks, mudstone, smooth sandstone, and the seven glowing Gemspark blocks.
- **Lights:** blue, red, green, purple, white, yellow, orange, ice and demon torches (on the
  ground or a wall, each its colour), heart, skull and Chinese lanterns, campfire, fireplace.
- **Platforms:** stone, glass, bone, skyware, frozen, cloud, snow and the dungeon bricks'.
- **Decor:** keg, clay pot, bowls, mug, wine glass, pink vase, banners, picnic tables, bar,
  banquet table, bar stool, chimney, dungeon and obsidian sinks.

Wood variants share their wooden piece's 3D method and settings in the picker below. Every sink and
bathtub has a hand-made ("Claude") model of its own: a basin you can see into, the faucet against
the back, the cabinet or pedestal under it; tubs hollow, with their taps, lips, hoops and feet.

Animated placeables move like Terraria's animated tiles, with its frame counts and speeds
(Main.AnimateTiles): the Furnace's fire (12 frames), the Campfire's flames (8), the Sawmill's blade
(2), the Extractinator's hopper (10) and the Life Crystal's shimmer (10). Every frame gets its own model in whatever 3D method the
block uses (hull, extruded, Claude...), and all of a kind animate together, as in Terraria. The
placeable picker's previews animate too, every method side by side. A block
animates once blocks.json gives it an "anim" (frames, how far down its sheet each frame is, and
ticks per frame).

Torch effects, like Terraria's: torches, candles, candelabras, chandeliers, lamps and lanterns have
a flickering flame. Terraria draws each one's flame sheet (Flame_N) over it 7 times at random
offsets that change every tick, added on; here that is a glowing quad round the flame, facing you,
with each kind's own settings (the Ebonwood set's softer flicker, the Cactus Lamp's 3 copies; no
flame for the lanterns Terraria draws none for). Torches puff embers of their own colour (their
dust) 1 tick in 40, which drift up and fade, or a third of them fall. A torch in your hand flickers
the same way (Terraria's held-item flame) and puffs embers too. The Demon Torch's light pulses like
Terraria's, from red-pink to violet and back every 3.3 seconds (its light relights the world as it
changes level), held or placed.

Block dust, as in Terraria.
- **Which dust:** hitting a block throws 3 specks of its own dust and breaking it throws 10:
  - green flecks from grass and plants, brown from dirt and wood, grey from stone
  - pottery shards from pots, sand grains from sand, web from cobwebs
  - each torch colour its own flame
- **Where it comes from:** Terraria's own choice of dust for each tile,
  `WorldGen.KillTile_MakeTileDust` (for walls, `KillWall_MakeWallDust`).
  - `tools/terraria_dust.py` runs those methods in an IL interpreter for every block, frame
    by frame, and writes `assets/terraria/tile_dust.json`. `extract_assets.sh` runs it.
  - Like Terraria, tables, chairs, doors, beds, pianos, dressers, bookcases, bathtubs,
    candles, chandeliers, lamps, banners and the Extractinator make no dust.
- **How it moves:** the specks come from `Images/Dust` and move by Terraria's rules
  (`Dust.NewDust` / `UpdateDust`), in its pixels and ticks.
  - They fly off at up to 2 px/tick, fall at 0.1 px/tick², slow down and shrink until they
    vanish in about a second and a half.
  - Flame dusts drift upward and glow; the rest take the light where they are.

Enemies gib as in Terraria. Each one's gores and blood come from Terraria's own `NPC.HitEffect`:
`tools/terraria_gore.py` runs it for every enemy in an IL interpreter and writes
`assets/terraria/npc_gore.json`, and `extract_assets.sh` runs it.
- **Gores:** when it dies, an enemy breaks into its pieces.
  - A zombie gives its head, two arms and two legs; a Demon Eye splits in half; a skeleton
    gives bones.
  - Town NPCs, sharks, vultures and the rest come apart too.
  - The pieces start where they were on its body and are flung with its own speed (knockback
    included), plus Terraria's random kick.
  - They fall, spin, land and slide to rest, then after 10 s fade away over 4 more
    (`Gore.Update`).
- **Blood:** a hit sprays blood dust in proportion to the damage, and a death sprays 50.
  - Slimes and jellyfish leave no gore, only their own slime dust in their colour.
  - Eaters of Souls and Hornets bleed their own colours; skeletons throw bone dust.

Enemy knockback works as in Terraria (`NPC.StrikeNPC_Inner`), in its own pixels and ticks.
- **The push:** the weapon's knockback is multiplied by the enemy's own knockback resistance
  (Terraria's `knockBackResist` for every enemy, read from Terraria.exe). It eases off above 8,
  caps at 16, and a crit multiplies it by 1.4.
- **Strong and weak hits:** a hit doing more than a tenth of the enemy's life adds that speed
  away from you, and three-quarters of it upward (half for flyers). A weaker hit sets those
  speeds, with the resistance counting twice.
- **How far it flies:** that comes from each enemy's own movement, taken from Terraria's AI code:
  - Zombies and other walkers keep their speed in the air and slide to a stop on the ground
    (×0.8 a tick).
  - Slimes slow ×0.93 a tick in the air and ×0.8 on the ground.
  - Demon Eyes and bats brake by their own steering; bats barely brake, so they fly furthest.
  - Eaters of Souls, Crimeras, Hornets and Servants home back in at their own rate.
  - Gravity is Terraria's NPC gravity (0.3 px/tick², 45 blocks/s²).
- **Checked:** at knockback 5 and 8, a test measures how far each kind flies back in 3D against a
  transcription of Terraria's tick-by-tick rules.

  | Enemy | Knockback 5 | Knockback 8 |
  |---|---|---|
  | Zombie | 1.7 blocks | 4.1 |
  | Blue Slime | 2.4 | 4.2 |
  | Demon Eye | 1.1 | 5.4 |
  | Eater of Souls | 3.2 | 8.3 |
  | Cave Bat | 6.6 | 9.1 |
- **Jumps:** with Terraria's gravity, the jumps are Terraria's too.
  - Slimes hop 6 px/tick up, 2 forward; every third hop is a big one at 8 and 3.
  - Zombies jump 5–8 px/tick by how tall the wall ahead is.

Falling leaves and wind, like Terraria's. The wind wanders the way Terraria's does (calm spells,
breezes, gales; light until you have 120 max life), blowing along x. Trees near you drop their own
leaves (forest, jungle, Corruption, Crimson, palm, gem, Sakura and Willow; snowy pines and ash trees
none) as often as Terraria's do for the wind: one in a few minutes per tree in still air, every
few seconds in a gale; leafy branches a third as often, Hallow trees twice, and hardly at all where
the wind doesn't reach. Living-tree leaf blocks drop them too. A leaf sways from side to side as it
sinks, tumbling through its frames and blown along by the wind; it drifts through tree trunks,
slides down walls, lands or floats, and fades after ten seconds.

## Placeable picker

```sh
./placeable_picker.sh
```

Chooses how each placeable sprite block (chest, work bench, furnace, anvil, torch, pots, life
crystal, tall grass) and every tree canopy is turned into 3D. Canopies are not blocks: all 81
are listed (each of Terraria's 27 Tree_Tops sheets has 3 trees), named for their art ("Canopy:
Corruption (Tree_Tops_1) 2"), each with its own method, settings, transform and sculpted model,
so the gem trees, palms or snowy pines can each be drawn their own way. (Files saved before this
kept one set of choices for every canopy: each canopy starts with a copy of it.) Models bigger
than a block are shown scaled down to fit the row. A Terraria player stands at the row's left end for scale (shrunk
along with a scaled-down model), on the game's grass. The selected block is shown in all eleven
methods side by side; click one or press 1-9, 0 or -, then Ctrl+S (saves `game/data/placeables.json`,
read by the game):

| # | Method | What it does |
| --- | --- | --- |
| 1 | Panels | The sprite on the four sides of the block (default for furniture) |
| 2 | Cross | Two crossed planes (default for plants and torches) |
| 3 | Billboard | A flat sprite that always faces you |
| 4 | Flat | The sprite extruded one voxel thick |
| 5 | Extruded | The sprite pushed through the whole block, like a cookie cutter |
| 6 | Hull | Voxels carved from the sprite seen from the front and the side |
| 7 | Hull Top | Voxels carved from the sprite seen from the front and from above/below: as deep as the sprite is tall (its top row at the back), so tall sprites reach past their block |
| 8 | Lathe | The right half of the outline spun around the vertical axis |
| 9 | Claude | A voxel model made by hand for the block (Sawmill, Bench, Bookcase, Piano, sinks, bathtubs, Extractinator, Sharpening Station) |
| 0 | Tuned | A voxel model you sculpted in the [model sculptor](#model-sculptor); blocks not tuned yet can't pick it |
| - | Rendered | Its model shot from every angle and drawn as a sprite again (see below) |

**Rendered** works as it does for NPCs (see the [NPC picker](#npc-picker)), but straight on only, the
way Doom's sprites are: the block's model is shot from 16 directions round it at eye level, every
frame of an animated block too, and each shot is shrunk to the art's pixels. In the world each
rendered block is an upright sprite that turns round its vertical to face you, showing the shot
for the direction you see it from, turned the way the block was placed (a chest put down facing
east shows its east side), and lit like the other block models (seen from above it's still the side
view, foreshortened); until its shots are made (and in headless runs) it's drawn as its
billboard. "Shots taken of" in the settings panel picks the model: **Auto** (its tuned model, else
Claude's, else its hull) or **Extruded** (the Extruded model with its own settings). The block's
offset, rotation and scale are in the shots, and changing the model or the transform takes them
again. Shots are cached in `user://rendered_npcs/` as `block-<name>_...`.

**One colour per voxel:** every voxel method (Extruded, Hull, Hull Top, Lathe, Claude, Tuned) has
this setting in the settings panel (or press O). Each voxel then shows one colour on all its faces:
its front face's where that shows, otherwise its most visible face's. Without it, a voxel's faces
can differ, like a hull's tops taking the colour from just inside the outline. Doors always keep
this rule (they're drawn on their own, not through the picker): the door art pushed through, every
voxel one colour.

**Remove outline:** the methods that work the sprite out by themselves (Extruded, Hull, Hull Top,
Lathe) can cut away its dark outline first (the settings panel, or press L): each pixel on the
silhouette's edge that's clearly darker than the pixels just inside it goes, so the model has no
black rim and is a pixel smaller each side. **Add outline**, under Rendered (or Shift+L), draws a
dark one-pixel outline round every shot instead, as Terraria's sprites have: the outline of the
view you see, from any angle, not the sprite's. The two go together: cut the outline away from the
model, then have the rendered shots put it back.

**Claude's hand-made models** live in `game/data/handmade_models.json`, built at the sprite's
art resolution (one voxel per pixel of the original art).
- **Parts:** each part covers a rectangle of the sprite, sets which depths its pixels have voxels
  at, and can take a fill colour from one of the sprite's pixels for its hidden sides. A part can
  also be limited to pixels of one colour, as for the gaps between books or the drawer knobs.
- **Examples:** the sawmill has a tabletop, four legs, a shelf with aprons, a thin saw blade
  through the table, a plank stack and a sawdust pile. The bench has a seat, a backrest along its
  back edge and four legs.
- **Bookcase:** the books sit back inside the frame, with the gaps between them deeper still, and
  the drawers and their knobs stick out.
- **Piano:** an upright cabinet with a sheet-music stand. The keyboard juts out, so you see its
  keys from above, and it has front legs and pedals.
- **Extractinator:**
  - The ribbed hopper sits on a deep machine base.
  - A feed pipe runs from it to the exhaust stack.
  - The right-hand housing has its vents and window set into it.
  - Each part can carry a per-frame `shift`, so the hopper bobs down into the housing with the
    animation, as in the sprite.
- **Sharpening Station:** a grindstone disc on a metal axle, held between front and back wooden
  legs with diagonal braces on a base board, and the blade being sharpened lying against the
  stone.
- **Front view:** each pixel's front-most voxel keeps that pixel's colour, so seen straight on the
  model is exactly the sprite (placeables_test checks every pixel).
- **Side noise:** Claude models have the same side noise, strength and seed settings as Hull and
  Lathe (pick "Claude" under "Settings for", or press 9 and then N). The noise goes on every face
  but the front-facing ones, so the front view stays the sprite.
- **Other blocks:** Method 9 says "Not made yet" and can't be picked.
- **Defaults:** the Bench, Bookcase and Piano start with this method; the Sawmill keeps what you
  picked.

**Hull and Lathe noise:** the same noise, strength and seed settings exist for Hull and Hull Top (applied
to its sides, top and bottom, keeping the front/back art clean) and Lathe (its whole surface;
*grain* becomes horizontal rings like thrown pottery). The settings panel's "Settings for" switch
picks which method you're editing and follows the method you choose; depth and bevel are
Extruded-only. `N` / `Shift+N` act on whichever method the panel shows.

**Transform:** the panel under the settings moves, turns and scales the block's model, whatever
its method:
- **Offset:** X/Y/Z in the sprite's art pixels.
- **Rotation:** X/Y/Z in degrees, about the bottom centre of the block, before the block's own facing.
- **Scale:** a percentage.

Billboards take the offset and scale only, since they always face you. A transformed panels or
cross block is drawn as a block model in game, because the chunk mesher can't move it.
"Reset transform" clears it.

Voxel sizes come from each sprite's own resolution: Terraria art is drawn at 2x (every visible
pixel is 2x2 texture pixels), so the scale is detected per sprite and voxel models, side noise,
bevel steps and extrusion depth all work in those art pixels (held items too, one art pixel
thick). Depth and bevel size are measured in art voxels; older `placeables.json` files are
converted on load.

Directional methods face the player when placed (saved with the world). PageUp/PageDown
switch blocks, Space spins a turntable, Q/E turn the models, MMB orbits, wheel zooms. The
search box above the list (Ctrl+F) keeps only the placeables whose name or block name holds the
text; PageUp/PageDown then step through the matches and Enter shows the first. **Copy**, **Paste**
and **Paste to styles** (Ctrl+C, Ctrl+V, Ctrl+Shift+V) copy one placeable's method, the settings
of every method and its transform onto another (or onto all styles of its kind); a Claude or
Tuned choice is only pasted where that model exists.

**Extruded settings** (right panel, per block, saved with the methods): **depth** in voxels, from
1 up to a full block; **side noise** for the voxel cells along the sides - *none*, *speckle*
(random light/dark cells), *grain* (wavy wood-like bands along the depth) or *palette* (cells
take random colours from the sprite's interior); **strength** and **seed**; **bevel** for the
front and back edges, in voxel steps by distance from the outline - *chamfer* (45 degree slope),
*round* (convex), *cove* (concave) or *step* (a ledge around a raised panel) - with a **bevel
size** of 1-6 voxels, and **bevel sides**: tick which edges of the silhouette (*top*, *bottom*,
*left*, *right*) and which faces (*front*, *back*) get the bevel. For example, untick *bottom*
to keep a chest square where it sits on the floor, or *back* to keep a wall-hung model flat
against the wall. The boxes are greyed out while the bevel is *none*. Shortcuts: `[` / `]` depth, `N` next noise mode, `Shift+N` new seed,
`B` / `Shift+B` next / previous bevel. Sides take their colour from just inside the
sprite's dark outline.

## Sprite editor

```sh
./sprite_editor.sh
```

Chooses how the tree canopy, tree trunk and cactus sprites are made from Terraria's art, with a live
preview (the cactus shows sample cacti as its styles, and a row of them on sand in the scene view), and saves `game/data/sprite_fx.json` (read by the game at start-up; missing settings use
the built-in defaults). For each sprite:

- **Upscale:** none, or a pixel-art magnifier at 2x or 4x: Scale2x (EPX), Eagle or EPB. All three
  match ImageMagick's magnify methods and only reuse the sprite's own colours.
- **Warp:** amount and feature size (in art pixels, so they look the same at any upscale), seed,
  and for the canopy a fade that keeps the trunk stub in place. The trunk's warp repeats
  vertically so stacked trunk blocks still line up.
- **Noise:** speckle, palette shades (one step lighter/darker on the sprite's own colours),
  hue + value, or blotches; strength, patch size (1/2/4 px) and seed.

Views: `1` the sprite, `2` before / after, `3` trees (canopies on trunks at in-game proportions).
For the canopy, "Tree tops" (or Left/Right) picks which of Terraria's 15 tree-top sheets to look at
(forest, Corruption, Crimson, snow and jungle looks; Style picks its frame), or "All tree tops" to
see every one side by side, with their branches (which take the canopy's settings, without
the warp); the settings apply to all of them.
PageUp/PageDown switch sprite, wheel zooms, middle-drag pans, `F` resets the view, Ctrl+S saves.

## NPC scale editor

```sh
./npc_scale_editor.sh
```

Chooses how big each enemy, boss and town NPC appears in the game, and saves
`game/data/npc_scales.json` (read at start-up; NPCs not in it keep their npcs.json size).

- **The list:** every NPC, with a search box; scaled ones show their scale.
- **The preview:** the NPC exactly as the game draws it, animated, on a grid of blocks next to you
  (1.8 m) and one block, with its hitbox as a yellow wire box. Drag to orbit, wheel to zoom, F to
  frame it, Space to pause its animation, PageUp/PageDown for the next NPC.
- **Scale:** a slider, a number box and presets (0.5x to 2x; anything from 0.25x to 4x). "Hitbox
  scales too" (on by default) makes it get hit, and touch you, where it now looks; off, only the
  sprite changes. Reset, Revert to saved, Save (Ctrl+S).
- **Pixel size:** "Match player pixels" scales the NPC so one pixel of its sprite is as big as one of
  the player's (everything on one pixel grid, like Terraria's); "Match all NPCs" does that for every
  NPC (Revert to saved undoes it). The panel shows each NPC's pixel size next to the player's.

## NPC picker

```sh
./npc_picker.sh
```

The placeable picker's sister app, for enemies, bosses and town NPCs. It chooses how each one is
turned into 3D, and saves `game/data/npc_models.json`, which the game reads. NPCs that aren't in
the file stay billboards.

- **The list:** every NPC, with its icon. Filter by All / Enemies / Bosses / Town NPCs, or search.
  NPCs with a 3D method show it next to their name.
- **The row:** the selected NPC in all ten methods side by side, walking or flapping through its
  frames, on grass next to a Terraria player for scale. Big ones (bosses) are shrunk to fit, the
  player with them. The methods are Billboard (always faces you, as before), Cross (two crossed
  planes), Flat (1 voxel thick), Extruded (the sprite pushed through), Hull (front and side
  silhouettes), Hull Top (front and top silhouettes: as deep as the sprite is tall), Lathe (the outline spun round; sprites drawn on their side, like the Demon Eye,
  spin round the way they point), Claude (a model made by hand; NPCs without one show their hull),
  Tuned (sculpted by you) and Rendered (its model shot from every angle, drawn as a sprite).
- **Choosing:** click a model or press 1-9 and 0. The gold square and label mark the chosen one.
- **Settings (right):** pixel noise, strength and seed for Extruded, Hull, Hull Top, Lathe, Claude and Tuned. Extruded also
  has depth (default half the sprite's width), bevel and bevel sides. The panel follows the chosen
  method. "Settings for" switches it.
- **Keys:** PageUp/PageDown (or Up/Down) for the next NPC, Space turntable, Q/E turn, P pause the
  animation, `[` `]` depth, N noise mode, Shift+N seed, B bevel, MMB orbit, Shift+MMB pan, wheel
  zoom, Ctrl+S save, F1 help.

In the game, a 3D NPC turns to face where it's walking (toward you when it stands still). Fliers
that tilt with their flight (the Demon Eye, the Eater of Souls) point their art along it. Hit
flashes, slime colours and lighting work as they do on billboards. Each frame's mesh is built the
first time it's shown, then kept.

**Claude's hand-made NPC models** live in `game/data/handmade_npc_models.json` and are built by
`NPCSculpt` from a few shapes, for every frame of the sprite, so they animate with it. So far there's
the **Eye of Cthulhu**, both phases:

- **Front and back:** a ball wearing the sprite, projected straight through it. From the front it is
  the sprite pixel for pixel, from the back its mirror. The open mouth of the second phase is a gap
  right through, as in the sprite. The ball is fitted to each frame (the mouth frames sit lower).
- **Sides:** a band round each side takes the sprite's columns folded in, so the veins carry on with
  no seams.
- **Tendrils:** where the sprite has them seen from the front, fanning out in depth the higher they
  rise, so they spread round the ball.
- **Below:** the faces looking down are painted, so the iris is round. In the second phase, the
  inside of the mouth rows is filled behind the sprite (unseen from the front), leaving an oval mouth
  ringed with teeth.
- **In the game:** a 3D Eye turns rather than snapping, at Terraria's own rates: it turns to watch
  you while it hovers (1.2 radians a second, 3 in the second phase), faces along each charge as it
  starts and holds that for 40 ticks, then turns back toward you (3, or 4.8 in the second phase).
  It spins with its transformation. Its frames are built on worker threads when it
  appears, so the second phase doesn't stall the game.

**King Slime** has a Claude model too: a solid slime spun from each frame's outline (every row of
the sprite becomes an ellipse round its middle, so the body squashes and stretches with the hop),
coloured from the sprite as the Eye is (front exact, the sides folded, its highlight in rings on
top). It's see-through (0.8 opaque, Terraria's own is 0.88), so the ninja inside shows; the ninja and
the crown stay billboards. Only the body's surface is kept (the mesher knows the rest is solid), so
it builds quickly.

Claude's models ignore the sprite's **outline**: the dark pixels round the silhouette take the
colour just inside them before the model is built, so there are no black voxels on it (a spec can
say `"outline": "keep"`).

The ninth method, **Tuned**, shows a model you sculpted in the [model sculptor](#model-sculptor)
(NPCs not tuned yet show their hull).

The tenth, **Rendered** (key 0), draws the NPC as a sprite again, the way Fallout 1 did: its voxel
model is shot from every angle (32 round it, every 11.25 degrees, at each of 13 heights, every 15
degrees from straight below to straight above) for every frame, and each shot is shrunk to the sprite's own pixel size. The shrinking keeps
it crisp pixel art: each shot is lined up so the model's voxels land on whole pixels (straight on,
its pixels are the art's), and each pixel takes the colour covering most of it, opaque only if
mostly covered, so colours never blur together. "Shots taken of" (the Rendered section at the
bottom of the settings panel) picks the model: **Auto** (tuned, else Claude's, else the hull) or
**Extruded** (the Extruded model with its own depth, bevel and noise). In the game it shows the shot
that matches how you see it, turned in the screen plane to line up, and lit like any sprite. The
shots are made off screen the first time the NPC appears (about five seconds for the Eye), kept in
`user://rendered_npcs/`, and made again when its model changes. Every voxel method has the **one colour per voxel** setting
(O), and Extruded, Hull, Hull Top and Lathe have **remove outline** (L), with **add outline** for the
rendered shots (Shift+L), as in the placeable picker.

## Model sculptor

```sh
./model_sculptor.sh
```

Hand-tunes voxel models for the Tuned method of both pickers, for NPCs and placeables alike.

- **Saved as patches:** each model is kept in `game/data/tuned_patches/` as what it started from
  (the method and its settings) and the voxels changed since, so the repo holds your edits but none
  of Terraria's art. It's rebuilt from the sprite on any machine with the extracted assets, then the
  edits are applied (a fingerprint warns if the start comes out different). The whole model is
  cached in `game/data/tuned/`, outside git, so the game loads it at once.

- **Starting:** pick an NPC or placeable on the left, choose what to start from (Flat, Extruded,
  Hull, Hull Top, Lathe, Claude, or Blank) and press Start. It copies that method's model as you
  set it up in the picker, every frame of it, each voxel face keeping its colour. The inside is
  filled, so cutting into it never opens a hollow. "Start over" replaces the model (press twice),
  and Delete removes it.
- **Tools (left click):** A Add (onto the face you point at; drag to lay one layer), X Remove,
  P Paint (F: just the face you point at), I Eyedropper (or Ctrl+click anywhere). `[` `]` brush
  size, M mirror across the middle. Adding past the grid's edge grows it.
- **Smart paint (C):** each voxel under the brush copies the look of a voxel sampled from the
  surface round it (not under the brush), nearer ones likelier, so painting over a blemish fills it
  with the texture around it. Shift+`[` `]` sets how far past the brush it looks. With F it copies
  just the face you point at. Over a frame range each voxel gets the same pick on every frame
  (sampled from the frame shown), so nothing flickers in the animation.
- **Texture (T):** paints noise from the model's own colours: each voxel takes one of the colours
  used in the model that are near the current colour, nearer ones likelier. The Texture range
  slider sets how near (the panel shows how many colours that gives). Each voxel keeps its colour
  for the whole stroke, on every frame edited, and mirrored voxels match. With F it textures just
  the face you point at.
- **Frame range:** tick Frames (L) and set From and To: every edit then changes those frames. A
  range can wrap past the last frame (5 to 2 is 5, 6, 1, 2). Unticked, edits change only the frame
  shown.
- **Colours:** a colour picker, plus every colour in the sprite as swatches.
- **Frames:** `,` `.` step through them, Space plays them. R shows the sprite beside the model.
- **Camera, as in Blender:** MMB (or Alt+LMB) orbits, Shift+MMB pans, the wheel or Ctrl+MMB zooms.
  Numpad 1 is the front (the sprite's view), 3 the right side, 7 the top, and with Ctrl the
  opposite sides. 9 flips to the opposite view, 5 toggles orthographic, 2 4 6 8 orbit in 15-degree
  steps, and `.` or Home frames the model. Snapping to a view goes orthographic, and orbiting away
  from it goes back to perspective. The number row works like the numpad.
- **Editing:** Ctrl+Z and Ctrl+Shift+Z (or Ctrl+Y) undo and redo, Ctrl+S saves every changed
  model, and PageUp/PageDown move to the next model. Closing with unsaved changes asks first.

## Weapon pose editor

```sh
./viewmodel_editor.sh
```

Positions held items in first person with Blender-style controls and saves to
`game/data/viewmodel.json`, which the game loads (missing entries use built-in defaults).
Poses are per item kind (sword, pickaxe, axe, shortsword, gun, bow, staff, small item), with
optional per-item overrides; the hand position and the swing axis/angle are editable too.

| Key | Action |
| --- | --- |
| G / R / S | Grab / rotate / scale (Tab: switch target between item grip and hand) |
| X / Y / Z | Constrain to camera axis; press again for the item's local axis, again to clear |
| Numbers | Exact value while transforming, e.g. `R X 90 Enter`, `G Z -0.1 Enter`; `-` flips sign |
| Ctrl / Shift | Snap (5 mm, 5°, 0.05) / precision |
| LMB, Enter / RMB, Esc | Confirm / cancel |
| Alt+G / Alt+R / Alt+S | Reset position / rotation / scale |
| Ctrl+Z, Ctrl+Shift+Z, Ctrl+S | Undo, redo, save |
| Space (Shift: slow) | Preview the item's use animation |
| MMB, Shift+MMB, wheel | Orbit, pan, zoom |
| Numpad 0 or \` / 1 3 7 / 5 / . | Camera view / front, right, top / ortho / frame item |
| PageUp / PageDown, T, N, F1 | Previous/next item, item list, sidebar, help |

## Layout

```
tools/xnb-extract/    Rust: XNB (LZX, Texture2D, SoundEffect, ReLogic fonts) + XWB/XSB extractor
tools/terraria_ids.py ID constants and English names from Terraria.exe
tools/terraria_recipes.py  Terraria's crafting recipes, read from Terraria.exe's code
tools/contact_sheet.py  labeled sprite crops, for picking tile frame coordinates
tools/terraria_wld.py  Terraria world files (.wld) reader/writer
tools/terraria_test_world.py  the test world's layout built into a real Terraria world
tools/terraria_dust.py  each block's dust, read from Terraria's KillTile_MakeTileDust
tools/terraria_gore.py  each enemy's gores and blood, read from Terraria's NPC.HitEffect
rust/voxel_core/      Rust GDExtension: world storage, Terraria-style flood-fill lighting,
                      world generation, meshing (smooth light + AO), raycasts, AABB physics, saves
game/data/            blocks.json, items.json (metal tiers expand into tools/weapons/armor),
                      npcs.json, loot.json
game/scripts/         GDScript gameplay: game.gd (session), player/, entities/, ui/hud.gd, world/
game/shaders/         voxel, cutout, billboard sprite, canopy and highlight shaders
game/tests/           render_test (screenshots) and game_test (scripted end-to-end session)
```

## Tests

```sh
./run_tests.sh              # Rust + headless Godot suites (no windows)
./run_tests.sh --visual     # plus screenshot tests (opens a window briefly; closes itself)
```

Individually:

```sh
cd rust/voxel_core && cargo test --release             # lighting, meshing, physics, worldgen, saves
cd game && godot --audio-driver Dummy --path . res://tests/game_test.tscn -- /tmp/shots
cd game && godot --audio-driver Dummy --path . res://tests/render_test.tscn -- /tmp/shots
cd game && godot --audio-driver Dummy --path . res://tests/menu_test.tscn -- /tmp/shots
cd game && godot --audio-driver Dummy --path . res://tests/editor_test.tscn -- /tmp/shots
cd game && godot --audio-driver Dummy --path . res://tests/viewmodel_test.tscn -- /tmp/shots
```

`game_test` plays a scripted session: digging and pickups, building, crafting, killing a
slime, chests, summoning and beating the Eye of Cthulhu, night spawns, and a save/reload
round trip. It exits non-zero on failure.

## Status (milestone 1 vertical slice)

Done: asset pipeline; Small / Medium / Large island worlds (surface, underground, caverns, underworld; caves;
paired ores; trees with Terraria canopies (upscaled 4x with Scale2x and gently warped at load,
the warp fading out at the trunk stub; each world picks its tree tops like Terraria: the forest
is split across the world's width into 2 / 3 / 4 zones (Small / Medium / Large) with their own
leaves out of Terraria's six forest styles, and the snow and jungle get one look each: round
snowy trees, green or snowy pines, or bare branches; the usual or the bushier jungle leaves;
branches grown by Terraria's rules, 1 in 10 per trunk cell on either side, leafy 2 in 3 and
matching the tree top, else a bare stub: fixed cards sticking out of the trunk, so they don't
swing round as you pass); gem trees in the caves, like Terraria 1.4.5's: every stone floor underground
gets a 1 in 5 try at one of the seven (topaz, amethyst, sapphire, emerald, ruby, diamond, amber),
7-12 tall with room for its top and clear of waterfalls, its gem-studded trunk, top and branches
from Terraria; chopped, each trunk cell drops its gem 1 time in 10, else stone (the gems are
materials, so the Amethyst Staff and the other gem recipes work); canopies are lit by the light
where they stand, so a gem tree is as dark as its cave until you bring light; vanity trees in the
forest, like Terraria's: 1 in 20 trees on grass grows as a Yellow Willow or a Sakura instead; and
the Underworld's ash forests: in its outer ring, ash open to the air turns to ash grass, ash trees
grow on it (they drop Ash Wood: block, door, platform, armor and Terraria's recipes), and the
Underworld glows a pulsing orange as Terraria's does (open tiles below its top), so you can see
them; giant living trees, Terraria's GrowLivingTree in 3D: groves of 2-4 in the
forest (0-2 groves on a Small world), each a round Living Wood trunk 4-5 wide that narrows as it
puts out branches on alternate sides, branches ending in clusters of Leaf Blocks, a crown of big
leaf balls, roots spreading through the ground, and in the first tree of each grove a doorway, a
stair down through the roots and a Living Wood room with a chest; leaf blocks let the sun
through like Terraria's, so it's light under the trees; mahogany trees in the underground jungle, like
Terraria's: on its caves' jungle grass, 5-15 tall where there's room, with the underground
jungle's own trunk, vine-hung top and branches (they drop Rich Mahogany); and Living Mahogany
trees, Terraria's MahoganyTreeBiome: 6-11 per Small world in the underground jungle, each
filling a tall cavern (hollowed out where the caves aren't tall enough): a hollow, swaying trunk
6 across with an Ivy Chest at its foot (Terraria's jungle loot: Feral Claws, Anklet of the Wind,
Staff of Regrowth or Boomstick, now and then a Fiberglass Fishing Pole or Flower Boots), branches angled up from alternate sides and two at the
top ending in blotchy balls of mahogany leaves, and four big roots out and down; underground
cabins, Terraria's CaveHouse builder (about 95 in a 1024 x 1024 world: its 35-40 per small
world for each 640 x 640 blocks), each built in a cave below the surface and away from chests:
a main room on the ground (Terraria's smallest, 15 x 8 tiles: 10 x 10 x 6 blocks), sometimes a
room stacked above and below fitted to the cave (up to 20 x 20 x 7), sunk 2 blocks into the
ground. Its kind follows the ground round it, as in Terraria: Wood in dirt and stone, Ice in the
snow, Desert in the underground desert, Jungle in the mud, Mushroom in the Glowing Mushroom biome.
A frame (Wood, Boreal Wood, Sandstone, Rich Mahogany or Mushroom Blocks) with its wall (Planked,
Boreal Wood, Sandstone, Rich Mahogany or Mushroom Wall) lining the
walls and an outer layer of the frame, platform stairs between stacked rooms up through a hatch,
doors where there's open cave outside, platform hatches in the roof and floor where it's open
beyond, beams down to the ground (Wooden, Boreal, Rich Mahogany, Mushroom Beams, Sandstone Columns), unlit
chandeliers (copper, silver, gold, tin, tungsten or platinum; break and replace one to light
it), furniture against the walls in the kind's style (table, anvil, work bench, loom, piano, keg,
bookcase), and the kind's chest. Then each room ages its own way: the wooden cabin gets
cobwebs, walls gone to dirt in patches and holes in the frame; the Ice cabin's frame goes mostly
to ice (some snow), icicles hang from the ceiling and the walls go to snow in patches; the Desert
cabin gets a little hardened sand, sandstone stalactites and patches of hardened sand wall; the
Jungle cabin's frame goes mostly to jungle grass (some mud), jungle vines hang from the ceiling
and the walls go to jungle mud in patches; the Mushroom cabin's frame goes to mushroom grass in
patches, glowing mushrooms grow on its floor and roof, and its wall is gone in places. Chests: a
Gold Chest or Rich Mahogany Chest
(underground chest loot); a Frozen Chest (Ice Boomerang, Ice Blade, Ice Skates, Snowball
Cannon, Blizzard in a Bottle, Flurry Boots or Glacier Fang, now and then an Extractinator); a
Sandstone Chest (Ancient Chisel, Dunerider Boots, Snake Charmer's Flute or Magic Conch; in the
deeper desert the Storm Spear, Thunder Zapper or Bast Statue); a Mushroom Chest (a Gold Chest's
loot, and half the time the Mushroom Hat, Vest and Pants: Terraria's other half, a Shroom
Minecart, waits for minecarts). The first desert cabins also get
an Extractinator and a Bast Statue (3 in the world at most), the first jungle cabins a Sharpening
Station. Terraria's Granite and Marble cabins wait for their biomes, and cabins have
none of Terraria's paintings, statues or rubble piles yet; Enchanted Sword Shrines, Terraria's
EnchantedSwordBiome with its 2D shapes spun round into 3D (1-2 tries per small world for each 640 x
640 blocks, each half the time, as in Terraria), 50 to 99 blocks under the surface in the outer
part of the map, in ground that's mostly dirt and stone with no sand above: a slime-shaped cave
(Terraria's radius 20, 0.8 to 1.3 as wide, its lower half squashed) lined with grass, a dirt mound
14 high in it with grass plants and the sword in stone on top, pools of water round the mound,
flower vines hanging from the ceiling (Terraria hangs one 3-5 long from every ceiling tile, a single
row seen side on; spread over a 3D ceiling that's a grid of them, so here they grow in clumps, 1 to
7 long, with bare ceiling between), and a shaft from the cave up through the surface. Terraria
digs that shaft only 1 time in 3 and stops it 10 tiles under the surface; here every shrine has
one, open to the sky, so you can find it: its top 8 blocks widen to a round mouth 5 across, with a
wall torch on each side just under the ground (they glow from afar at night). Mine the sword in stone with a pickaxe for
the Enchanted Sword, or 1 time in 30 the Terragrim. Terraria's Flower Walls aren't drawn (there
are no background walls); pots, life crystals, loot chests); colored torch
lighting (sunlight reaches open ground fully, but ground you dig out keeps Terraria's
"background wall": sunlight only seeps in from the opening and fades a level per block, so a
shaft goes dark about a dozen blocks down; chasms and pits the world was made with stay lit);
day/night with a Terraria-style sky (see Sky below); mining with pickaxe power, axes felling trees (Terraria's numbers: a pickaxe hit does its power,
blocks have 50% (dirt, sand, mud...) to 200% (ebonstone, hellstone, dungeon brick) hit points, grass
takes one hit more as it turns to dirt; an axe chop does axe power x 0.24 to a tree tile's 100, so the
Copper Axe needs 13 chops at 21 ticks each; tool speeds per tier are Terraria's);
building; inventory, accessories, chests, crafting at stations; melee, bows, guns, magic,
throwing (Terraria's tile cutting: anything swung that does damage, tools too, cuts the grass,
flowers, plants, vines, cobwebs, herbs and pots in its swing that no wall hides, and your
arrows, bullets, bolts, shurikens, boomerangs, yoyos and spears cut what they pass through;
not plants in a clay pot, and not sunflowers, rocks or life crystals); Slimes, Zombies, Demon Eyes, Cave Bats, Skeletons; the Eye of Cthulhu with both
phases and Servants; the Eater of Worlds; King Slime; context music and SFX; save/load with autosave.

King Slime: Terraria's (AI_015_KingSlime), summoned any time with a Slime Crown (20 Gel and a Gold
or Platinum Crown at a Demon Altar; the crowns are 5 bars and a Ruby at an anvil).
- **Body:** 2000 life, 40 damage, 10 defense; knockback doesn't move it. Its crown and the ninja
  inside are drawn as Terraria draws them, the ninja lagging its bounces.
- **Hopping:** it hops at you in a cycle (8 px/tick up, 8, 6, then a big 13), winding up between
  hops, faster as it's hurt. It's 1.25x its size at full life, shrinking to 0.75x.
- **Teleporting:** when it can't reach you for 5 seconds (no line of sight, or more than 160 px
  above or below you) it shrinks away in a puff of slime and grows back beside you. If you die or
  get 3000 px away, it leaves.
- **Slimes:** each 5% of its life lost, 1-3 Blue Slimes pop out of it.
- **Loot:** the Solidifier (a crafting station), one Ninja armor piece (2 / 4 / 3 defense, 3% crit
  each; the set gives 20% movement speed), 5-15 Lesser Healing Potions, 1 gold, and 1 in 7 its
  mask.
- **Not in yet:** its other drops (Slimy Saddle, Slime Hook, Slime Gun, Slime Staff: mounts,
  hooks and minions aren't in yet) and its natural spawning (surface, outer thirds, slime rain).

The Eater of Worlds: Terraria's worm boss (AI_006_Worms), summoned with Worm Food (30 Vile Powder
and 15 Rotten Chunks at a Demon Altar; it only works in the Corruption) or by smashing a third
Shadow Orb.
- **Body:** a head, 65 body segments and a tail, 150 life each (10,050 in all, on one boss bar),
  damage 22 / 13 / 11 and defense 2 / 4 / 8. Knockback doesn't move it.
- **Movement:** it comes up out of the ground below you and steers at you through the ground at
  Terraria's 10 px a tick, accelerating 0.07 px/tick² on each axis. In the open it falls and
  drifts. The segments trail 38 px apart, the ground crumbling and rumbling as it digs.
- **Splitting:** kill a middle segment and it splits in two. The segment behind becomes a new head,
  the one ahead a tail; a head or tail left on its own dies.
- **Leaving:** leave the Corruption (or die) and it digs straight down and is gone.
- **Loot:** each segment has a 1 in 2 chance of 1-2 Shadow Scales and of 2-5 Demonite Ore, plus
  8 silver. The last one killed drops 20-60 more Demonite Ore and, 1 in 20, an Eater's Bone (its
  pet isn't in yet).
- **What the scales make:** Shadow Scales make the Shadow armor (6 / 7 / 6 defense, 5% crit each;
  the set makes you quicker to speed up and stop, and 15% faster), the Nightmare Pickaxe (now its
  real recipe) and The Breaker (a 55% hammer).

World sizes: chosen under "World size" when creating a world. They keep Terraria's
Small : Medium : Large proportions (4200 : 6400 : 8400 tiles wide). Terraria's real sizes can't
be used: a 3D Small world at Terraria's scale would need about 105 GB of memory. The layers
(cavern, underworld, space) are shares of the height, as in Terraria.

| Size | Blocks | Memory | Making it |
| --- | --- | --- | --- |
| Small | 768 × 384 × 768 | ~1.1 GB | ~10 s |
| Medium | 1152 × 576 × 1152 | ~3.8 GB | ~25 s |
| Large | 1536 × 768 × 1536 | ~9 GB | ~1 min |

Older 512 × 256 × 512 worlds still load.

Ocean: every new world is an island. The land slopes through a sand beach into a sea that runs
round every edge, deepening toward the world's edge (no caves under it). Past the edge, open
water reaches the horizon. Palm trees line the beach, grown like Terraria's (10-20 tall on
sand, each trunk segment stepping 2 px further along a lean of up to 16 px from a quarter of
the way up, Tree_Tops_15 leaves on the end), leaning out to sea; chopped, they drop Palm Wood
(blocks, door, platform, armor and any-wood recipes, all Terraria's). On the coast the ocean biome plays Terraria's Ocean music, the
depth readout says "Ocean", and its enemies spawn:
- Crabs on the beach.
- Pink Jellyfish, which drift in pulses and glow when you're close.
- Sharks, which chase you while you swim and drop Shark Fins.

Biomes: besides the forest, every new world gets Terraria's Snow, Desert and Jungle. The Snow and
the Jungle lie on opposite sides of spawn and the Desert between them, each with its own blocks,
music (surface and underground) and enemies:

| Biome | Surface | Underground | Enemies |
| --- | --- | --- | --- |
| Snow | Snow-covered ground, boreal trees with snowy pine tops | Snow and slippery ice, narrowing into the caverns | Ice Slimes, Zombie Eskimos at night; Ice Bats and Spiked Ice Slimes below |
| Desert | Deep sand with cacti | Hardened sand and sandstone | Antlions buried in the sand throwing sand at you, Vultures; Walking Antlions below |
| Jungle | Mud and jungle grass under dense mahogany trees with Terraria's big jungle canopies, jungle plants and glowing Jungle Spores | Mud all the way down to the Underworld, with jungle grass in its caves | Jungle Slimes and Snatchers (jaws on a vine); Jungle Bats, Hornets that shoot stingers, Man Eaters and Piranhas below |

**The Glowing Mushroom biome**, Terraria's Mushroom Patches pass in 3D (rust `mushroom.rs`):

- **Where:** Terraria's maxTilesX / 700 biomes (6 in a small world) for each 640 x 640 blocks of the
  map, fewer as the patches grow with the world, 180 blocks apart, in the cavern layer (Terraria's
  50 tiles below it to 300 above the world's bottom), away from the Jungle, the snow, the deserts,
  the Dungeon and the ocean. No lava in them.
- **Shape:** each is six of Terraria's ShroomPatches, one at its spot and five within 40 tiles: a
  chain of 20-25 flattened balls of mud (2.3 times as wide as tall, about 80-100 tiles across),
  their middles hollowed out above, drifting a block sideways and half a block up each step, with
  blobs of mud just below.
- **Grass:** then, as in Terraria, every mud block below the surface open to the air turns to
  mushroom grass (so the mud patches through the caverns get some too; not the Jungle's mud), the
  ground round it is smoothed, and some mud inside the ground turns to mushroom grass too.
- **Mushrooms:** on every mushroom grass block open above, a Giant Glowing Mushroom where Terraria's
  GrowShroom fits one (grass on all four sides, 13 blocks clear above; a stem 4-10 tall under its
  cap, Terraria's Shroom_Tops, a canopy style in the placeable picker), else a small Glowing
  Mushroom; mushroom vines hang under some of its ceilings.
- **It glows:** mushroom grass, the mushrooms, their stems, vines and Mushroom Blocks light up blue
  (Terraria's 0, 0.3, 1).
- **Drops (Terraria's):** mushroom grass gives mud; small and giant glowing mushrooms 1 in 40
  Mushroom Grass Seeds, else half the time a Glowing Mushroom; vines half the time a Glowing
  Mushroom; Mushroom Blocks a Glowing Mushroom. A Glowing Mushroom places a Mushroom Block;
  Mushroom Grass Seeds turn mud into mushroom grass.
- **Music and enemies:** its own music ("Mushrooms"). Before Hardmode its enemies are Terraria's:
  Spore Skeletons and Spore Bats in place of the cavern's Skeletons and bats (a Spore Bat drops the
  Shroomerang 1 in 40). Its Hardmode enemies (Anomura Fungus, Fungi Bulb, Mushi Ladybug, Fungo
  Fish) and the Truffle wait for Hardmode.
- **Mushroom cabins:** see the underground cabins.

- **Cacti:** drawn like Terraria's, one flat sprite facing you (a trunk with arms, put together from
  Tiles_80's pieces; Corruption and Crimson ones in their colours), walk-through. Each is a column
  of cells you aim at, chop (axes do 3x) or mine; any cell brings the whole cactus down, a Cactus
  per piece, arms included. Its arms come from its height and position.
- **Crafting:** cactus makes a Cactus Sword and Cactus Pickaxe. Boreal Wood and Rich Mahogany are
  placeable and count as wood in every wood recipe (Terraria's "Any Wood").
- **Test world:** a small patch of each biome to the north.

Forest plants and debris: the forest floor gets Terraria's plants and debris, all of which you
can walk through:
- **Plants:** short and tall grass; short and tall flowers in all of Terraria's colours; surface
  mushrooms (they drop Mushrooms); Daybloom (it drops Daybloom); patches of Sunflowers (they drop
  Sunflowers, which you can plant).
- **Debris:** small stones, twigs, large rock piles and fallen logs.
- **Vines and flowering vines:** they hang from the grass under overhangs and in cave mouths, and
  fall when the block they hang from is mined.
- **Ponds:** lily pads float on surface ponds, and cattails grow up through shallow water with
  their heads above it.
- **Other biomes:** Snow and the Desert clear these, the Jungle and the evil biomes swap the plants
  for their own, and rocks stay everywhere.
- **Not yet:** herbs don't grow from seeds (Daybloom only appears at world creation).

The Dungeon: every new world gets one. Its entrance sits on the Snow's side of the world (away
from the Jungle) near the coast, its door facing the world's centre, built of the world's dungeon
brick colour (blue, green or pink, like Terraria's).
- **The keep:** shaped like Terraria's cross-section. A tall 15 x 15 keep with corner towers and
  battlements between them, holding one tall hall.
- **The porch:** a long covered porch runs 17 blocks out from the door. Its thick roof has its own
  battlements and a raised block at the far end, and it stands on pillars, open between them,
  over a raised brick floor with half-block steps down at its end. Chain lanterns hang under it.
- **The door:** at floor level in the keep's front, under the porch, with a real arch
  (upside-down ramps).
- **The hall:** pillared and hung with two rows of dungeon banners (Marching Bones, Necromantic Sign, Ragged
  Brotherhood Sigil), lit by chain lanterns and wall torches.
- **The way down:** the back of the hall's floor opens into the entrance hallway, a wide tunnel
  stepping down in sloping stretches (Terraria's LegacyEntranceDungeonHall) to where Terraria's
  dungeon starts: halfway down to the cavern layer, give or take, at least 60 tiles underground.
- **The Dungeon itself** (rust/voxel_core/src/dungeon.rs, a port of 1.4.5's
  DungeonCrawler.MakeDungeon with the legacy layout every normal world gets): from there a walker
  lays rooms and halls of brick, Terraria's sizes a block a tile, its 2D walk spread into 3D (halls
  run up, down or any of the four ways across). It's sent down until 100 tiles under the cavern
  layer's top and kept 100 from the underworld (depths mapped onto this world's layers), inside the
  ocean and within a quarter of the world of where it started, and it stays under the ground.
  Cabins and Enchanted Sword Shrines keep out of it.
- **Doors and platforms:** horizontal halls end in doors (2 in 3 the plain Dungeon Door, else the
  brick colour's) set in a wall of brick across the passage; vertical ones, and halls opening into a
  room's top or bottom, get a platform of the colour's brick across the shaft.
- **Furnishings, in Terraria's order and numbers:** spikes (strips on floors, ceilings and walls,
  every other one sticking 2 out; 60 damage to touch, give or take 15%), shelves (Metal, Brass,
  Wood or Dungeon Shelf) with books (1 in 50 a Water Bolt, deep down), Water Candles and Lesser
  Healing / Mana Potions, a chest in each room, lanterns (three of Terraria's seven styles) and the
  colour's Dungeon Chandeliers hanging from ceilings, each with a switch on a wall nearby that turns
  it on or off (2 in 3 start off), and banners hanging from the ceiling on the walls: Marching
  Bones / Necromantic Sign, Rusted Company Standard / Ragged Brotherhood Sigil or Molten Legion Flag /
  Diabolic Sigil, by which of Terraria's three wall kinds that part of the dungeon would have.
- **Chests:** Locked Gold Chests hold, in turn, the Muramasa, Cobalt Shield, Aqua Scepter, Blue
  Moon, Magic Missile, Valor, a Golden Key (in a wooden chest, as is any chest near the surface)
  and Handgun, with the cavern layer's extras. Right-click one with a Golden Key to open it for good
  (the key is used up; it becomes a Gold Chest).
- **The new weapons:** the Muramasa, Valor (a yoyo) and Handgun with Terraria's stats; the Water
  Bolt bounces off blocks (10 times, through 10 enemies); the Aqua Scepter sprays two streams a use
  for its mana once, falling as they go; the Magic Missile flies toward your crosshair while you
  hold the button, one at a time. The Cobalt Shield stops knockback.
- **Not yet:** Terraria's cracked-brick pit traps, dart and boulder traps, locked biome chests,
  furniture and paintings, and the Dungeon's enemies (Angry Bones and the rest).
- **Bricks:** dungeon brick needs 65% pickaxe power (Nightmare / Deathbringer Pickaxe), as in
  Terraria.
- **The Dungeon biome:** inside (under the keep's roof, or among dungeon brick underground) the
  Dungeon music plays; nothing spawns there yet but the Dungeon Guardian.
- **The Old Man:** he waits under the porch. Right-click him to talk; he can't be hurt. At night he
  offers his Curse (Terraria's NPC.SpawnSkeletron): he dies and Skeletron rises where he stood.
  He's back at dawn if it isn't beaten, and gone for good once it is (the Clothier who'd take his
  place isn't in yet).
- **Skeletron** (Terraria's aiStyles 11 and 12, its numbers): a 4400-life head (32 damage, 10
  defense) with two 600-life hands (20 damage, 14 defense), all flying through blocks. The head
  keeps 250 px (Terraria's, 24 a block here) over your head and closes on you; every 800 ticks it
  spins at you for 400, its defense 10 lower. Each hand hangs out to its side below the head and,
  every 300 ticks, in turn rises over the head and slams down at you (18 px a tick) or swings out
  500 px and sweeps across at you (17); its arm is Terraria's two bones. By day it's enraged
  (9999 damage and defense, spinning at you fast); with you dead or far off it sinks away. Kill the
  head and the hands go with it. It drops 5-15 Healing Potions, 5 gold and, at most one of, the
  Skeletron Mask (1 in 7), Skeletron Hand or Book of Skulls (each 1 in 7 of what's left; the Hand
  isn't in yet, being a grappling hook). The Book of Skulls shoots skulls that fly through blocks
  and home in. Not yet: its trophy, Chippy's Couch, the Hellforge it brings, expert-mode skulls.
- **The Dungeon Guardian:** go below the ground in the Dungeon before Skeletron is beaten and it
  comes for you: Skeletron's head always enraged, 9999 damage, at 8 px a tick through the walls.
  It leaves when you leave the Dungeon.
- **New items:** Blue / Green / Pink Brick, the brick platforms, Spikes, Books, Water Candles,
  the four shelves, the Dungeon Doors, the seven lanterns, the Dungeon Chandeliers, the six banners
  and the Switch are placeable.
- **Old worlds:** worlds made before the entrance don't get one; worlds made before the Dungeon
  keep their sealed shaft.

Sky:
- **Colours:** a gradient from the horizon up that follows the time of day. The sun's side of the
  horizon glows warm at sunrise and sunset, and the sun and moon (with its phases) have soft halos.
- **Fading:** the sky, the light on the world and the clouds follow the clock as one smooth curve:
  the day brightens over 3.75 hours after sunrise (Terraria's 13,500 ticks) and dims as long before
  sunset, which glows orange into twilight while the stars come out. Nothing jumps when day turns to
  night or back.
- **Stars:** pixel stars twinkle at night. In the Space layer the sky darkens and they show by day
  too.
- **Clouds:** Terraria's cloud sprites drift across the sky, with the odd rare shaped cloud. They're
  white by day, warm at sunrise and sunset and dark blue at night. Each day rolls a new
  cloudiness, from nearly clear to overcast, which is saved with the world.
- **Backdrops:** Terraria's background art in three layers: far mountains, nearer mountains or
  hills, then trees. They change with the biome (forest, Snow, Desert, Jungle, Corruption, Crimson)
  and dissolve into each other as you cross over. Far layers are hazier, and all of it is lit by
  the sky.
- **Over the sea:** where the open sea reaches the horizon (looking out from the coast, or from a
  height), the backdrop isn't drawn, so no mountains or trees rise out of the water; over land it
  still shows. The game works out, as you move, how far you see in each direction before the sea.
- **Distance:** the backdrops, clouds and sun always sit just beyond your view distance, so terrain
  is always in front of them, whatever the view distance setting.

Furniture: Terraria's early house furniture and the crafting chain behind it.

| Piece | Made from | Made at | What it does |
| --- | --- | --- | --- |
| Wooden Table | 8 Wood | Work Bench | Solid on top: stand on it, put a candle on it |
| Wooden Chair | 4 Wood | Work Bench | Faces you when placed |
| Bench | 8 any Wood | Sawmill | Faces you when placed |
| Sawmill | 10 any Wood, 2 Iron/Lead Bars, 1 Chain | Work Bench | Crafting station |
| Loom | 12 any Wood | Sawmill | Crafting station |
| Silk | 7 Cobwebs | Loom | |
| Bed | 15 Wood, 5 Silk | Sawmill | Right-click: your spawn point; again clears it |
| Barrel | 9 any Wood, 1 Iron/Lead Bar | Sawmill | A container, like a chest |
| Grandfather Clock | 3 Iron/Lead Bars, 6 Glass, 10 Wood | Sawmill | Right-click: tells the time |
| Candle | 1 Gold Bar, 1 Torch | Work Bench | Light |
| Copper / Silver / Gold Chandelier | 4 Copper / Silver / Gold Bars, 4 Torches, 1 Chain | Anvil | Light; hangs from the ceiling |
| Candelabra | 5 Gold Bars, 3 Torches | Work Bench | Light; stands on tables and dressers |
| Bookcase | 20 Wood, 10 Books | Sawmill | |
| Piano | 4 Bones, 15 Wood, 1 Book | Sawmill | Solid on top |
| Dresser | 16 Wood | Sawmill | A container; solid on top |
| Trash Can | 8 Iron/Lead Bars | Anvil | A container |
| Sign | 6 any Wood | Work Bench | Right-click to write on it; aim at it to read it |
| Lamp Post | 3 Iron/Lead Bars, 2 Glass, 1 Torch | Anvil | Light, three blocks tall |
| Tiki Torch | 1 Torch, 3 any Wood | Work Bench | Light |

- **Recipes are Terraria's own:** every recipe is read from your Terraria.exe
  (`tools/terraria_recipes.py`, run by `extract_assets.sh`), so amounts, stations and "any Wood" /
  "Iron or Lead Bar" are exactly Terraria's. An item is craftable here when everything its Terraria
  recipe takes exists in this game. Two stand-ins remain until their parts exist: the Nightmare
  Pickaxe (without Shadow Scales, from the Eater of Worlds) and Hellstone Bars (at a furnace, not a
  Hellforge). Like Terraria, the Candle, Candelabra and chandeliers take one metal each (Terraria has
  separate Platinum, Tin... versions, not in this game yet), and the plain Work Bench and Wooden
  Table take plain Wood.
- **Supporting recipes:** Chain is 15 from 1 Iron or Lead Bar at an anvil, Glass is 2 Sand at a
  Furnace, Bottles are 2 from 1 Glass at a Furnace, and a Lead Anvil (5 Lead Bars at a work bench)
  works as an anvil. Place a Bottle to brew potions at it (Lesser Healing Potions: a Mushroom, 2 Gel
  and 2 Bottles make 2).
- **Bed:** you respawn at your bed. The bed is saved with your character; if it's gone, you're
  told and come back at the world spawn.
- **Books and Bones:** Books sit on the Dungeon's shelves (and, as before, turn up in underground
  chests). Skeletons drop Bones.
- **Signs:** the editor closes with Save, or with Cancel or Escape to leave the sign as it was.
  What's written is saved with the world and goes when the sign is broken.
- **Cobwebs:** they hang in patches in cave corners. They slow you to a crawl and break your
  fall, and they drop Cobweb.

Platforms: Wood, Boreal Wood, Rich Mahogany, Ebonwood, Shadewood and Cactus Platforms. One wood
(or cactus) makes two, with no crafting station needed; the Wood Platform takes plain Wood, as in
Terraria.
- **Look:** Terraria's plank, flush with the top of its block (where you stand), a quarter of a
  block thick.
- **Moving:** they hold you up from above only. You land on them, jump up through them and walk
  under them. Hold Shift (Drop down, rebindable) to fall through. Walking into one at your feet
  steps up onto it, so a diagonal row of them makes a staircase. Flying passes through them.
- **Others:** enemies and dropped items land on them too.
- **Placing:** a platform goes next to a block, or off the side of another platform, so a row of
  them can bridge a gap in mid-air.
- **Breaking:** platforms stay put when the block under them is mined. Torches and other props
  can stand on them.

Doors: Wooden, Boreal Wood, Rich Mahogany, Ebonwood, Shadewood and Cactus Doors, each made from
6 of its wood (or cactus) at a work bench. The Wooden Door takes plain Wood, as in Terraria.
- **Shape:** a door is 1 block wide and 2 tall, since you are 2 blocks tall here (3 in Terraria).
  It is drawn from Terraria's door art, given some thickness.
- **Placing:** it goes on a floor with two free blocks above it, facing you. Its hinge goes on
  the side of the block you aimed at.
- **Opening:** right-click either half. It swings a quarter turn away from you; if that side is
  blocked, it swings the other way.
- **Closing:** right-click again. A door won't close on anyone standing in the doorway.
- **Enemies:** a closed door is solid, so enemies that walk can't get through (Terraria's
  zombies can't open doors either).
- **Aiming:** you can mine and build through an open doorway; only the door itself gets in the way.
- **Breaking:** either half breaks the whole door and drops it, and so does mining the floor
  under it.

Liquids: Terraria-style finite water and lava that fall, level out and settle (only moving
cells are simulated); cave pools, surface ponds and Underworld lava lakes; lava glows, burns
and sets you On Fire!, water breaks falls, needs breath (bubbles) and puts fires out;
water + lava makes obsidian; buckets scoop and pour; items burn in lava; saved with the world.
Waterfalls: liquid pouring off a ledge renders as an animated falling stream (Terraria's
Waterfall textures), and worlds get decorative springs on cliffs and cave walls plus lavafalls
from the Underworld ceiling - visual only like Terraria's, so they never drain or flood - with
splashes, looping sound, and re-measuring when you build or dig around them. Make your own
like Terraria's half-block trick: hit a block that has water or lava behind it with a hammer
(Wooden Hammer from 8 Wood at a work bench, metal hammers at an anvil) to open a spring in that
face; it runs while the liquid is there, and hammering the face again closes it.

Hammered blocks: like Terraria's, a hammer reshapes the blocks it hits. Each hit moves the block on
one step:
1. Full block.
2. Half block (the bottom half).
3. Ramp, rising away from you, so you can walk up it in the direction you face. Ramps are pixel
   staircases like Terraria's slopes: 16 one-pixel steps per block. The side texture follows the
   slope, so a grass ramp's green edge runs up the steps.
4. Ramp upside down (a ceiling slope).
5. Back to full.

- **Moving:** half blocks and ramps hold you up in their shape (on a ramp, the step you see). You walk smoothly up a ramp, step up
  onto a half block, and a row of ramps makes a staircase. Upside-down ramps make arches.
- **Light:** shaped blocks let light through.
- **Which blocks:** any solid cube block can be shaped (not unbreakable ones, torches, plants or
  furniture). A block with water or lava behind it still gets a spring instead.
- **Saving:** shapes are saved with the world. Breaking a shaped block and putting a block back
  gives a whole one.

Stairs: like Terraria's platform stairs, a hammer turns a platform into a stair. The first hit
makes it rise away from you, the next the other way, the next flat again. A stair is drawn like
Terraria's: its platform's stair frames (two treads per tile) up the block's diagonal with the
diagonal beam Terraria draws under a stair that goes on down, so a staircase is one piece (in
whatever 3D method the platform uses), and you walk up its steps; set them one up and one along each time for a staircase,
with flat platforms for landings. Like any platform, you jump up through a stair from below and drop
through it holding Down. Stairs are saved with the world.

Floating islands: high in the Space layer, well above the mountains and away from spawn, each a
lens of grassy dirt with a cloud underside and cloud puffs (some rain clouds), trees, and either a
Skyware house, a sky lake, or nothing. Houses follow Terraria's: a blue Sunplate shell with gold
trim on its edges, lined with Disc Wall, glass windows, hanging Skyware lanterns, a World Banner
and a Skyware chest (Starfury, Lucky Horseshoe or Shiny Red Balloon). Clouds break falls, the Lucky Horseshoe stops fall damage, the Shiny Red Balloon
jumps higher and Starfury calls stars down where you aim. Harpies circle above you in Space and
throw feathers (they drop Feathers); Space has its own music and depth readout.

The world evil (Corruption or Crimson; random by seed, or chosen under "World evil" when creating a
world): 2-3 patches away from spawn where grass, stone, sand, plants and trees turn evil (purple
ebonwood or red shadewood trees under matching canopies), with veins of ebonstone/crimstone and
Demonite/Crimtane ore (65% pickaxe for the stone, 55% for the ore). The Corruption sinks deep
chasms whose side passages end in Shadow Orbs; the Crimson winds tunnels down to a flesh cavern
whose tendrils end in Crimson Hearts; demon/crimson altars sit at the bottom and through the
caverns (they can't be smashed yet). Smash orbs and hearts with a hammer for Musket / Vilethorn /
Band of Starpower or The Undertaker / Crimson Rod / Panic Necklace, with Terraria's warnings.
Inside a patch the sky and fog take its colour, its music plays, and its enemies spawn: Eater of
Souls, or Crimera and Face Monsters. The test world has a small patch of each to the south.

Armor: three slots (head, body, legs) left of the accessories in the inventory, with Terraria's
empty-slot silhouettes, the defense shield under them and a picture of you wearing it beside them
(Terraria's player sprites and the armor's equip sprites, which you never see in first person).
Defense takes half its value off each hit. Sets: Wood, Boreal Wood, Rich Mahogany, Ebonwood and
Shadewood (work bench); Cactus (spines hurt whatever touches you); Copper to Platinum (anvil; the
set adds 2-4 defense); Mining (chests; Mining Helmet light, faster digging); Jungle (Stingers,
Jungle Spores and Vines; mana, magic crit, cheaper spells); Necro (Bones and Cobwebs; ranged
damage and crit); Molten (Hellstone Bars; melee damage, crit and speed, fire immunity). Tooltips
and set bonuses use Terraria's own text, read from Terraria.exe. Hellstone sets you on fire when
you touch it unless you wear the Molten set or an Obsidian Skull (20 Obsidian at a furnace). A
held torch lights your surroundings like the Mining Helmet. Shadow, Crimson and Meteor armor wait
for the evil bosses and meteorites.

Town NPCs: the Guide is there from the start; the Merchant comes once you carry 50 silver, the
Nurse once the Merchant lives here and you have over 100 max life, the Arms Dealer once you carry a
gun or bullets, the Dryad once you've beaten a boss, the Demolitionist once you carry an explosive. Each needs a free home near you and moves in
with a name from Terraria's lists ("Andrew the Guide has arrived!"). A home is Terraria's: a room
closed off on every side (floor, walls, ceiling) by blocks, doors and platforms, 18 to 1500 open
cells, with a door or platform, a light source, a table and a chair. Residents walk about near
home by day, opening doors and shutting them behind them, and go home at night. They walk paths
(round their house's walls and out the door, up steps, down short drops, never off a cliff)
rather than straight lines, so they don't get stuck against walls. Right-click one to
talk (Terraria's own lines, naming the others who live here): the Merchant (torches, potions,
arrows, Copper tools, an Iron Anvil, Mining gear), Arms Dealer (Musket Balls, Flintlock Pistol,
Unholy Arrows at night) and Dryad (plants) have shops - click to buy, sell anything for a fifth of
its value; the Guide's Help gives Terraria's tips; the Nurse heals you for a price; the Dryad's
Status tells how corrupt the world is. Coins join up (100 copper make a silver). Inventory ->
Housing lists who lives where and checks the room you're in, with Terraria's reasons. The test
world has a row of houses east of the arena with all six living there.

Yoyos: the Wooden Yoyo (10 wood, 20 cobweb), Malaise (10 Demonite Bars), Artery (10 Crimtane Bars),
Amazon (Rich Mahogany, Stingers, a Vine, Jungle Spores), and Rally and Code 1 from underground
chests, with Terraria's damage, reach and spin times. Hold the use button: the yoyo flies out on its
string to what you aim at (an enemy in your sights, or as far as its reach), spins there and hits
whatever it touches several times a second, bouncing off; each hit takes a little off its spin, and
a block between you and it weakens it. Let go, or let the spin run out, and it comes back; like Terraria's, it takes a fresh click to throw
it again (holding the button as it comes back doesn't). Melee
speed lengthens its reach; a White String (chests) adds a quarter and 1.9 blocks.

Fallen Stars fall at night, at Terraria's rate: each tick a 10 in 8000 chance on a small world
(about 40 a night; more on bigger worlds), more on a Starfall night (1 in 10: 3 to 5 times as
many) or a slightly starry one (1 in 3: up to half as many again). They start high in the sky
anywhere over the world and come down at a slant; 1 in 15 is a lucky star that falls within 40
blocks of you, drifting your way. A falling star twinkles and shines, hits enemies it passes for
1000 (never you or the town's NPCs) and lands as a Fallen Star, which glows, twinkles through its
animation and fades at sunrise unless you've picked it up. Five make a Mana Crystal; one turns a
Wooden Boomerang into an Enchanted Boomerang.

Boomerangs: the Wooden Boomerang (chests), Enchanted Boomerang (a Wooden Boomerang and a Fallen
Star), Thorn Chakram (6 Jungle Spores, 9 Stingers at an anvil), Flamarang (10 Hellstone Bars and an
Enchanted Boomerang), Trimarang (Enchanted, Ice and Shroomerang at a work bench) and Ice Boomerang
(Frozen Chests), plus the Shroomerang, Fruitcake Chakram, Bloody Machete and Combat Wrench (creative
only for now: Spore Bats, the holidays and the Mechanic aren't in yet), with Terraria's stats. A click
throws it from your hand along your aim; it flies straight for Terraria's 30 ticks (the Wooden
Boomerang about 12 blocks), or until it hits a block (bouncing off) or an enemy (turning round),
then homes back to you through blocks at its own return speed, hitting everything it passes, and
you catch it. One at a time, three Trimarangs; the Bloody Machete drops instead of turning round.
Melee speed throws it faster and brings it back sooner.

Flails: the Mace (underground chests), Flaming Mace (a Mace and 99 Torches), Ball O' Hurt (Shadow
Orbs), The Meatball (10 Crimtane Bars and 5 Tissue Samples at an anvil), and the Blue Moon and Sunfury
(the Blue Moon in the Dungeon's chests; the Sunfury creative only for now: the Underworld's Shadow
Chests aren't in yet), with
Terraria's stats and its flail AI (AI_015_Flails), in its pixels (16 a block) and ticks:
- **Spinning:** hold the button and it whirls round over your head, 5 turns a second. After 12 ticks
  it hits anything within 55 px of you that you can see, each enemy every 15 ticks, for 1.2x damage
  and 0.35x knockback.
- **Thrown:** let go and it flies at your aim at its launch speed, plus your own (the Mace 12 px a
  tick for 13 ticks, about 10 blocks). Then it slows and comes back. Out and back it does 2x damage,
  which is the damage its tooltip shows, as in Terraria.
- **Ricochet:** a block in its way bounces it off. It falls for 15 ticks, then it's pulled back.
- **Dropped:** click while it's out and it drops to the ground. It stays there while you hold the
  button, with half knockback. Let go (or walk too far) and it's pulled straight back through blocks.
- **Hits:** knockback always pushes away from you. Melee speed makes it faster all round. Switching
  items puts it away.
- **Fire:** the Sunfury (1 hit in 2, for 5 s) and the Flaming Mace (1 in 6, for 2 to 3 s) set enemies
  On Fire!. They lose 4 life a second, shown 1 at a time, and burn with flames (half the size of Terraria's). The Flaming Mace turns
  into a plain Mace in water, as in Terraria.
- **Looks:** each has Terraria's head sprite and chain links (the Flaming Mace's first links glow) and
  its dust (Corruption motes, blood, blue sparkles, fire). They're drawn to the player's pixels, so
  the Sunfury's head is two thirds your height; links near your eye are drawn thinner.

The Enchanted Sword, from the sword in stone of an Enchanted Sword Shrine, with Terraria's stats
(23 melee damage, 4.25 knockback, a 21-tick swing): with a swing it shoots an Enchanted Beam, at
most every 45 ticks (Terraria's use time). The beam flies point first at 9.5 px a tick, glows,
trails Terraria's blue and gold dust, and stops at the first enemy or block.

The Terragrim (1 time in 30 from the sword in stone instead of the Enchanted Sword), with Terraria's
stats (17 melee damage, 3 knockback) and its held slash (projectile AI 75, Projectile 735):
- **Slashing:** hold the button and it slashes on toward your aim until you let go, with a swing
  sound every 12 ticks, its green dust and its light (you shine while you slash). Terraria's 28-frame
  flurry glows on a sheet centred on you, as big as its hitbox, lying flat round you at shoulder
  height: the slashes arc round you, sweeping out the way you aim (and tilting as you look up or
  down).
- **Hits:** its hitbox (68 x 64 px) is centred on you, so it reaches about two blocks round you,
  even a little behind, hitting what you can see. Each enemy is hit at most every 5 ticks: 12 hits a
  second at the item's damage (melee speed doesn't change it, as in Terraria). It cuts grass round you.

The world's first Shadow Orb always gives the Musket, as in Terraria (then one of the Musket,
Vilethorn, Ball O' Hurt and Band of Starpower).

Spears: the Spear (chests), The Rotted Fork (Crimson Hearts), the Storm Spear (deep desert
cabins' Sandstone Chests), and the Trident, Slime Spear, Swordfish and Dark Lance (creative only
for now: their Water and Shadow chests, the Solidifier and fishing aren't in yet), with Terraria's damage, speed and knockback. A
click thrusts the spear out along your aim and pulls it back, its tip going exactly as far as
Terraria's (the Spear 5 blocks, the Storm Spear 6.7); it hits every enemy the tip touches, each up to
6 times a second, but only ones you can see. The Dark Lance and Rotted Fork reach a little past
the tip as they thrust, and the Storm Spear throws a short lightning bolt. The spear is the
projectile's own sprite in 3D: held, it rests in your hand pointing at the crosshair, and a
thrust slides it out along that line and back (the hits use Terraria's real tip, which is always
on the crosshair). Melee speed makes it
quicker and its reach a little longer.

Cabin loot (Frozen and Sandstone Chests), with Terraria's stats:
- **Ice Blade:** a sword that shoots an icy bolt with a swing, at most every 55 ticks (Terraria's
  use time, longer than its swing); the bolt glows and stops at the first enemy or block.
- **Snowball Cannon:** fires Snowballs (15 from a Snow Block, no station), which you can also
  throw; they fly straight for a third of a second, then drop (Terraria's thrown projectile AI).
- **Glacier Fang:** hold the button to charge an icicle lance. 10 mana to start and 10 more a
  third and two thirds of the way (without the mana it charges at 40%); full after a second, it
  flies by itself. The longer it charged, the harder it hits (150% to 400%), the faster and bigger
  it flies, and the more enemies it pierces (1 from half a second, 2 at full), each taking 34%
  off its damage.
- **Thunder Zapper:** a staff whose bolt zigzags across its way and fades after a second.
- **Snake Charmer's Flute:** a rope snake rises from a basket where you aim (or at your feet), up
  to 67 blocks (Terraria's 100 tiles) or until a block stops it, and stays 30 seconds. Jump into it
  to grab it: jump climbs, Drop down lets you down, walking away lets go.
- **Magic Conch:** after 0.75 s, takes you to the ocean furthest from you. The sea is all round
  the island here, so it's the beach across the world (through its middle), on the sand by the
  water.
- **Accessories:** Ice Skates (you slide much less on ice), Blizzard in a Bottle (a double jump
  higher than the Cloud's; wearing both, you get both, the Cloud's first), Flurry Boots (run
  fast, like the Hermes Boots), Dunerider Boots (run fast, and 75% faster on sand, sandstone and
  hardened sand), Ancient Chisel (25% faster mining).
- **Furniture:** the Bast Statue (+5 defense, The Bast Defense, while one is within Terraria's
  170 x 125 tiles of you), the Sharpening Station (right-click it: Sharpened, melee weapons ignore
  12 of an enemy's defense until you die) and the Extractinator (below).

**Silt, slush and the Extractinator.**
- **Where they are:**
  - Silt lies in patches through the cavern layer, about 1.5% of its blocks, as in Terraria's own
    worlds.
  - Inside the snow biome, silt and mud become slush, as Terraria's slush pass does.
  - The underground desert has none.
- **Using the Extractinator:** hold Silt or Slush and use it on an Extractinator. It takes one
  block every 10 ticks, plays Terraria's sound and drops the result where you aim.
- **What comes out:** Terraria's own odds (`ExtractinatorHelper.RollExtractinatorDrop`).
  - About two-thirds coins (copper mostly; now and then silver, gold or even platinum).
  - About a third ore: copper, tin, iron, lead, silver, tungsten, gold or platinum.
  - 2% gems, 1% Amber, sometimes several at once.
  - 1 in 10,000 an Amber Mosquito. It's in as an item, but its Baby Dinosaur pet isn't, since
    the game has no pets yet.
- Desert Fossils and fishing junk aren't in the game yet.

**Falling sand.** Sand, ebonsand, crimsand, silt and slush fall when nothing holds them up, as in
Terraria (`WorldGen.SpawnFallingBlockProjectile`).
- **When they fall:** when you dig out the block under one, or place one over a gap; a whole
  column drops together.
- **The fall:** 0.41 px/tick² up to 10 px/tick. A falling block hits players and enemies it
  passes for 10 damage (knockback 6).
- **Landing:** it becomes its block where it lands. If a torch or another object fills that
  spot, it drops as an item instead.
- **What holds them up:**
  - Solid blocks and platforms do; air, actuated blocks and icicles don't.
  - A torch or plant does only if there's ground under it.
  - Sand under a chest, dresser, altar, cactus or palm stays put.
- Sand left over caves by worldgen stays until something disturbs it.
- **Buried:** if sand lands on you, you're stuck in it with Suffocation (20 life a second) until
  you dig yourself out.

Explosives: Bombs, Sticky Bombs (Bomb + Gel), Dynamite, Sticky Dynamite and Grenades, thrown
with the use button. A lit bomb is lobbed, bounces and rolls to a stop (sticky ones stick to the
first thing they touch) and goes off when its fuse burns down; a grenade also goes off on hitting
an enemy. The blast hurts enemies in reach and you too (not grenades), and bombs and dynamite blow
a sphere of blocks away (radius 3.5 / 6), dropping what they drop as one pile per item. Chests,
dungeon brick, Hellstone, orbs and altars are blastproof. Bombs turn up in pots and chests,
Dynamite rarely in chests. The Demolitionist moves in once you carry an explosive and sells
Grenades, Bombs and Dynamite.

Enemy health bars: Terraria's bar (HealthBar1/2, green through yellow to red) floats above an
enemy's head once it is hurt, facing you; bosses get a bigger one. Town NPCs and target dummies
have none. Settings → Interface → "Enemy health bars" turns them off.

Not yet: the evil bosses (Eater of Worlds, Brain of Cthulhu), Devourers and Blood Crawlers,
Giant Worms, the other town NPCs (Goblin Tinkerer, Clothier...), NPC happiness,
other biomes and bosses; the ocean's palm
trees, seashells and fishing; Granite and Marble caves, the Dungeon's
enemies, traps and furniture, and the Underground Desert's open caverns.
