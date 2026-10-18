#!/usr/bin/env python3
"""Reads and writes Terraria 1.4.5 world files (.wld, version 326), as
Terraria.IO.WorldFile saves them: tiles, chests, signs, town NPCs and tile
entities are decoded; every other section is kept as it was.

    w = World.load("template.wld")
    t = w.tile(x, y)            # a Tile you can change (columns decode on use)
    w.save("out.wld")
"""
import struct

VERSION = 326
SECTIONS = ["format", "header", "tiles", "chests", "signs", "npcs", "entities",
            "pressure_plates", "town", "bestiary", "creative", "footer"]

# Liquid kinds (Tile.liquid_kind).
WATER, LAVA, HONEY, SHIMMER = 1, 2, 3, 4


class Reader:
    def __init__(self, data, pos=0):
        self.d = data
        self.p = pos

    def take(self, fmt):
        v = struct.unpack_from("<" + fmt, self.d, self.p)
        self.p += struct.calcsize("<" + fmt)
        return v[0] if len(v) == 1 else v

    def string(self):
        n = shift = 0
        while True:
            b = self.d[self.p]
            self.p += 1
            n |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                break
        s = self.d[self.p:self.p + n].decode("utf-8")
        self.p += n
        return s


def pack_string(s):
    b = s.encode("utf-8")
    n = len(b)
    out = bytearray()
    while True:
        if n < 0x80:
            out.append(n)
            break
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out) + b


class Tile:
    """One cell: a block (`active`, `type`, frames), a background `wall`,
    liquid, wires and paint, as Terraria's Tile holds them."""
    __slots__ = ("active", "type", "fx", "fy", "color", "wall", "wall_color", "liquid", "liquid_kind",
                 "wires", "slope", "half", "actuator", "inactive", "invisible_block", "invisible_wall",
                 "fullbright_block", "fullbright_wall")

    def __init__(self):
        self.clear()

    def clear(self):
        self.active = False
        self.type = 0
        self.fx = self.fy = 0
        self.color = 0
        self.wall = 0
        self.wall_color = 0
        self.liquid = 0
        self.liquid_kind = 0
        self.wires = 0  # bits: 1 red, 2 blue, 4 green, 8 yellow
        self.slope = 0  # 0 none, 1-4 the four ramps
        self.half = False
        self.actuator = self.inactive = False
        self.invisible_block = self.invisible_wall = False
        self.fullbright_block = self.fullbright_wall = False

    def clear_block(self):
        self.active = False
        self.type = self.fx = self.fy = self.color = 0
        self.slope = 0
        self.half = self.actuator = self.inactive = False

    def copy(self):
        t = Tile()
        for k in Tile.__slots__:
            setattr(t, k, getattr(self, k))
        return t

    def key(self):
        return tuple(getattr(self, k) for k in Tile.__slots__)


def decode_tile(r, important):
    """One tile record (SaveWorldTiles); returns (tile, run) where `run` more
    identical tiles follow."""
    d = r.d
    h1 = d[r.p]; r.p += 1
    h2 = h3 = h4 = 0
    if h1 & 1:
        h2 = d[r.p]; r.p += 1
        if h2 & 1:
            h3 = d[r.p]; r.p += 1
            if h3 & 1:
                h4 = d[r.p]; r.p += 1
    t = Tile()
    if h1 & 2:
        t.active = True
        if h1 & 0x20:
            t.type = d[r.p] | d[r.p + 1] << 8; r.p += 2
        else:
            t.type = d[r.p]; r.p += 1
        if important[t.type]:
            t.fx, t.fy = struct.unpack_from("<HH", d, r.p); r.p += 4
        if h3 & 8:
            t.color = d[r.p]; r.p += 1
    if h1 & 4:
        t.wall = d[r.p]; r.p += 1
        if h3 & 0x10:
            t.wall_color = d[r.p]; r.p += 1
    lq = (h1 >> 3) & 3
    if lq:
        t.liquid_kind = SHIMMER if h3 & 0x80 else lq
        t.liquid = d[r.p]; r.p += 1
    if h3 & 0x40:
        t.wall |= d[r.p] << 8; r.p += 1
    t.wires = ((h2 >> 1) & 7) | (8 if h3 & 0x20 else 0)
    s = (h2 >> 4) & 7
    if s == 1:
        t.half = True
    elif s > 1:
        t.slope = s - 1
    t.actuator = bool(h3 & 2)
    t.inactive = bool(h3 & 4)
    t.invisible_block = bool(h4 & 2)
    t.invisible_wall = bool(h4 & 4)
    t.fullbright_block = bool(h4 & 8)
    t.fullbright_wall = bool(h4 & 0x10)
    run = 0
    rle = h1 >> 6
    if rle == 1:
        run = d[r.p]; r.p += 1
    elif rle == 2:
        run = d[r.p] | d[r.p + 1] << 8; r.p += 2
    return t, run


