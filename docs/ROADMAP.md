# Roadmap

Updated 2026-10-27. The goal is Terraria 1.4.5 in first-person 3D, with its numbers, recipes, drops
and AI taken from Terraria's own code. This page lists what's done, what's left before Hardmode,
and Hardmode itself, in the order planned.

## Where it stands

- **Content:** 1,495 items (766 of them blocks), 190 NPC kinds, 7 of Terraria's 8 pre-Hardmode bosses, 11 town residents plus
  the Traveling Merchant and the Skeleton Merchant.
- **Characters:** saved apart from worlds, as in Terraria, with Classic, Mediumcore and Hardcore.
- **World sizes:** small, medium and large, in Terraria's 1 : 1.5 : 2 proportions. Each world is
  an island in an ocean.
- **Tests:** about 1,500 automated checks across the Godot suites and 111 Rust tests.

## Done

| Phase | What it covered |
|---|---|
| Vertical slice | Forest, underground and caverns; digging and building; crafting; combat; day and night; the Eye of Cthulhu; music; saving |
| Biomes and gear | Snow, Desert, Jungle, Corruption and Crimson; armor and set bonuses; accessories; town NPCs and housing; underground cabins |
| 1. Underworld | Ash forests, ruined forts, Shadow Chests, Hellstone gear, Underworld enemies |
| 2. Dungeon | Layout, traps, biome chests, furniture, Dungeon enemies, Skeletron and the Dungeon Guardian, wiring |
| 3. Everyday systems | Fishing and the Angler, herbs and alchemy, buff potions, Well Fed, the Piggy Bank and Safe, summons and whips, pets, debuffs |
| 4. Town and events | Rain, storms and wind, the Blood Moon, Slime Rain, the Goblin Army, meteorites, the Witch Doctor, Skeleton Merchant and Traveling Merchant |
| 5. Biomes and structures | Glowing Mushroom biome, Granite and Marble caves, spider caves, Pyramids and Dunes, the Jungle Temple, gem trees |
| 6. Wall of Flesh | The boss, the Guide Voodoo Doll, its loot and items; Hardmode as a flag only |
| Characters | Character creation (Terraria's hairstyles, clothing styles and colours), character select, difficulties |

Also in: the Queen Bee, the Brain of Cthulhu, the Eater of Worlds and King Slime; optional sun
shadows and global illumination; third-person views; render scale and upscaling; the Windows
installer; and the editing tools (placeable picker, NPC picker, model sculptor and others).

## Phase 7: finish pre-Hardmode

Ordered by how much they change play. Rough size: **S** a session, **M** a few, **L** a week or
more.

### 7.1 Missing content people will notice

- **Deerclops (M):** the last pre-Hardmode boss, with its drops (Lucy the Axe, Pew-matic Horn,
  Weather Pain, Houndius Shootius, Eyebrella).
- **Meteorite gear (S):** Meteor armor, the Space Gun and the Star Cannon. Meteorites already land.
- **Gaps in the gear (M):**
  - Weapons: the Minishark, the Sandgun, the Volcano, the Blade Staff, Abigail's Flower.
  - Accessories: the rest of the Water Walking Boots line, Terraspark Boots, the Magic Quiver.
  - The Water Chest's Sandcastle Bucket (a wand placing sandcastles) and Shark Bait (a pet).
  - Hooks: the Dual Hook and the Skeletron Hook.
  - Info combinations: the Fish Finder, the PDA and the Cell Phone.
- **Missing enemies (M):** the Devourer, Blood Crawler, Tomb Crawler, Dune Splicer and Doctor Bones.
- **Mounts and minecarts (M):** the Fuzzy Carrot, minecarts and minecart tracks, with Terraria's
  track worldgen (its TrackGenerator: 1-2 long tracks and 4-7 standard ones in a small world,
  tunnelling through the rock).
- **Cages and terrariums (S):** critters in cages, which the Bug Net already supports.

### 7.2 Worldgen gaps

Taken from a pass-by-pass comparison with Terraria's world generation.

- **Structures and biomes:** done: moss, with neon patches, lava moss and Long Moss; gem caves
  and loose gems, amber included; oases, with palms, sea oats and oasis plants; ocean caves and
  Water Chests; the Underground Desert's caverns, Desert Fossil and its four entrances; the
  Aether and its shimmer; Terraria's placement passes (cave statues, biome pots, piles,
  stalactites and stalagmites, dye plants, sea shells, sea oats, shell piles, seaweed) and its
  micro biomes but the tracks (campsites, thin ice and frozen pools, Dead Man's Chests, mining
  explosives, lava traps).
