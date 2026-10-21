#!/usr/bin/env python3
"""Draws the project's logo: "TERRARIA 3D" in pixel letters built of
isometric pixel-art blocks, grassy dirt for the name and gold for the "3D",
standing round the corner of a floating grass island. Writes a PNG (no
libraries needed).

usage: python3 -I make_logo.py <out.png> [scale]

Each lit glyph pixel is a column of blocks DEPTH deep. "TERRARIA" runs along
the x axis (down and right on screen) and reads on the blocks' left faces;
"3D" turns the corner, running along -z (up and right) and reading on their
right faces. Glyph rows go up y. A block is
a 16 x 20 sprite: a 2:1 diamond on top, a left and a right face below it.
Blocks are painted far to near (x + z, then y), each face pixel by pixel with
a little noise; each letter gets a dark rim where it meets anything else,
the whole art a dark outline, and it's scaled up by whole pixels.
"""
import random
import struct
import sys
import zlib

GLYPHS = {
    "T": ["######", "######", "..##..", "..##..", "..##..", "..##..", "..##.."],
    "E": ["######", "##....", "##....", "#####.", "##....", "##....", "######"],
    "R": ["#####.", "##..##", "##..##", "#####.", "##.##.", "##..##", "##..##"],
    "A": [".####.", "##..##", "##..##", "######", "##..##", "##..##", "##..##"],
    "I": ["####", ".##.", ".##.", ".##.", ".##.", ".##.", "####"],
    "3": ["#####.", "....##", "....##", ".####.", "....##", "....##", "#####."],
    "D": ["#####.", "##..##", "##..##", "##..##", "##..##", "##..##", "#####."],
}
W = 16       # a block's width on screen; its diamond is W x W/2
V = 12       # a block's vertical edge (taller than a cube: bigger letter faces)
DEPTH = 1    # blocks deep
GAP = 1      # columns between letters
OUTLINE = (26, 18, 12)

# Materials: (top, left, right) base colours.
DIRT = ((150, 96, 56), (186, 122, 72), (110, 66, 36))
STONE = ((132, 132, 140), (164, 164, 172), (92, 92, 100))
GRASS = ((84, 176, 58), (104, 204, 72), (52, 128, 38))
GOLD = ((255, 226, 112), (238, 180, 50), (170, 112, 22))
FLOWERS = [(236, 72, 96), (250, 220, 70), (176, 116, 244), (250, 250, 250)]


def glyphs(text):
    """Lit pixels as [(column, row from the top, letter index)], and the width."""
    cells = []
    x = 0
    for n, ch in enumerate(text):
        g = GLYPHS[ch]
        for y, row in enumerate(g):
            for i, c in enumerate(row):
                if c == "#":
                    cells.append((x + i, y, n))
        x += len(g[0]) + GAP
    return cells, x - GAP


