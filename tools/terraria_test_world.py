#!/usr/bin/env python3
"""Builds a Terraria world laid out like the game's test world
(game/scripts/world/test_world.gd), to compare the two side by side.

usage: python3 -I terraria_test_world.py <template.wld> <out.wld> [name]

The template is a fresh Journey-mode world from Terraria's own generator
(TerrariaServer -config with autocreate=1, difficulty=3). A strip of forest at
spawn is flattened and, west to east, gets: a garden, a furnished house and a
library, hammered blocks, the liquid lab (pool with swimming-enemy statues, a
waterfall, hammer springs, a lava pit), a dark room, chests holding every item
in game/data/items.json, the spawn plaza (crafting stations), target dummies,
the enemy arena (statues on switches stand in for the spawners), the town
(Guide, Merchant, Nurse, Arms Dealer, Dryad, Demolitionist, housed), the
fall-test tower, platforms, and the block gallery (one of every block in
game/data/blocks.json) with the ore wall. Biomes, the Dungeon, floating islands,
cabins and the evil biome are the world generator's own. Journey's enemy
strength is set to Normal (1x).
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terraria_wld import World, Chest, Item, TownNPC, WATER, LAVA  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STRIP = 580  # how wide the flattened strip is
CLEAR_UP = 110  # how far above the ground it is cleared

# Terraria tile and wall IDs used by the builder.
DIRT, STONE, GRASS, TORCH, TREE, WORKBENCH, ANVIL, FURNACE = 0, 1, 2, 4, 5, 18, 16, 17
DOOR, TABLE, CHAIR, CHEST, PLATFORM, WOOD, BRICK, OBSIDIAN = 10, 14, 15, 21, 19, 30, 38, 56
CANDLE, CHANDELIER, SUNFLOWER, PLANTS, TALL_PLANTS, VINES, FLOWER_VINES = 33, 34, 27, 3, 73, 52, 382
COBWEB, SIGN, BED, DRESSER, PIANO, BOOKCASE, CANDELABRA, LAMP_POST, LAMP = 51, 55, 79, 88, 87, 101, 100, 92, 93
CLOCK, STATUE, SAWMILL, LOOM, SWITCH, DUMMY, DAYBLOOM, ROCKS, LARGE_ROCKS = 104, 105, 106, 86, 136, 378, 84, 185, 186
FALLEN_LOG, JUNGLE_GRASS, CORRUPT_GRASS, CRIMSON_GRASS = 488, 60, 23, 199
W_STONE, W_WOOD, W_BRICK = 1, 4, 5
CONTAINERS = {21, 467, 88}
SIGNS = {55, 85, 425, 573}
TREES = {5, 323, 583, 584, 585, 586, 587, 588, 589, 596, 616, 634}

# Statue styles (tile 105) and what Wiring.HitWireSingle spawns from them.
LAND_STATUES = [(4, "Slime: Blue Slime"), (74, "Armed Zombie"), (10, "Skeleton"), (35, "Eyeball: Demon Eye"),
                (7, "Bat: Cave Bat"), (70, "Harpy"), (30, "Corrupt: Eater of Souls"), (18, "Crab"),
                (16, "Hornet")]
WATER_STATUES = [(50, "Shark"), (23, "Jellyfish: Blue Jellyfish"), (42, "Piranha")]

# Town NPCs (NPCID) and their name lists in ids.json.
TOWN = [(22, "GuideNames"), (17, "MerchantNames"), (18, "NurseNames"), (19, "ArmsDealerNames"),
        (20, "DryadNames"), (38, "DemolitionistNames")]

# The test world's chest categories (TestWorld.CATEGORIES).
CATEGORIES = [
    ("Weapons", ["melee", "ranged", "magic", "thrown"]),
    ("Tools", ["tool", "bucket", "tool_use"]),
    ("Ammo", ["ammo"]),
    ("Potions & Summons", ["consumable", "summon"]),
    ("Accessories", ["accessory"]),
    ("Armor", ["armor"]),
    ("Blocks", ["block"]),
    ("Materials", ["material"]),
    ("Coins & Misc", []),
]
COINS = ["CopperCoin", "SilverCoin", "GoldCoin", "PlatinumCoin"]


class Builder:
    def __init__(self, w):
        self.w = w
        self.ids = json.load(open(os.path.join(ROOT, "game/assets/terraria/ids.json")))
        self.items = json.load(open(os.path.join(ROOT, "game/data/items.json")))["items"]
        self.blocks = json.load(open(os.path.join(ROOT, "game/data/blocks.json")))["blocks"]
        self.rng = random.Random(7)

    # -- cells

    def t(self, x, y):
        return self.w.tile(x, y)

    def block(self, x, y, type, fx=0, fy=0, slope=0, half=False):
        t = self.t(x, y)
        t.clear_block()
        t.liquid = t.liquid_kind = 0
        t.active, t.type, t.fx, t.fy, t.slope, t.half = True, type, fx, fy, slope, half

    def air(self, x, y):
        t = self.t(x, y)
        t.clear_block()
        t.liquid = t.liquid_kind = 0

    def box(self, x0, y0, x1, y1, type):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                self.block(x, y, type)

    def walls(self, x0, y0, x1, y1, wall):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                self.t(x, y).wall = wall

    def liquid(self, x0, y0, x1, y1, kind):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                self.air(x, y)
                t = self.t(x, y)
                t.liquid, t.liquid_kind = 255, kind

    def wire(self, cells, bit=1):
        for x, y in cells:
            self.t(x, y).wires |= bit

    def obj(self, type, x, y_top, w, h, fx=0, fy=0):
        """A multi-tile object, its top-left frame (fx, fy), 18px per tile."""
        for dx in range(w):
            for dy in range(h):
                self.block(x + dx, y_top + dy, type, fx + dx * 18, fy + dy * 18)
        if type in CONTAINERS:
            self.w.chests.append(Chest(x, y_top))
        return w

    def floor_obj(self, type, x, w, h, fx=0, fy=0, floor=None):
        """An object standing on the row `floor` (default: the ground)."""
        floor = self.G if floor is None else floor
        return self.obj(type, x, floor - h, w, h, fx, fy)

    def sign(self, x, floor, text):
        self.floor_obj(SIGN, x, 2, 2, floor=floor)
        self.w.signs.append([x, floor - 2, text])

    def door(self, x, floor, style=0):
        """A closed door (1x3) in a wall, its top at floor - 3."""
        for dy in range(3):
            self.block(x, floor - 3 + dy, DOOR, (style // 36) * 54, (style % 36) * 54 + dy * 18)

    def torch(self, x, y, style=0, on_wall=False):
        self.block(x, y, TORCH, 66 if on_wall else 0, style * 22)

    # -- the strip

    def flatten(self, left, right, G):
        w = self.w
        # Don't cut trees in half: widen the strip past any at its edges.
        def has_tree(x):
            return any(w.tile(x, y).active and w.tile(x, y).type in TREES for y in range(G - 80, G + 6))
        while has_tree(left - 1) or has_tree(left - 2):
            left -= 1
        while has_tree(right + 1) or has_tree(right + 2):
            right += 1
        for x in range(left, right + 1):
            col = w.column(x)
            for y in range(G - CLEAR_UP, G + 15):
                col[y].clear()
                if y >= G:
                    col[y].active = True
                    col[y].type = GRASS if y == G else DIRT
        inside = lambda x, y: left <= x <= right and G - CLEAR_UP <= y < G + 15
        w.chests = [c for c in w.chests if not inside(c.x, c.y)]
        w.signs = [s for s in w.signs if not inside(s[0], s[1])]
        w.entities = [e for e in w.entities if not inside(e[2], e[3])]
        return left, right

    def build(self, center_x, G):
        self.G = G
        left, right = self.flatten(center_x - STRIP // 2, center_x + STRIP // 2, G)
        self.left, self.right = left, right
        x = left + 4
        for section in [self.garden, self.house, self.library, self.hammered, self.liquids, self.dark_room,
                        self.storage, self.plaza, self.dummies, self.arena, self.town, self.tower,
                        self.platforms, self.gallery]:
            print("  %-10s %d" % (section.__name__, x))
            x += section(x) + 4
        x -= 4
        if x > right:
            raise SystemExit("the test area (%d..%d) is wider than the strip (%d..%d)" % (left, x, left, right))
        self.set_town_npcs()
        return left, x

    # -- sections (each takes its west edge, returns its width)

    def garden(self, x):
        """Forest plants: each ground piece at least twice, sunflowers, a pond,
        and a grassy ledge with vines under it."""
        G, rng = self.G, self.rng
        pieces = [(PLANTS, 0), (PLANTS, 36), (PLANTS, 6 * 18), (TALL_PLANTS, 0), (TALL_PLANTS, 6 * 18),
                  (PLANTS, 8 * 18), (DAYBLOOM, 0), (ROCKS, 0)]
        for i in range(14):
            type, fx = pieces[i % len(pieces)]
            self.block(x + i, G - 1, type, fx)
        self.floor_obj(LARGE_ROCKS, x + 15, 3, 2, 378)
        self.floor_obj(FALLEN_LOG, x + 19, 3, 2)
        for i in range(3):
            self.floor_obj(SUNFLOWER, x + 23 + i * 2, 2, 4)
        # The pond: 3 deep.
        self.liquid(x + 31, G, x + 38, G + 2, WATER)
        # The ledge: two grass rows on dirt pillars, vines under it.
        lx = x + 42
        self.box(lx, G - 7, lx + 8, G - 6, GRASS)
        for px in (lx, lx + 8):
            self.box(px, G - 5, px, G - 1, DIRT)
        for px in range(lx + 1, lx + 8):
            n = rng.randint(1, 3)
            for k in range(n):
                self.block(px, G - 5 + k, FLOWER_VINES if rng.random() < 0.25 else VINES)
        self.sign(x + 52, G, "Forest plants: grass, flowers, mushrooms, daybloom, rocks, a fallen log, "
                             "sunflowers, a pond, vines under a ledge. The natural forest is past the ends.")
        return 54

    def _shell(self, x, width, height, door_side):
        """A wooden room on the ground: floor, walls, roof, wood wall inside,
        a door in the `door_side` wall ("left"/"right"). Returns (x0, x1) inside."""
        G = self.G
        top = G - height + 1
        self.box(x, G, x + width - 1, G, WOOD)
        self.box(x, top, x + width - 1, top, WOOD)
        for wx in (x, x + width - 1):
            self.box(wx, top, wx, G - 1, WOOD)
        self.walls(x + 1, top + 1, x + width - 2, G - 1, W_WOOD)
        self.door(x if door_side == "left" else x + width - 1, G)
        return x + 1, x + width - 2

    def house(self, x):
        """A furnished house: clock, sawmill, bed, table with candle, chair,
        barrel, loom, a copper chandelier."""
        G = self.G
        a, b = self._shell(x, 25, 8, "right")
        p = a
        p += self.floor_obj(CLOCK, p, 2, 5) + 1
        p += self.floor_obj(SAWMILL, p, 3, 3) + 1
        p += self.floor_obj(BED, p, 4, 2, 72) + 1
        self.floor_obj(TABLE, p, 3, 2)
        self.block(p + 1, G - 3, CANDLE)
        p += 3
        p += self.floor_obj(CHAIR, p, 1, 2) + 1
        p += self.floor_obj(CHEST, p, 2, 2, 5 * 36)
        self.floor_obj(LOOM, p, 3, 2)
        self.obj(CHANDELIER, (a + b) // 2 - 1, G - 6, 3, 3)
        # Tiki torches by the door, and a sign.
        self.floor_obj(LAMP, x + 25, 1, 3)
        self.floor_obj(LAMP, x + 28, 1, 3)
        self.sign(x + 26, G, "Welcome! House: right-click the bed to set your spawn, the clock tells the time.")
        return 29

    def library(self, x):
        """Bookcases, piano, dresser with a candelabra, trash can, silver
        chandelier, a lamp post outside."""
        G = self.G
        a, b = self._shell(x, 20, 8, "left")
        p = a + 1
        p += self.floor_obj(BOOKCASE, p, 3, 4) + 1
        p += self.floor_obj(PIANO, p, 3, 2) + 1
        p += self.floor_obj(BOOKCASE, p, 3, 4) + 1
        self.floor_obj(DRESSER, p, 3, 2)
        self.obj(CANDELABRA, p, G - 4, 2, 2)
        p += 4
        self.floor_obj(CHEST, p, 2, 2, 6 * 36)
        self.obj(CHANDELIER, (a + b) // 2 - 1, G - 6, 3, 3, 0, 54)
        self.floor_obj(LAMP_POST, x + 21, 1, 6)
        return 22

    def hammered(self, x):
        """Half blocks, a ramp staircase rising east, an arch with upside-down
        ramps in its corners, grass ramps."""
        G = self.G
        y = G - 1
        self.block(x, y, STONE, half=True)
        self.block(x + 1, y, STONE, half=True)
        for i in range(3):
            for k in range(i):
                self.block(x + 3 + i, y - k, STONE)
            self.block(x + 3 + i, y - i, STONE, slope=1)
        self.box(x + 6, y - 2, x + 6, y, STONE)
        self.box(x + 8, y - 2, x + 8, y, STONE)
        self.box(x + 12, y - 2, x + 12, y, STONE)
        self.box(x + 8, y - 3, x + 12, y - 3, STONE)
        self.block(x + 9, y - 2, STONE, slope=4)
        self.block(x + 11, y - 2, STONE, slope=3)
        self.block(x + 14, y, GRASS, slope=1)
        self.block(x + 15, y, GRASS, slope=1)
        self.sign(x + 17, G, "Hammered blocks: hit a block with a hammer for half blocks and ramps.")
        return 19

    def liquids(self, x):
        """The water pool (9 deep) with a stone cliff and a natural waterfall,
        swimming-enemy statues on its floor, hammer springs, a lava pit."""
        G = self.G
        # Pool: brick sides and floor, water G..G+8.
        self.box(x, G, x, G + 9, BRICK)
        self.box(x + 15, G, x + 15, G + 9, BRICK)
        self.box(x, G + 9, x + 15, G + 9, BRICK)
        self.liquid(x + 1, G, x + 14, G + 8, WATER)
        # The cliff in it, with a pocket of water by a half block: a waterfall.
        self.box(x + 1, G - 18, x + 2, G + 8, STONE)
        self.box(x + 3, G - 16, x + 3, G - 16, STONE)
        fy = G - 15
        self.liquid(x + 2, fy, x + 2, fy, WATER)
        self.block(x + 3, fy, STONE, half=True)
        # Statues on the pool floor, each wired (red, blue, green) to a switch
        # east of the pool.
        statues = [x + 5, x + 8, x + 11]
        for i, (style, _) in enumerate(WATER_STATUES):
            sx = statues[i]
            self.obj(STATUE, sx, G + 6, 2, 3, (style % 55) * 36, (style // 55) * 54)
            for dx in range(2):
                for dy in range(3):
                    t = self.t(sx + dx, G + 6 + dy)  # (water fills statues)
                    t.liquid, t.liquid_kind = 255, WATER
        cells = []
        for i, sx in enumerate(statues):
            sw = x + 17 + i * 2
            self.block(sw, G - 1, SWITCH)
            row = G + 3 + i  # each colour its own row: green G+3, blue G+4, red G+5
            col = [(sw, y) for y in range(G - 1, row + 1)]
            run = [(xx, row) for xx in range(sx + 1, sw + 1)]
            down = [(sx + 1, y) for y in range(row, G + 6)]
            cells.append(col + run + down + [(sx + dx, G + 6 + dy) for dx in range(2) for dy in range(3)])
        for i, c in enumerate(cells):
            self.wire(c, [4, 2, 1][i])
        # Hammer springs: a water tank already hammered, a lava tank to try.
        for i, kind in enumerate((WATER, LAVA)):
            cx, cy = x + 25 + i * 5, G - 9
            self.box(cx - 1, cy - 1, cx + 1, cy + 1, BRICK)
            self.liquid(cx, cy, cx, cy, kind)
            if kind == WATER:
                self.block(cx + 1, cy, BRICK, half=True)
        # Lava pit: 3 deep, a brick fence round it, obsidian beside it.
        lx = x + 35
        self.box(lx - 1, G - 1, lx - 1, G + 3, BRICK)
        self.box(lx + 9, G - 1, lx + 9, G + 3, BRICK)
        self.box(lx - 1, G + 3, lx + 9, G + 3, BRICK)
        self.liquid(lx, G, lx + 8, G + 2, LAVA)
        self.box(lx + 11, G - 3, lx + 13, G - 1, OBSIDIAN)
        self.sign(x + 22, G, "Swimmers: each switch here spawns a Shark, a Blue Jellyfish or a Piranha "
                                "(statues on the pool floor).")
        self.sign(x + 32, G, "Hammer springs: hammer a tank's side block. Lava pit and obsidian to the east.")
        return 50

    def dark_room(self, x):
        """A stone room with stone walls inside (no daylight), a door, cobwebs
        in its top corners."""
        G = self.G
        top = G - 10
        self.box(x, top, x + 13, G, STONE)
        for xx in range(x + 1, x + 13):
            for y in range(top + 1, G):
                self.air(xx, y)
        self.walls(x + 1, top + 1, x + 12, G - 1, W_STONE)
        self.door(x + 13, G)
        for cx, dx in ((x + 1, 1), (x + 12, -1)):
            for c in [(cx, top + 1), (cx + dx, top + 1), (cx, top + 2)]:
                self.block(c[0], c[1], COBWEB)
        self.sign(x + 15, G, "Dark room: torches and lighting.")
        return 17

    def storage(self, x):
        """Chests holding every item, by category, on platform shelves: eight
        to a row, named for what's inside."""
        G = self.G
        by_cat = {}
        for name, d in self.items.items():
            t = d.get("type", "")
            cat = "Coins & Misc"
            for c, types in CATEGORIES:
                if t in types:
                    cat = c
            by_cat.setdefault(cat, []).append(name)
        n = 0
        for cat, _ in CATEGORIES:
            names = sorted(by_cat.get(cat, []))
            chunks = [names[i:i + 40] for i in range(0, len(names), 40)]
            for k, chunk in enumerate(chunks):
                row, colm = n // 8, n % 8
                floor = G - row * 4
                if colm == 0 and row > 0:
                    for xx in range(x - 1, x + 25):
                        self.block(xx, floor, PLATFORM)
                cx = x + colm * 3
                self.floor_obj(CHEST, cx, 2, 2, floor=floor)
                c = self.w.chests[-1]
                c.name = cat + ("" if len(chunks) == 1 else " %d/%d" % (k + 1, len(chunks)))
                for i, name in enumerate(chunk):
                    c.items[i] = Item(self.ids["ItemID"][name], self.stack(name), 0)
                n += 1
        self.sign(x + 25, G, "Every item: chests on shelves, named for what's inside (hover a chest).")
        return 27

    def stack(self, name):
        d = self.items[name]
        t = d.get("type", "material")
        default = 1 if t in ["melee", "ranged", "magic", "tool", "accessory", "armor", "tool_use",
                             "fishing_pole"] else 9999
        n = int(d.get("max_stack", default))
        return n - 1 if name in COINS else n

    def plaza(self, x):
        """Gray brick under spawn, crafting stations, torches, the help sign."""
        G = self.G
        self.box(x, G, x + 19, G, BRICK)
        self.torch(x, G - 1)
        self.torch(x + 19, G - 1)
        self.floor_obj(WORKBENCH, x + 2, 2, 1)
        self.floor_obj(FURNACE, x + 5, 3, 2)
        self.floor_obj(ANVIL, x + 9, 2, 1)
        self.sign(x + 16, G, HELP)
        self.w.spawn = (x + 13, G)
        return 20

    def dummies(self, x):
        G = self.G
        self.box(x, G, x + 9, G, BRICK)
        for dx in (2, 6):
            self.floor_obj(DUMMY, x + dx, 2, 3)
            self.w.add_training_dummy(x + dx, G - 3)
        return 10

    def arena(self, x):
        """A brick-walled arena (walls 6 high, a door in the west one), a statue
        and its switch for each land enemy that has a statue."""
        G = self.G
        width = 44
        self.box(x, G, x + width - 1, G, BRICK)
        for wx in (x, x + width - 1):
            self.box(wx, G - 6, wx, G - 1, BRICK)
            self.torch(wx, G - 7)
        self.door(x, G)
        for i, (style, _) in enumerate(LAND_STATUES):
            sx = x + 3 + i * 4
            self.floor_obj(STATUE, sx, 2, 3, (style % 55) * 36, (style // 55) * 54)
            self.block(sx + 2, G - 1, SWITCH)
            self.wire([(sx + dx, G - 3 + dy) for dx in range(2) for dy in range(3)] + [(sx + 2, G - 1)])
        names = ", ".join(n for _, n in LAND_STATUES)
        self.sign(x - 3, G, "Enemy arena: hit a statue's switch to spawn its enemy (statue enemies drop "
                            "nothing). West to east: " + names + ". Swimmers: by the pool. Eye of Cthulhu: "
                            "Suspicious Looking Eye at night (Potions chest).")
        return width

    def town(self, x):
        """Six houses in a row, sharing walls, doors in every wall; each with a
        table, candle and chair, and a resident (set_town_npcs)."""
        G = self.G
        top = G - 7
        n = len(TOWN)
        width = n * 12 + 1
        self.box(x, G, x + width - 1, G, WOOD)
        self.box(x, top, x + width - 1, top, WOOD)
        self.homes = []
        for i in range(n + 1):
            wx = x + i * 12
            self.box(wx, top, wx, G - 1, WOOD)
            self.door(wx, G)
        for i in range(n):
            a = x + i * 12 + 1
            self.walls(a, top + 1, a + 10, G - 1, W_WOOD)
            self.floor_obj(TABLE, a + 5, 3, 2)
            self.block(a + 6, G - 3, CANDLE)
            self.floor_obj(CHAIR, a + 4, 1, 2, 18)
            self.homes.append((a + 2, G))
        self.sign(x - 3, G, "Town: the Guide, Merchant, Nurse, Arms Dealer, Dryad and Demolitionist "
                            "(right-click to talk).")
        return width

    def set_town_npcs(self):
        names = self.ids["names"]["town"]
        self.w.town_npcs = [n for n in self.w.town_npcs if n.id not in [t[0] for t in TOWN]]
        for (id, key), (hx, hy) in zip(TOWN, self.homes):
            self.w.town_npcs.append(TownNPC(id, names[key][0], hx * 16.0, hy * 16.0 - 40, False, (hx, hy)))

    def tower(self, x):
        """Fall test: a platform ladder up to a deck 37 tiles (25 blocks) up;
        off its west end the ground, off its east end a water pool."""
        G = self.G
        top = G - 37
        for y in range(G - 4, top, -4):
            for xx in range(x + 5, x + 8):
                self.block(xx, y, PLATFORM)
        for xx in range(x + 1, x + 14):
            self.block(xx, top, PLATFORM)
        self.box(x + 13, G, x + 13, G + 7, BRICK)
        self.box(x + 20, G, x + 20, G + 7, BRICK)
        self.box(x + 13, G + 7, x + 20, G + 7, BRICK)
        self.liquid(x + 14, G, x + 19, G + 6, WATER)
        self.sign(x + 1, G, "Fall test: climb the platforms. Off the top's west end is the ground "
                            "(37 tiles down), off its east end water.")
        return 21

    def platforms(self, x):
        """Wooden platform stairs up to a platform floor."""
        G = self.G
        for i in range(4):
            self.block(x + i, G - 1 - i, PLATFORM, slope=1)
        for xx in range(x + 4, x + 12):
            self.block(xx, G - 5, PLATFORM)
        return 13

    # -- the gallery

    def gallery_entries(self):
        """[(name, kind, type, w, h, fx, fy)] for each gallery block (not hidden,
        not the Bast Statue, like TestWorld.gallery_blocks), once per look."""
        out, seen = [], set()
        imp = self.w.important
        for b in self.blocks:
            name = b["name"]
            if b.get("hidden") or "near_buff" in b or name in ("npc_spawner", "wall_torch", "tree_trunk",
                                                                 "lily_pad", "cattail", "sunplate_trim"):
                continue
            tex = b.get("tex") or {}
            face = tex.get("all") or tex.get("side") or tex.get("top")
            if not isinstance(face, dict) or "sheet" not in face:
                continue
            sheet = face["sheet"]
            num = int(sheet.split("_")[1])
            fx, fy = (face.get("frames") or [[0, 0]])[0]
            if sheet.startswith("Wall_"):
                entry = (name, "wall", num, 3, 4, 0, 0)
            elif num == 11:  # open-door sheet: the closed door (tile 10) of the same style
                style = fy // 54 + 36 * (fx // 72)
                entry = (name, "door", DOOR, 1, 3, (style // 36) * 54, (style % 36) * 54)
            elif num == PLATFORM:
                entry = (name, "obj", num, 1, 1, 0, fy)
            elif num in (VINES, FLOWER_VINES, 62):
                entry = (name, "vine", num, 1, 2, 0, 0)
            elif num in (124, 574, 575, 577):  # beams
                entry = (name, "solid", num, 1, 3, 0, 0)
            elif not imp[num]:
                entry = (name, "solid", num, 2, 2, 0, 0)
            else:
                w_, h_ = face.get("tiles", [1, 1])
                entry = (name, "hang" if b.get("hangs") or num == 91 else "obj", num, w_, h_, fx, fy)
            look = entry[1:]
            if look in seen:
                continue
            seen.add(look)
            out.append(entry)
        ores = ["copper_ore", "tin_ore", "iron_ore", "lead_ore", "silver_ore", "tungsten_ore", "gold_ore",
                "platinum_ore", "demonite_ore", "crimtane_ore", "hellstone", "obsidian"]
        ore_types = {7: 0, 166: 1, 6: 2, 167: 3, 9: 4, 168: 5, 8: 6, 169: 7, 22: 8, 204: 9, 58: 10, 56: 11}
        for i, t in sorted(ore_types.items(), key=lambda kv: kv[1]):
            out.append((ores[t], "ore", i, 4, 6, 0, 0))
        return out

    def gallery(self, x):
        """Rows of every block on brick floors, 8 tiles apart (platforms at both
        ends to jump up through), gray brick wall behind, torches along the top;
        the ore wall last."""
        G = self.G
        width = min(110, self.right - x - 2)
        entries = self.gallery_entries()
        rows, row, cur = [], [], 5
        for e in entries:
            if e[1] == "ore" and row and row[0][1] != "ore":
                rows.append(row)
                row, cur = [], 5
            w_ = e[3]
            if cur + w_ > width - 5:
                rows.append(row)
                row, cur = [], 5
            row.append(e + (cur,))
            cur += w_ + 2
        if row:
            rows.append(row)
        top = G - 8 * len(rows)
        print("  gallery: %d wide, %d rows, %d blocks" % (width, len(rows), len(entries)))
        self.box(x, top, x, G, BRICK)
        self.box(x + width - 1, top, x + width - 1, G, BRICK)
        self.walls(x + 1, top + 1, x + width - 2, G - 1, W_BRICK)
        for r in range(len(rows) + 1):
            fl = G - 8 * r
            self.box(x, fl, x + width - 1, fl, BRICK)
            if 0 < r < len(rows):
                for xx in list(range(x + 1, x + 4)) + list(range(x + width - 4, x + width - 1)):
                    self.block(xx, fl, PLATFORM)
        self.door(x, G)
        for r, items in enumerate(rows):
            fl = G - 8 * r
            ceil = fl - 8
            for name, kind, type, w_, h_, fx, fy, off in items:
                px = x + off
                if kind == "wall":
                    self.walls(px, fl - h_, px + w_ - 1, fl - 1, type)
                elif kind == "solid" or kind == "ore":
                    self.box(px, fl - h_, px + w_ - 1, fl - 1, type)
                elif kind == "door":
                    self.door(px, fl)
                    for dy in range(3):
                        t = self.t(px, fl - 3 + dy)
                        t.fx, t.fy = fx, fy + dy * 18
                    self.block(px, fl - 4, BRICK)
                elif kind == "vine":
                    self.block(px, ceil, JUNGLE_GRASS if type == 62 else GRASS)
                    for dy in range(h_):
                        self.block(px, ceil + 1 + dy, type)
                elif kind == "hang":
                    self.obj(type, px, ceil + 1, w_, h_, fx, fy)
                else:
                    ground = {PLANTS: GRASS, TALL_PLANTS: GRASS, DAYBLOOM: GRASS, 24: CORRUPT_GRASS,
                              201: CRIMSON_GRASS, 61: JUNGLE_GRASS}.get(type)
                    if ground is not None:
                        self.block(px, fl, ground)
                    self.obj(type, px, fl - h_, w_, h_, fx, fy)
                    if type in SIGNS:
                        self.w.signs.append([px, fl - h_, name.replace("_", " ")])
            # Torches on the back wall along the top, where it's free.
            for tx in range(x + 2, x + width - 2, 9):
                if not any(self.t(tx, ceil + 1 + k).active for k in range(3)):
                    self.torch(tx, ceil + 1, on_wall=True)
        self.sign(x - 3, G, "One of every block (rows going up; jump through the platforms at the ends). "
                            "Ore wall in the top row.")
        return width


HELP = ("TEST WORLD (3D comparison). West: garden, house, library, hammered blocks, liquids, dark room, "
        "every item in chests. Here: crafting. East: target dummies, enemy arena, town, fall-test tower, "
        "platforms, block gallery. Snow, desert, jungle, the evil biome, the Dungeon, floating islands and "
        "cabins are the world generator's. Journey powers stand in for the test world's debug keys "
        "(god mode, time, spawn rate).")


def set_enemy_strength(w, value):
    """Journey's enemy strength slider (creative power 12) in the saved powers."""
    p = w.pointers
    base = p[6]
    raw = bytearray(w.raw_after_entities)
    i = p[9] - base
    while raw[i]:
        pid = raw[i + 1] | raw[i + 2] << 8
        if pid in (8, 12):  # sliders: a float
            if pid == 12:
                import struct
                struct.pack_into("<f", raw, i + 3, value)
            i += 7
        else:
            i += 4
    w.raw_after_entities = bytes(raw)


PLANT_TILES = {3, 5, 20, 24, 27, 28, 61, 72, 73, 74, 82, 83, 84, 185, 186, 187, 201, 233, 323, 324}


def surface(w, x):
    """The first ground (or liquid) row in column x, below the floating islands."""
    col = w.column(x)
    for y in range(int(w.surface) - 200, int(w.rock)):
        t = col[y]
        if (t.active and t.type not in PLANT_TILES) or t.liquid:
            return y
    return int(w.surface)


def flattest_strip(w):
    """A strip centre near spawn where the ground strays least from one level,
    and that level (the median ground row)."""
    sx = w.spawn[0]
    tops = {x: surface(w, x) for x in range(sx - 200 - STRIP // 2, sx + 200 + STRIP // 2, 5)}
    best = None
    for c in range(sx - 200, sx + 201, 10):
        ys = sorted(tops[x] for x in tops if abs(x - c) <= STRIP // 2)
        g = ys[len(ys) // 2]
        cost = sum(abs(y - g) for y in ys)
        if best is None or cost < best[0]:
            best = (cost, c, g)
    return best[1], best[2]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    w = World.load(sys.argv[1])
    if len(sys.argv) > 3:
        w.name = sys.argv[3]
    b = Builder(w)
    center, G = flattest_strip(w)
    left, right = b.build(center, G)
    set_enemy_strength(w, 0.33)
    w.save(sys.argv[2])
    print("built %d..%d (ground %d), spawn %s, %d chests, %d town NPCs" %
          (left, right, G, w.spawn, len(w.chests), len(w.town_npcs)))


if __name__ == "__main__":
    main()
