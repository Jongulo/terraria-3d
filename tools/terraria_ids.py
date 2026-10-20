#!/usr/bin/env python3
"""Extracts ID constants (ItemID, NPCID, TileID, ...) and English names from
Terraria.exe's .NET metadata and embedded localization JSON.

usage: python3 -I terraria_ids.py <Terraria.exe> <out.json>

Writes {"ItemID": {"CopperShortsword": 3507, ...}, ..., "ArmorHead": {"CopperHelmet": 1, ...},
"names": {"items": {internal: english}, "tooltips": {...}, "set_bonuses": {...}, "prefixes": {PrefixID name: english},
"town": {"GuideNames": [...], "LegacyDialog": {...}, "TownNPCHousingFailureReasons": {...}, ...}, ...}}
"""
import json
import re
import struct
import sys

ID_CLASSES = ["ItemID", "NPCID", "TileID", "WallID", "ProjectileID", "BuffID", "MusicID", "DustID", "AmmoID", "PrefixID"]
# Nested classes of ArmorIDs (equip sprite numbers: Armor_Head_N, Armor/Armor_N, Armor_Legs_N).
ARMOR_CLASSES = {"Head": "ArmorHead", "Body": "ArmorBody", "Legs": "ArmorLegs"}


class PE:
    def __init__(self, data):
        self.d = data
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        nsec = struct.unpack_from("<H", data, pe + 6)[0]
        opt_size = struct.unpack_from("<H", data, pe + 20)[0]
        opt = pe + 24
        magic = struct.unpack_from("<H", data, opt)[0]
        dd = opt + (96 if magic == 0x10B else 112)
        self.cli_rva = struct.unpack_from("<I", data, dd + 14 * 8)[0]
        self.sections = []
        sec = opt + opt_size
        for i in range(nsec):
            vsize, va, rsize, raw = struct.unpack_from("<IIII", data, sec + i * 40 + 8)
            self.sections.append((va, max(vsize, rsize), raw))

    def off(self, rva):
        for va, size, raw in self.sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError("rva not mapped")


def read_metadata(data):
    pe = PE(data)
    cli = pe.off(pe.cli_rva)
    md_rva = struct.unpack_from("<I", data, cli + 8)[0]
    md = pe.off(md_rva)
    ver_len = struct.unpack_from("<I", data, md + 12)[0]
    p = md + 16 + ver_len + 2
    nstreams = struct.unpack_from("<H", data, p)[0]
    p += 2
    streams = {}
    for _ in range(nstreams):
        off, size = struct.unpack_from("<II", data, p)
        p += 8
        end = data.index(b"\0", p)
        name = data[p:end].decode()
        p = (end + 4) & ~3
        streams[name] = (md + off, size)
    return streams


# Column kinds: 2/4 fixed ints, 's' string, 'g' guid, 'b' blob, ('t', table), ('c', tag_bits, [tables])
TDOR = ("c", 2, [0x02, 0x01, 0x1B])
SCHEMAS = {
    0x00: [2, "s", "g", "g", "g"],
    0x01: [("c", 2, [0x00, 0x1A, 0x23, 0x01]), "s", "s"],
    0x02: [4, "s", "s", TDOR, ("t", 0x04), ("t", 0x06)],
    0x03: [("t", 0x04)],
    0x04: [2, "s", "b"],
    0x05: [("t", 0x06)],
    0x06: [4, 2, 2, "s", "b", ("t", 0x08)],
    0x07: [("t", 0x08)],
    0x08: [2, 2, "s"],
    0x09: [("t", 0x02), TDOR],
    0x0A: [("c", 3, [0x02, 0x01, 0x1A, 0x06, 0x1B]), "s", "b"],
    0x0B: [1, 1, ("c", 2, [0x04, 0x08, 0x17]), "b"],
    # Up to FieldRVA (constant array data, for terraria_recipes.py).
    0x0C: [("c", 5, [0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00, 0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B, 0x20, 0x23,
                     0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B]), ("c", 3, [0x3F, 0x3F, 0x06, 0x0A, 0x3F]), "b"],
    0x0D: [("c", 1, [0x04, 0x08]), "b"],
    0x0E: [2, ("c", 2, [0x02, 0x06, 0x20]), "b"],
    0x0F: [2, 4, ("t", 0x02)],
    0x10: [4, ("t", 0x04)],
    0x11: ["b"],
    0x12: [("t", 0x02), ("t", 0x14)],
    0x14: [2, "s", TDOR],
    0x15: [("t", 0x02), ("t", 0x17)],
    0x17: [2, "s", "b"],
    0x18: [2, ("t", 0x06), ("c", 1, [0x14, 0x17])],
    0x19: [("t", 0x02), ("c", 1, [0x06, 0x0A]), ("c", 1, [0x06, 0x0A])],
    0x1A: ["s"],
    0x1B: ["b"],
    0x1C: [2, ("c", 1, [0x04, 0x06]), "s", ("t", 0x1A)],
    0x1D: [4, ("t", 0x04)],
}