def sprite():
    """The block's pixels relative to its top corner: {(px, py): (face, edge)},
    face 0 top, 1 left, 2 right; edge flags the face's border pixels."""
    px = {}
    half = W // 2
    q = W // 4
    for py in range(half):  # the diamond
        r = py if py < q else half - 1 - py
        span = (r + 1) * 2
        for x in range(half - span, half + span):
            px[(x, py)] = (0, py in (0, half - 1) or x in (half - span, half + span - 1))
    for x in range(W):  # the sides, under the diamond's lower edges
        low = q + (x // 2 if x < half else (W - 1 - x) // 2)
        face = 1 if x < half else 2
        for py in range(low + 1, low + 1 + V):
            edge = py == low + V or x in (0, W - 1, half - 1, half)
            px[(x, py)] = (face, edge)
    return px


def write_png(path, img, w, h, scale):
    rows = []
    for y in range(h * scale):
        row = bytearray([0])
        for x in range(w * scale):
            c = img.get((x // scale, y // scale))
            row += bytes(c + (255,)) if c else b"\0\0\0\0"
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main(out, scale):
    rng = random.Random(5)
    rows = 7
    blocks = {}  # (x, y, z) -> (material, owner: 0 the island, else a letter)
    word, width = glyphs("TERRARIA")
    for (c, r, n) in word:
        for z in range(DEPTH):
            blocks[(c, rows - 1 - r, z)] = ("dirt", n + 1)
    # "3D" round the corner: its columns go along -z, its depth along x.
    digits, dwidth = glyphs("3D")
    x0 = width + 2
    for (c, r, n) in digits:
        for d in range(DEPTH):
            blocks[(x0 + d, rows - 1 - r, DEPTH - 1 - c)] = ("gold", 20 + n)
    # The island under both: grass on top, its underside narrowing a ring a
    # layer, with now and then a block hanging lower.
    ground = set()
    for x in range(-2, x0 + DEPTH + 2):
        for z in range(-2, DEPTH + 2):
            ground.add((x, z))
    for x in range(x0 - 2, x0 + DEPTH + 2):
        for z in range(DEPTH - dwidth - 2, DEPTH + 2):
            ground.add((x, z))
    for (x, z) in ground:
        edge = 0
        while all((x + dx, z + dz) in ground for dx in range(-edge - 1, edge + 2) for dz in range(-edge - 1, edge + 2)):
            edge += 1
        blocks[(x, -1, z)] = ("dirt", 0)
        for d in range(2, 3 + edge + (1 if rng.random() < 0.25 else 0)):
            blocks[(x, -d, z)] = ("dirt", 0)
    stones = {k for k, (m, o) in blocks.items() if o == 0 and k[1] < -1 and rng.random() < 0.15}
    spr = sprite()
    img = {}
    owner = {}

    def put(x, y, c, o):
        img[(x, y)] = tuple(max(0, min(255, int(v))) for v in c)
        owner[(x, y)] = o

    for (x, y, z) in sorted(blocks, key=lambda b: (b[0] + b[2], b[1], b[0])):
        m, o = blocks[(x, y, z)]
        ox = (x - z) * (W // 2)
        oy = (x + z) * (W // 4) - y * V
        open_top = (x, y + 1, z) not in blocks
        if m == "gold":
            mat = GOLD
        elif (x, y, z) in stones:
            mat = STONE
        else:
            mat = DIRT
        grass = m == "dirt" and open_top and (x, y, z) not in stones
        tone = rng.uniform(-8, 8)
        fringe = [rng.choice((2, 3, 3, 4)) for _ in range(W)]
        for (sx, sy), (face, edge) in spr.items():
            base = mat[face]
            low = W // 4 + (sx // 2 if sx < W // 2 else (W - 1 - sx) // 2)
            if grass and (face == 0 or sy - low <= fringe[sx]):
                base = GRASS[face]
            n = rng.uniform(-10, 10) + tone
            c = tuple(v + n for v in base)
            if edge:
                c = tuple(v * (0.82 if face else 0.9) for v in c)
            if m == "gold" and face and (sx % 8, sy - low) in ((2, 2), (3, 2), (2, 3), (4, 2)):
                c = (255, 250, 210)
            put(ox + sx, oy + sy, c, o)
        if grass and rng.random() < 0.3:
            # A tuft (and now and then a flower) on the top.
            tx, ty = ox + rng.randint(4, W - 5), oy + rng.randint(2, W // 2 - 3)
            g = tuple(v + rng.uniform(-10, 10) for v in GRASS[0])
            for dx, hgt in ((-1, 2), (0, 3), (1, 2)):
                for k in range(1, hgt + 1):
                    put(tx + dx, ty - k, g if k < hgt else tuple(v * 1.1 for v in g), o)
            if rng.random() < 0.3:
                put(tx, ty - 4, rng.choice(FLOWERS), o)
    # A letter's rim: its pixels next to anything that isn't that letter.
    rim = []
    for p, o in owner.items():
        if o and any(owner.get((p[0] + dx, p[1] + dy)) not in (o, None) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            rim.append(p)
    for p in rim:
        img[p] = OUTLINE
    # Outline: background pixels touching the art.
    art = set(img)
    for (x, y) in art:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in art:
                img[p] = OUTLINE
    xs = [p[0] for p in img]
    ys = [p[1] for p in img]
    pad = 2
    shifted = {(x - min(xs) + pad, y - min(ys) + pad): c for (x, y), c in img.items()}
    write_png(out, shifted, max(xs) - min(xs) + 1 + pad * 2, max(ys) - min(ys) + 1 + pad * 2, scale)


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 2)