def encode_tile(t, important, run):
    h1 = h2 = h3 = h4 = 0
    body = bytearray()
    if t.active:
        h1 |= 2
        if t.type > 255:
            h1 |= 0x20
            body += struct.pack("<H", t.type)
        else:
            body.append(t.type)
        if important[t.type]:
            body += struct.pack("<HH", t.fx, t.fy)
        if t.color:
            h3 |= 8
            body.append(t.color)
    if t.wall:
        h1 |= 4
        body.append(t.wall & 0xFF)
        if t.wall_color:
            h3 |= 0x10
            body.append(t.wall_color)
    if t.liquid and t.liquid_kind:
        if t.liquid_kind == SHIMMER:
            h3 |= 0x80
            h1 |= 8
        else:
            h1 |= t.liquid_kind << 3
        body.append(t.liquid)
    if t.wall > 255:
        h3 |= 0x40
        body.append(t.wall >> 8)
    h2 |= (t.wires & 7) << 1
    if t.wires & 8:
        h3 |= 0x20
    if t.active and t.half:
        h2 |= 1 << 4
    elif t.active and t.slope:
        h2 |= (t.slope + 1) << 4
    if t.actuator:
        h3 |= 2
    if t.inactive:
        h3 |= 4
    h4 |= (2 if t.invisible_block else 0) | (4 if t.invisible_wall else 0) | \
        (8 if t.fullbright_block else 0) | (0x10 if t.fullbright_wall else 0)
    if h4:
        h3 |= 1
    if h3:
        h2 |= 1
    if h2:
        h1 |= 1
    if run > 255:
        h1 |= 0x80
        body += struct.pack("<H", run)
    elif run > 0:
        h1 |= 0x40
        body.append(run)
    head = bytearray([h1])
    if h1 & 1:
        head.append(h2)
        if h2 & 1:
            head.append(h3)
            if h3 & 1:
                head.append(h4)
    return bytes(head + body)


class Item:
    __slots__ = ("id", "stack", "prefix")

    def __init__(self, id=0, stack=0, prefix=0):
        self.id, self.stack, self.prefix = id, stack, prefix


class Chest:
    def __init__(self, x, y, name="", size=40):
        self.x, self.y, self.name = x, y, name
        self.items = [Item() for _ in range(size)]


class TownNPC:
    def __init__(self, id, name, x, y, homeless=False, home=(0, 0), variation=0, homeless_despawn=False):
        self.id, self.name, self.x, self.y = id, name, x, y
        self.homeless, self.home = homeless, home
        self.variation, self.homeless_despawn = variation, homeless_despawn


