#!/usr/bin/env python3
"""Extracts Terraria's crafting recipes from Terraria.exe.

usage: python3 -I terraria_recipes.py <Terraria.exe> <ids.json> <out.json>

Terraria builds its recipe list in code (Recipe.SetupRecipes and the helper
methods it calls), so this reads that method's CIL and runs it in a tiny
interpreter that only follows what recipes are made of: the item made and how
many, each ingredient and its stack, the crafting stations, recipe groups
("any Wood", "Iron or Lead Bar"...) and flags (needWater...). Ingredient lists
written as constant arrays (SetIngredients) are read from the assembly's data.

Writes [{"result": internal item name, "count", "ingredients": [[name, n]...],
"tiles": [TileID names], "groups": [RecipeGroups names], "flags": [...]},
plus "shimmer": [[name, n]...] where a recipe sets what shimmering its item
gives back instead of its ingredients (AddCustomShimmerResult)].
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terraria_ids as t  # noqa: E402

# CIL operand sizes (one-byte opcodes; 0xFE-prefixed ones in TWO).
ONE = {op: 0 for op in range(0x100)}
for op in [0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x1F, 0xDE] + list(range(0x2B, 0x38)):
    ONE[op] = 1
for op in [0x20, 0x22, 0x27, 0x28, 0x29, 0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x79, 0x7B, 0x7C, 0x7D, 0x7E,
           0x7F, 0x80, 0x81, 0x8C, 0x8D, 0x8F, 0xA3, 0xA4, 0xA5, 0xC2, 0xC6, 0xD0, 0xDD] + list(range(0x38, 0x45)):
    ONE[op] = 4
ONE[0x21] = 8
ONE[0x23] = 8
TWO = {0x06: 4, 0x07: 4, 0x09: 2, 0x0A: 2, 0x0B: 2, 0x0C: 2, 0x0D: 2, 0x0E: 2, 0x12: 1, 0x15: 4, 0x16: 4, 0x1C: 4}
BR_SHORT = range(0x2B, 0x38)
BR_LONG = range(0x38, 0x45)
STEP_LIMIT = 3_000_000


class Assembly:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        self.streams = t.read_metadata(self.data)
        self.tables = t.read_tables(self.data, self.streams)
        self.pe = t.PE(self.data)
        tb = self.tables
        self.typedefs, self.fields, self.methods = tb[0x02], tb[0x04], tb[0x06]
        self.memberrefs, self.typerefs = tb[0x0A], tb[0x01]
        self.field_rva = {row[1] - 1: row[0] for row in tb.get(0x1D, [])}

    def s(self, i):
        return t.heap_string(self.data, self.streams, i)

    def _owner(self, idx, col, count):
        for i, td in enumerate(self.typedefs):
            start = td[col] - 1
            end = self.typedefs[i + 1][col] - 1 if i + 1 < len(self.typedefs) else count
            if start <= idx < end:
                return self.s(td[1])
        return "?"

    def token_name(self, tk):
        table, idx = tk >> 24, (tk & 0xFFFFFF) - 1
        if table == 0x06:
            return "M:%s.%s" % (self._owner(idx, 5, len(self.methods)), self.s(self.methods[idx][3]))
        if table == 0x04:
            return "F:%s.%s" % (self._owner(idx, 4, len(self.fields)), self.s(self.fields[idx][1]))
        if table == 0x0A:
            cls = self.memberrefs[idx][0]
            tag, ci = cls & 7, (cls >> 3) - 1
            owner = self.s(self.typerefs[ci][1]) if tag == 1 else (self.s(self.typedefs[ci][1]) if tag == 0 else "?")
            return "R:%s.%s" % (owner, self.s(self.memberrefs[idx][1]))
        return "tok%08x" % tk

    def signature(self, tk):
        """(parameter count, has this, returns a value) of a called method."""
        table, idx = tk >> 24, (tk & 0xFFFFFF) - 1
        blob = self.methods[idx][4] if table == 0x06 else (self.memberrefs[idx][2] if table == 0x0A else None)
        if blob is None:
            return 0, False, True
        b = t.heap_blob(self.data, self.streams, blob)
        conv, i = b[0], 1
        if conv & 0x10:
            i += 1  # generic parameter count
        n = b[i]
        if n & 0x80:
            n, i = ((n & 0x3F) << 8) | b[i + 1], i + 2
        else:
            i += 1
        return n, bool(conv & 0x20), b[i] != 0x01

    def body(self, mi):
        rva = self.methods[mi][0]
        if rva == 0:
            return b""
        o = self.pe.off(rva)
        h = self.data[o]
        if h & 3 == 2:
            return self.data[o + 1:o + 1 + (h >> 2)]
        flags = struct.unpack_from("<H", self.data, o)[0]
        size = struct.unpack_from("<I", self.data, o + 4)[0]
        start = o + (flags >> 12) * 4
        return self.data[start:start + size]

    def type_methods(self, ns, name):
        for i, td in enumerate(self.typedefs):
            if self.s(td[1]) == name and self.s(td[2]) == ns:
                end = self.typedefs[i + 1][5] - 1 if i + 1 < len(self.typedefs) else len(self.methods)
                return {self.s(self.methods[mi][3]): mi for mi in range(end - 1, td[5] - 2, -1)}
        return {}


def disassemble(code):
    """[(offset, opcode, operand, next offset)]."""
    i, out = 0, []
    while i < len(code):
        start, op = i, code[i]
        i += 1
        if op == 0xFE:
            op2 = code[i]
            i += 1
            n = TWO.get(op2, 0)
            arg = int.from_bytes(code[i:i + n], "little", signed=True) if n else None
            i += n
            out.append((start, 0xFE00 | op2, arg, i))
            continue
        if op == 0x45:  # switch
            n = struct.unpack_from("<I", code, i)[0]
            i += 4 + 4 * n
            out.append((start, op, None, i))
            continue
        n, arg = ONE[op], None
        if n == 1:
            arg = struct.unpack_from("<b", code, i)[0]
        elif n == 4:
            arg = struct.unpack_from("<i", code, i)[0]
        elif n == 8:
            arg = code[i:i + 8]
        i += n
        out.append((start, op, arg, i))
    return out


class RecipeReader:
    # Helpers SetupRecipes calls that only build recipes from what's set up
    # already, at runtime (skipped: reverse wall/platform recipes and the
    # bookkeeping after the list is made).
    SKIP = ("CreateReverse", "CreateRequired", "Update", "AddRecipe", "AddToAvailable", "AddMissing",
            "AddFakeCounts", "AddTileCountsAs", "AddCustomShimmerResult", "SetupTileInheritance")

    def __init__(self, asm):
        self.asm = asm
        self.methods = asm.type_methods("Terraria", "Recipe")
        self.recipes = []
        self.cur = self._new()

    @staticmethod
    def _new():
        return {"create": None, "count": 1, "req": {}, "tiles": [], "groups": [], "flags": []}

    def run(self, mi, args, depth=0):
        a = self.asm
        code = disassemble(a.body(mi))
        index = {c[0]: k for k, c in enumerate(code)}
        stack, local, k, steps = [], {}, 0, 0
        cur = lambda: self.cur  # noqa: E731
        while k < len(code):
            off, op, arg, nxt = code[k]
            k += 1
            steps += 1
            if steps > STEP_LIMIT:
                raise RuntimeError("runaway loop in method %d" % mi)
            if op in BR_SHORT or op in BR_LONG:
                base = op - (0x2B if op in BR_SHORT else 0x38)
                target = index.get(nxt + arg)
                if base == 0:
                    k = target
                elif base in (1, 2):  # brfalse, brtrue: unknown values fall through
                    v = stack.pop() if stack else None
                    if v is not None and ((base == 1 and not v) or (base == 2 and v)):
                        k = target
                else:
                    b = stack.pop() if stack else None
                    x = stack.pop() if stack else None
                    if isinstance(x, int) and isinstance(b, int):
                        if [x == b, x >= b, x > b, x <= b, x < b, x != b, x >= b, x > b, x <= b, x < b][base - 3]:
                            k = target
                continue
            try:
                self._step(op, arg, stack, local, args, depth)
            except IndexError:
                stack.clear()
            if op == 0x2A:  # ret
                return

    def _step(self, op, arg, stack, local, args, depth):
        a, cur = self.asm, self.cur
        if 0x16 <= op <= 0x1E:
            stack.append(op - 0x16)
        elif op == 0x15:
            stack.append(-1)
        elif op in (0x1F, 0x20):
            stack.append(arg)
        elif op == 0x14:
            stack.append(None)
        elif 0x02 <= op <= 0x05:
            stack.append(args[op - 2] if op - 2 < len(args) else None)
        elif op == 0x0E:
            stack.append(args[arg] if arg < len(args) else None)
        elif 0x06 <= op <= 0x09:
            stack.append(local.get(op - 6))
        elif op == 0x11:
            stack.append(local.get(arg))
        elif 0x0A <= op <= 0x0D:
            local[op - 0x0A] = stack.pop()
        elif op == 0x13:
            local[arg] = stack.pop()
        elif op == 0x25:
            stack.append(stack[-1])
        elif op == 0x26:
            stack.pop()
        elif op == 0x58:
            y, x = stack.pop(), stack.pop()
            stack.append(x + y if isinstance(x, int) and isinstance(y, int) else None)
        elif op == 0x94:  # ldelem.i4
            i, arr = stack.pop(), stack.pop()
            stack.append(arr[1][i] if isinstance(arr, list) and isinstance(i, int) and i < len(arr[1]) else None)
        elif op == 0x7E:
            name = a.token_name(arg & 0xFFFFFFFF)
            if name == "F:Recipe.currentRecipe":
                stack.append("R")
            elif name.startswith("F:RecipeGroups."):
                stack.append(("group", name.split(".")[-1]))
            else:
                stack.append(name)
        elif op == 0x7B:
            name = a.token_name(arg & 0xFFFFFFFF)
            stack.pop()
            stack.append({"F:Recipe.createItem": "create", "F:Recipe.requiredItem": "reqarr",
                          "F:Recipe.requiredTile": "tilearr"}.get(name, name))
        elif op == 0x9A:  # ldelem.ref
            i, arr = stack.pop(), stack.pop()
            stack.append(("req", i) if arr == "reqarr" else None)
        elif op == 0x8D:  # newarr
            n = stack.pop()
            stack.append(["arr", [0] * (n if isinstance(n, int) else 0)])
        elif op == 0xD0:  # ldtoken
            stack.append(("token", arg & 0xFFFFFFFF))
        elif op == 0x9E:  # stelem.i4
            v, i, arr = stack.pop(), stack.pop(), stack.pop()
            if arr == "tilearr":
                cur["tiles"].append(v)
            elif isinstance(arr, list) and isinstance(i, int) and i < len(arr[1]):
                arr[1][i] = v
        elif op == 0x7D:  # stfld
            name = a.token_name(arg & 0xFFFFFFFF)
            v, obj = stack.pop(), stack.pop()
            if name == "F:Item.stack":
                if obj == "create":
                    cur["count"] = v
                elif isinstance(obj, tuple) and obj[0] == "req":
                    cur["req"].setdefault(obj[1], [None, 1])[1] = v
            elif obj == "R" and name == "F:Recipe.requiredTile":
                cur["tiles"].append(v)
            elif obj == "R" and name.startswith("F:Recipe.") and v:
                cur["flags"].append(name.split(".")[-1])
        elif op in (0x28, 0x6F, 0x73):  # call, callvirt, newobj
            tk = arg & 0xFFFFFFFF
            name = a.token_name(tk)
            n, has_this, returns = a.signature(tk)
            cargs = [stack.pop() for _ in range(n)][::-1]
            this = stack.pop() if (has_this and op != 0x73) else None
            if op == 0x73 or (returns and name != "M:Item.SetDefaults"):
                stack.append(None)
            short = name.split(".")[-1]
            if name == "M:Item.SetDefaults":
                if this == "create":
                    cur["create"] = cargs[0]
                elif isinstance(this, tuple) and this[0] == "req":
                    cur["req"].setdefault(this[1], [None, 1])[0] = cargs[0]
            elif name == "R:RuntimeHelpers.InitializeArray":
                arr, token = cargs
                if isinstance(arr, list) and isinstance(token, tuple):
                    rva = a.field_rva.get((token[1] & 0xFFFFFF) - 1)
                    if rva is not None:
                        o = a.pe.off(rva)
                        arr[1][:] = list(struct.unpack_from("<%di" % len(arr[1]), a.data, o))
            elif name == "M:Recipe.SetIngredients":
                vals = cargs[0][1] if isinstance(cargs[0], list) else []
                # One item alone is one of it (Recipe.SetIngredients).
                if len(vals) == 1:
                    vals = [vals[0], 1]
                for q in range(0, len(vals) - 1, 2):
                    cur["req"][len(cur["req"])] = [vals[q], vals[q + 1]]
            elif name == "M:Recipe.SetCraftingStation":
                cur["tiles"].append(cargs[0])
            elif name == "M:Recipe.RequireGroup":
                g = cargs[0]
                cur["groups"].append(g[1] if isinstance(g, tuple) else g)
            elif name == "M:Recipe.AddCustomShimmerResult" and this == "R":
                cur.setdefault("shimmer", []).append(cargs[:2])
            elif name == "M:Recipe.AddRecipe":
                self.recipes.append(cur)
                self.cur = self._new()
            elif name.startswith("M:Recipe.") and short in self.methods and depth < 4 and not short.startswith(self.SKIP):
                self.run(self.methods[short], cargs, depth + 1)


def extract(exe, ids):
    asm = Assembly(exe)
    reader = RecipeReader(asm)
    reader.run(reader.methods["SetupRecipes"], [])
    items = {v: k for k, v in ids["ItemID"].items()}
    tiles = {v: k for k, v in ids["TileID"].items()}
    out = []
    for r in reader.recipes:
        if not isinstance(r["create"], int) or r["create"] <= 0:
            continue
        ings = [[items.get(v[0], v[0]), v[1]] for _, v in sorted(r["req"].items()) if isinstance(v[0], int) and v[0] > 0]
        out.append({
            "result": items.get(r["create"], r["create"]), "count": r["count"], "ingredients": ings,
            "tiles": [tiles.get(v, v) for v in r["tiles"] if isinstance(v, int) and v >= 0],
            "groups": r["groups"], "flags": r["flags"],
        })
        if r.get("shimmer"):
            out[-1]["shimmer"] = [[items.get(v[0], v[0]), v[1]] for v in r["shimmer"] if isinstance(v[0], int)]
    return out


def main():
    ids = json.load(open(sys.argv[2]))
    recipes = extract(sys.argv[1], ids)
    with open(sys.argv[3], "w") as f:
        json.dump(recipes, f, indent=0)
    print("recipes: %d" % len(recipes))


if __name__ == "__main__":
    main()