def read_tables(data, streams):
    base, _ = streams["#~"]
    heap_sizes = data[base + 6]
    valid = struct.unpack_from("<Q", data, base + 8)[0]
    p = base + 24
    rows = {}
    for t in range(64):
        if valid >> t & 1:
            rows[t] = struct.unpack_from("<I", data, p)[0]
            p += 4
    sizes = {
        "s": 4 if heap_sizes & 1 else 2,
        "g": 4 if heap_sizes & 2 else 2,
        "b": 4 if heap_sizes & 4 else 2,
    }

    def col_size(c):
        if isinstance(c, int):
            return c
        if isinstance(c, str):
            return sizes[c]
        if c[0] == "t":
            return 2 if rows.get(c[1], 0) < 65536 else 4
        limit = 1 << (16 - c[1])
        return 2 if all(rows.get(t, 0) < limit for t in c[2]) else 4

    tables = {}
    for t in sorted(rows):
        if t not in SCHEMAS:
            break  # we only need tables up to Constant; they're contiguous
        cols = SCHEMAS[t]
        widths = [col_size(c) for c in cols]
        out = []
        for _ in range(rows[t]):
            row = []
            for w in widths:
                row.append(struct.unpack_from("<H" if w == 2 else ("<B" if w == 1 else "<I"), data, p)[0])
                p += w
            out.append(row)
        tables[t] = out
    return tables


def heap_string(data, streams, idx):
    base, _ = streams["#Strings"]
    end = data.index(b"\0", base + idx)
    return data[base + idx:end].decode("utf-8", "replace")


def heap_blob(data, streams, idx):
    base, _ = streams["#Blob"]
    p = base + idx
    b = data[p]
    if b & 0x80 == 0:
        n, p = b, p + 1
    elif b & 0xC0 == 0x80:
        n, p = ((b & 0x3F) << 8) | data[p + 1], p + 2
    else:
        n, p = struct.unpack_from(">I", data, p)[0] & 0x1FFFFFFF, p + 4
    return data[p:p + n]


CONST_FMT = {0x02: "<?", 0x03: "<H", 0x04: "<b", 0x05: "<B", 0x06: "<h", 0x07: "<H", 0x08: "<i", 0x09: "<I", 0x0A: "<q", 0x0B: "<Q"}