class World:
    @staticmethod
    def load(path):
        w = World()
        w.data = open(path, "rb").read()
        w._parse()
        return w

    def _parse(self):
        r = Reader(self.data)
        self.version = r.take("i")
        if self.version != VERSION:
            raise ValueError("world version %d, expected %d" % (self.version, VERSION))
        self.metadata = self.data[4:24]
        r.p = 24
        n = r.take("h")
        self.pointers = [r.take("i") for _ in range(n)]
        count = r.take("h")
        bits = []
        b = 0
        for i in range(count):
            if i % 8 == 0:
                b = r.take("B")
            bits.append(bool(b & (1 << (i % 8))))
        self.important = bits
        # Header: the fields we touch, then the rest kept raw.
        p = self.pointers
        hr = Reader(self.data, p[0])
        self.name = hr.string()
        self.seed = hr.string()
        self.header_mid_start = hr.p
        hr.take("Q")  # generator version
        hr.p += 16  # guid
        hr.take("i")  # world id
        hr.p += 16  # left, right, top, bottom
        self.height = hr.take("i")
        self.width = hr.take("i")
        self.game_mode = hr.take("i")
        hr.p += 9  # 9 world-seed flags (drunk .. skyblock)
        hr.p += 16  # creation time, last played
        hr.p += 1  # moon type
        hr.p += 4 * (3 + 4 + 3 + 4 + 3)
        self.spawn_pos = hr.p
        self.spawn = (struct.unpack_from("<i", self.data, hr.p)[0], struct.unpack_from("<i", self.data, hr.p + 4)[0])
        self.surface, self.rock = struct.unpack_from("<dd", self.data, hr.p + 8)
        self.game_mode_pos = self.spawn_pos - 4 * 17 - 1 - 16 - 9 - 4
        self.header_raw = bytearray(self.data[self.header_mid_start:p[1]])
        # Tiles: remember where each column starts; decode on demand.
        self._columns = {}
        self._col_start = []
        tr = Reader(self.data, p[1])
        for x in range(self.width):
            self._col_start.append(tr.p)
            y = 0
            while y < self.height:
                _, run = decode_tile(tr, self.important)
                y += 1 + run
        assert tr.p == p[2], "tile section length mismatch"
        self._parse_chests(Reader(self.data, p[2]))
        self._parse_signs(Reader(self.data, p[3]))
        self._parse_npcs(Reader(self.data, p[4]), p[5])
        self._parse_entities(Reader(self.data, p[5]), p[6])
        self.raw_after_entities = self.data[p[6]:p[10]]  # pressure plates .. creative powers
        self.footer = self.data[p[10]:]

    # -- tiles

    def column(self, x):
        col = self._columns.get(x)
        if col is None:
            col = []
            r = Reader(self.data, self._col_start[x])
            while len(col) < self.height:
                t, run = decode_tile(r, self.important)
                col.append(t)
                for _ in range(run):
                    col.append(t.copy())
            self._columns[x] = col
        return col

    def tile(self, x, y):
        return self.column(x)[y]

    def _column_bytes(self, x):
        if x not in self._columns:
            end = self._col_start[x + 1] if x + 1 < self.width else self.pointers[2]
            return self.data[self._col_start[x]:end]
        col = self._columns[x]
        out = bytearray()
        y = 0
        while y < self.height:
            t = col[y]
            k = t.key()
            run = 0
            # Batch identical tiles (not furniture: its frames differ per tile anyway).
            if not (t.active and self.important[t.type]):
                while y + run + 1 < self.height and run < 0xFFFF and col[y + run + 1].key() == k:
                    run += 1
            out += encode_tile(t, self.important, run)
            y += run + 1
        return bytes(out)

    # -- chests, signs, NPCs, tile entities

    def _parse_chests(self, r):
        n = r.take("h")
        self.chests = []
        for _ in range(n):
            x, y = r.take("i"), r.take("i")
            c = Chest(x, y, r.string(), r.take("i"))
            for it in c.items:
                it.stack = r.take("h")
                if it.stack > 0:
                    it.id, it.prefix = r.take("i"), r.take("B")
            self.chests.append(c)

    def _chests_bytes(self):
        out = bytearray(struct.pack("<h", len(self.chests)))
        for c in self.chests:
            out += struct.pack("<ii", c.x, c.y) + pack_string(c.name) + struct.pack("<i", len(c.items))
            for it in c.items:
                if it.stack > 0 and it.id > 0:
                    out += struct.pack("<hiB", it.stack, it.id, it.prefix)
                else:
                    out += struct.pack("<h", 0)
        return bytes(out)

    def _parse_signs(self, r):
        n = r.take("h")
        self.signs = []
        for _ in range(n):
            text = r.string()
            self.signs.append([r.take("i"), r.take("i"), text])

    def _signs_bytes(self):
        out = bytearray(struct.pack("<h", len(self.signs)))
        for x, y, text in self.signs:
            out += pack_string(text) + struct.pack("<ii", x, y)
        return bytes(out)

    def _parse_npcs(self, r, end):
        n = r.take("i")
        self.shimmered = [r.take("i") for _ in range(n)]
        self.town_npcs = []
        while r.take("?"):
            id = r.take("i")
            name = r.string()
            x, y = r.take("f"), r.take("f")
            homeless = r.take("?")
            home = (r.take("i"), r.take("i"))
            bits = r.take("B")
            variation = r.take("i") if bits & 1 else 0
            despawn = r.take("?")
            self.town_npcs.append(TownNPC(id, name, x, y, homeless, home, variation, despawn))
        self.npcs_rest = self.data[r.p:end]  # the other saved NPCs (pillars and such)

    def _npcs_bytes(self):
        out = bytearray(struct.pack("<i", len(self.shimmered)))
        for s in self.shimmered:
            out += struct.pack("<i", s)
        for n in self.town_npcs:
            out += struct.pack("<?i", True, n.id) + pack_string(n.name)
            out += struct.pack("<ff?ii", n.x, n.y, n.homeless, n.home[0], n.home[1])
            out += struct.pack("<Bi?", 1, n.variation, n.homeless_despawn)
        out += struct.pack("<?", False)
        return bytes(out) + self.npcs_rest

    def _parse_entities(self, r, end):
        n = r.take("i")
        self.entities = []  # [type, id, x, y, raw extra bytes]
        starts = []
        for _ in range(n):
            start = r.p
            kind, id, x, y = r.take("B"), r.take("i"), r.take("h"), r.take("h")
            starts.append((start, kind, id, x, y, r.p))
            # Each kind's extra data has its own length; find it by the next
            # entry's start (entries are contiguous), the last by the section end.
            r.p = self._entity_end(kind, r.p)
        for i, (start, kind, id, x, y, extra) in enumerate(starts):
            stop = starts[i + 1][0] if i + 1 < len(starts) else end
            self.entities.append([kind, id, x, y, self.data[extra:stop]])

    def _entity_end(self, kind, p):
        r = Reader(self.data, p)
        if kind == 0:  # training dummy: npc
            r.take("h")
        elif kind in (1, 4, 6):  # item frame, weapons rack, food platter: item
            r.take("h"); r.take("B"); r.take("h")
        elif kind == 2:  # logic sensor: type, on
            r.take("B"); r.take("?")
        elif kind == 3:  # display doll: items, dyes, pose...
            raise ValueError("display dolls not supported")
        elif kind == 5:  # hat rack
            raise ValueError("hat racks not supported")
        elif kind == 7:  # pylon
            pass
        else:
            raise ValueError("tile entity kind %d" % kind)
        return r.p

    def _entities_bytes(self):
        out = bytearray(struct.pack("<i", len(self.entities)))
        for kind, id, x, y, extra in self.entities:
            out += struct.pack("<Bihh", kind, id, x, y) + extra
        return bytes(out)

    def add_training_dummy(self, x, y):
        nid = max([e[1] for e in self.entities], default=-1) + 1
        self.entities.append([0, nid, x, y, struct.pack("<h", -1)])

    # -- saving

    def save(self, path):
        hdr = bytearray(self.header_raw)
        rel = self.spawn_pos - self.header_mid_start
        struct.pack_into("<iidd", hdr, rel, self.spawn[0], self.spawn[1], self.surface, self.rock)
        struct.pack_into("<i", hdr, self.game_mode_pos - self.header_mid_start, self.game_mode)
        header = pack_string(self.name) + pack_string(self.seed) + bytes(hdr)
        tiles = b"".join(self._column_bytes(x) for x in range(self.width))
        parts = [header, tiles, self._chests_bytes(), self._signs_bytes(), self._npcs_bytes(),
                 self._entities_bytes(), self.raw_after_entities]
        # The format header: version, metadata, section pointers, frame-important bits.
        bits = bytearray()
        for i in range(0, len(self.important), 8):
            b = 0
            for j in range(8):
                if i + j < len(self.important) and self.important[i + j]:
                    b |= 1 << j
            bits.append(b)
        fmt_len = 4 + 20 + 2 + 4 * len(self.pointers) + 2 + len(bits)
        pointers = [fmt_len]
        pos = fmt_len
        for part in parts:
            pos += len(part)
            pointers.append(pos)
        raw_split = self._split_raw_after(pointers)
        fmt = struct.pack("<i", self.version) + self.metadata + struct.pack("<h", len(self.pointers))
        fmt += b"".join(struct.pack("<i", q) for q in raw_split)
        fmt += struct.pack("<h", len(self.important)) + bytes(bits)
        with open(path, "wb") as f:
            f.write(fmt + b"".join(parts) + self.footer_bytes())

    def _split_raw_after(self, pointers):
        # pointers so far: format end (=header start), tiles, chests, signs, npcs,
        # entities, pressure plates start; the kept raw sections keep their sizes.
        old = self.pointers
        out = list(pointers[:7])
        base = out[6]
        for i in range(7, len(old)):
            out.append(base + (old[i] - old[6]))
        return out

    def footer_bytes(self):
        return struct.pack("<?", True) + pack_string(self.name) + self.footer[1 + len(pack_string(self._old_name())):]

    def _old_name(self):
        return Reader(self.data, self.pointers[0]).string()