- **Shimmer extras (M):** Faelings and the Shimmer Slime; enemies and town NPCs in shimmer
  (Terraria's shimmered look); critters and projectiles in it (critters become Faelings, some
  projectiles bounce up); the Aether's music and backdrop; the Shimmer Arrow, Flare, Campfire,
  Cloak and Monolith, Aetherium furniture and walls; luck, which coin luck and the Galaxy Pearl
  feed (nothing uses luck yet).
- **Underground Desert extras (S):** Antlion Eggs and Rolling Cactus in its caverns, its piles,
  and its enemies (Tomb Crawlers, Ghouls, Sand Poachers, Antlion Swarmers and Chargers).
- **Placement extras (S):** the statues' traps (they need statues that spawn on a signal, see
  7.4); the strange plants, which grow later on; the piles of the spider caves and living trees.

### 7.3 Town and events

- **Town NPCs (L):** the Painter, Dye Trader, Party Girl, Stylist, Tavernkeep, Golfer, Zoologist,
  Tax Collector and Princess, plus town pets. Several need new systems: paint, dyes, golf, the
  Old One's Army, the Bestiary.
- **NPC happiness (M):** biome and neighbour preferences, and their effect on shop prices.
- **Events (M):** Parties, Lantern Night, Sandstorms, the Torch God, and the first tier of the
  Old One's Army.
- **Graveyards (S):** tombstones from deaths, and the graveyard biome. Some recipes wait for it.

### 7.4 Systems

- **Map (M):** a minimap and a full-screen map. There's no map of any kind yet.
- **Paint and dyes (M):** painting blocks, dye items and the Dye Vat, and dye slots.
- **Bestiary (M):** kill and sighting records, and the Zoologist's shop conditions.
- **Wiring extras (S):** statues that spawn on a signal, pumps, logic gates.
- **Equipment loadouts and vanity slots (S).**

### 7.5 Clean-up

- **The Gem staves:** the Topaz, Sapphire, Emerald and Ruby Staves' gem effects.

## Phase 8: Hardmode

### 8.1 The switch (L)

- **World conversion:** the Hallow and a second evil in Terraria's V-shaped stripes, and the
  biomes spreading over time.
- **Altars and ores:** smashing altars with the Pwnhammer brings Cobalt or Palladium, Mythril or
  Orichalcum, and Adamantite or Titanium.
- **Hardmode gear and stations:** souls, the Mythril Anvil and Adamantite Forge, the ore gear.
- **Spawns:** Hardmode spawn tables, and Hardmode versions of the cave and surface enemies.
- **The Hallow** as a biome, with its enemies.

### 8.2 Early Hardmode (L)

- **Bosses:** Queen Slime, the Twins, the Destroyer and Skeletron Prime, with Hallowed gear.
- **Town NPCs:** the Wizard, Truffle, Pirate, Steampunker, Cyborg and Santa.
- **Events:** the Pirate Invasion and the Frost Legion.

### 8.3 Mid Hardmode (L)

- **Plantera:** Plantera's bulbs in the Jungle, and the Temple Key.
- **Golem:** the Jungle Temple is already in, with its altar and Power Cells.
- **Duke Fishron and the Empress of Light.**
- **Events:** the Solar Eclipse, the Pumpkin Moon, the Frost Moon, and tiers 2 and 3 of the Old
  One's Army.

### 8.4 Endgame (L)

- **Martian Madness and the Lunatic Cultist.**
- **The Lunar Events:** the four pillars.
- **The Moon Lord,** and its gear.

## Engineering, alongside

- **Performance:** in a large world each game tick costs about 10 ms during the Wall of Flesh
  fight. That's fine at normal speed (110–120 fps) but leaves little headroom; profile it before
  Hardmode adds more enemies.
- **Generating worlds without a window:** a full world hangs while loading when run headless, so
  world-generation tests must open a window.
- **Old saves:** worlds saved before characters still hold their own player, which is ignored when
  you play them with a character.

## Decisions for you

- **The Wall of Flesh's speed:** it moves at Terraria's speed relative to you, so it crosses our
  narrower worlds about 3.7 times faster (3:21 to 6:46 instead of 12:23 to 24:50). Keep that, or
  slow it to keep Terraria's crossing times?
- **Creative or Journey:** creative is a per-world switch, so a character can carry items from a
  creative world into a survival one. Terraria ties Journey mode to the character to prevent
  that. Keep it as it is, or make Journey a character difficulty?
- **What comes first:** finish Phase 7, or start Hardmode (8.1) now that the Wall of Flesh is in?
- **Expert and Master modes:** not planned so far. Their stat and AI changes would touch every
  boss.