def extract_ids(data):
    streams = read_metadata(data)
    t = read_tables(data, streams)
    s = lambda i: heap_string(data, streams, i)
    typedefs, fields, consts = t[0x02], t[0x04], t[0x0B]

    field_value = {}
    for ctype, _pad, parent, blob in consts:
        if parent & 3 == 0 and ctype in CONST_FMT:  # parent is a Field
            field_value[(parent >> 2) - 1] = struct.unpack(CONST_FMT[ctype], heap_blob(data, streams, blob))[0]

    result = {}
    for i, td in enumerate(typedefs):
        name, ns = s(td[1]), s(td[2])
        if ns == "" and name in ARMOR_CLASSES:
            name = ARMOR_CLASSES[name]
        elif name not in ID_CLASSES or ns != "Terraria.ID":
            continue
        start = td[4] - 1
        end = typedefs[i + 1][4] - 1 if i + 1 < len(typedefs) else len(fields)
        ids = {}
        for f in range(start, end):
            if f in field_value:
                ids[s(fields[f][1])] = field_value[f]
        result[name] = ids
    return result


def find_resource_json(data, inside):
    """Returns the length-prefixed JSON manifest resource containing offset `inside`."""
    p = inside
    for _ in range(4000):
        p = data.rfind(b"{", 0, p)
        if p < 4:
            return None
        start = p - 3 if data[p - 3:p] == b"\xef\xbb\xbf" else p
        length = struct.unpack_from("<I", data, start - 4)[0]
        if start + length > inside and length < 20_000_000:
            try:
                text = data[start:start + length].decode("utf-8-sig")
                # Terraria's JSON has trailing commas.
                return json.loads(re.sub(r",(\s*[}\]])", r"\1", text))
            except (ValueError, UnicodeDecodeError):
                pass
    return None


def extract_names(data):
    """Finds the embedded en-US localization JSON sections for items, NPCs, etc."""
    names = {}
    probes = {
        "items": (b'"ItemName"', "CopperShortsword", "Copper Shortsword"),
        "npcs": (b'"NPCName"', "BlueSlime", "Blue Slime"),
        "projectiles": (b'"ProjectileName"', "WoodenArrowFriendly", "Wooden Arrow"),
        "buffs": (b'"BuffName"', "Regeneration", "Regeneration"),
        "tooltips": (b'"ItemTooltip"', "MiningHelmet", "Provides light when worn"),
        "set_bonuses": (b'"ArmorSetBonus"', "Wood", "1 defense"),
        "prefixes": (b'"Prefix"', "Deadly2", "Deadly"),
    }
    for out, (key, probe, english) in probes.items():
        pos = 0
        while out not in names:
            pos = data.find(key + b": {", pos + 1)
            if pos < 0:
                break
            obj = find_resource_json(data, pos)
            section = obj.get(key.decode().strip('"')) if isinstance(obj, dict) else None
            if isinstance(section, dict) and section.get(probe) == english:
                names[out] = section
    return names


# Town NPC text: (section, a key in it, its English text) to find the English
# copy; the sections kept from each such localization file.
TOWN_PROBES = [
    ("TownNPCHousingFailureReasons", "RoomIsTooBig", "This room is too big",
     ["TownNPCHousingFailureReasons", "HousingText", "DryadSpecialText", "GuideHelpText"]),
    ("LegacyDialog", "4", "Sword beats paper! Get one today.", ["LegacyDialog"]),
]


def extract_town_text(data):
    """Town NPC names (<NPC>Names), chat lines (LegacyDialog), housing messages."""
    out = {}
    for section, key, english, keep in TOWN_PROBES:
        pos = 0
        while True:
            pos = data.find(('"%s": {' % section).encode(), pos + 1)
            if pos < 0:
                break
            obj = find_resource_json(data, pos)
            if isinstance(obj, dict) and isinstance(obj.get(section), dict) and obj[section].get(key) == english:
                for k in keep:
                    out[k] = obj.get(k, {})
                for k, v in obj.items():
                    if k.endswith("Names") and isinstance(v, dict):
                        out[k] = list(v.values())
                break
    return out


def main():
    data = open(sys.argv[1], "rb").read()
    out = extract_ids(data)
    out["names"] = extract_names(data)
    out["names"]["town"] = extract_town_text(data)
    with open(sys.argv[2], "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    for k, v in out.items():
        print(f"{k}: {len(v)}")


if __name__ == "__main__":
    main()
