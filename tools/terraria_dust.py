#!/usr/bin/env python3
"""Which dust each block makes when it's hit or broken, read from Terraria.exe:
runs WorldGen.KillTile_MakeTileDust (and KillTile_GetTileDustAmount) in a
small IL interpreter, for every block in game/data/blocks.json that draws from a
Terraria tile sheet, with the block's own tile type and frame (and
KillWall_MakeWallDust for blocks drawn from a wall sheet).

usage: python3 -I terraria_dust.py <Terraria.exe> <blocks.json> <out.json>

Writes {"blocks": {name: {"dust": [[DustID, share], ...], "hit": n, "kill": n,
"no_gravity": bool, "velocity": k, "scale": k, "alpha": a}}}: the dust types the
tile picks (with how often, over many rolls of its random choices), how many
dust a hit and a break make, and what it changes on the dust it makes.
"""
import json
import random
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terraria_recipes import Assembly, disassemble  # noqa: E402

ROLLS = 60  # random runs per block
BR_SHORT = range(0x2B, 0x38)
BR_LONG = range(0x38, 0x45)


class Tile:
    def __init__(self, type=0, fx=0, fy=0, active=False, wall=0):
        self.type, self.frameX, self.frameY, self.liquid, self.is_active = type, fx, fy, 0, active
        self.wall = wall


class Dust:
    def __init__(self, type, alpha, color, scale, speed):
        self.type, self.alpha, self.color, self.scale = type, alpha, color, scale
        self.velocity = (1.0, 1.0)  # multiplier on NewDust's random velocity
        self.noGravity = False
        self.noLight = False
        self.fadeIn = 0.0
        self.speed = speed


# Ground types (solid) the tile can stand on: trees pick their wood's dust by it.
GROUNDS = {"boreal": 147, "mahogany": 60, "jungle": 60, "palm": 53, "shadewood": 199, "ebonwood": 23, "ash": 633}
SOLID = {0, 1, 2, 23, 53, 60, 147, 199, 633}


class Interp:
    ground = 2
    y = 10

    def __init__(self, asm):
        self.asm = asm
        wg = asm.type_methods("Terraria", "WorldGen")
        self.dust_mi = wg["KillTile_MakeTileDust"]
        self.wall_dust_mi = wg["KillWall_MakeWallDust"]
        self.amount_mi = wg["KillTile_GetTileDustAmount"]
        self.code = {}
        self.torch_dust = self._static_int_array("Terraria.ID", "TorchID", "F:TorchID.Dust")

    def _static_int_array(self, ns, typ, field):
        """A static int array set up in a type's .cctor from InitializeArray."""
        a = self.asm
        ms = a.type_methods(ns, typ)
        if ".cctor" not in ms:
            return []
        code = disassemble(a.body(ms[".cctor"]))
        for k, (off, op, arg, nxt) in enumerate(code):
            if op == 0x80 and a.token_name(arg & 0xFFFFFFFF) == field:
                # Walk back to the newarr / ldtoken that built it.
                n = tok = None
                for off2, op2, arg2, _ in reversed(code[max(0, k - 8):k]):
                    if op2 == 0xD0 and tok is None:
                        tok = arg2 & 0xFFFFFFFF
                    if op2 in (0x1F, 0x20) and n is None and tok is not None:
                        n = arg2
                if tok is None or n is None:
                    return []
                rva = a.field_rva.get((tok & 0xFFFFFF) - 1)
                o = a.pe.off(rva)
                return list(struct.unpack_from("<%di" % n, a.data, o))
        return []

    def _code(self, mi):
        if mi not in self.code:
            raw = self.asm.body(mi)
            raw = raw if isinstance(raw, (bytes, bytearray)) else raw[0]
            code = disassemble(raw)
            index = {c[0]: k for k, c in enumerate(code)}
            switches = {}
            for off, op, arg, nxt in code:
                if op == 0x45:
                    n = struct.unpack_from("<I", raw, off + 1)[0]
                    end = off + 5 + 4 * n
                    switches[off] = [index[end + struct.unpack_from("<i", raw, off + 5 + 4 * i)[0]] for i in range(n)]
            self.code[mi] = (code, index, switches)
        return self.code[mi]

    def run(self, mi, args, rng):
        a = self.asm
        code, index, switches = self._code(mi)
        stack, local, k = [], {}, 0
        self.dusts = []
        steps = 0
        while k < len(code):
            off, op, arg, nxt = code[k]
            k += 1
            steps += 1
            if steps > 200000:
                raise RuntimeError("runaway")
            if op in BR_SHORT or op in BR_LONG:
                base = op - (0x2B if op in BR_SHORT else 0x38)
                target = index[nxt + arg]
                if base == 0:
                    k = target
                elif base in (1, 2):
                    v = stack.pop()
                    if (base == 1 and not v) or (base == 2 and v):
                        k = target
                else:
                    b, x = stack.pop(), stack.pop()
                    if base >= 9 and isinstance(x, int) and isinstance(b, int):
                        # bge.un .. blt.un on integers: unsigned (Terraria's range checks).
                        x, b = x & 0xFFFFFFFF, b & 0xFFFFFFFF
                    if [x == b, x >= b, x > b, x <= b, x < b, x != b, x >= b, x > b, x <= b, x < b][base - 3]:
                        k = target
                continue
            if op == 0x45:  # switch
                v = stack.pop()
                t = switches[off]
                if isinstance(v, int) and 0 <= v < len(t):
                    k = t[v]
                continue
            if op == 0x2A:
                return stack.pop() if stack else None
            self._step(op, arg, stack, local, args, rng)
        return None

    def _step(self, op, arg, stack, local, args, rng):
        a = self.asm
        if 0x16 <= op <= 0x1E:
            stack.append(op - 0x16)
        elif op == 0x15:
            stack.append(-1)
        elif op in (0x1F, 0x20):
            stack.append(arg)
        elif op == 0x22:
            stack.append(struct.unpack("<f", struct.pack("<i", arg))[0])
        elif op == 0x23:
            stack.append(struct.unpack("<d", arg)[0] if isinstance(arg, bytes) else arg)
        elif op == 0x14:
            stack.append(None)
        elif 0x02 <= op <= 0x05:
            stack.append(args[op - 2])
        elif op == 0x0E:
            stack.append(args[arg])
        elif 0x06 <= op <= 0x09:
            stack.append(local.get(op - 6, 0))
        elif op == 0x11:
            stack.append(local.get(arg, 0))
        elif op == 0x12:  # ldloca.s: a reference to the local
            stack.append(("loc", arg))
        elif 0x0A <= op <= 0x0D:
            local[op - 0x0A] = stack.pop()
        elif op == 0x13:
            local[arg] = stack.pop()
        elif op == 0x25:
            stack.append(stack[-1])
        elif op == 0x26:
            stack.pop()
        elif op in (0x58, 0x59, 0x5A, 0x5B, 0x5D):
            y, x = stack.pop(), stack.pop()
            if op == 0x58:
                r = x + y
            elif op == 0x59:
                r = x - y
            elif op == 0x5A:
                r = x * y
            elif op == 0x5B:
                r = int(x / y) if isinstance(x, int) and isinstance(y, int) else x / y
            else:
                r = int(x - y * int(x / y)) if isinstance(x, int) else x % y
            stack.append(r)
        elif op == 0x65:
            stack.append(-stack.pop())
        elif op in (0x6B, 0x6C, 0x76):  # conv.r4, conv.r8, conv.r.un
            stack.append(float(stack.pop()))
        elif op in (0x69, 0x67, 0x68, 0x6A, 0xD1, 0xD2):  # conv.i4 / i1 / i2 / i8 / u2 / u1
            stack.append(int(stack.pop()))
        elif op == 0xFE01:
            b, x = stack.pop(), stack.pop()
            stack.append(1 if x == b else 0)
        elif op == 0xFE02:
            b, x = stack.pop(), stack.pop()
            stack.append(1 if x > b else 0)
        elif op == 0xFE04:
            b, x = stack.pop(), stack.pop()
            stack.append(1 if x < b else 0)
        elif op == 0xFE15:  # initobj: a default struct (a Color)
            ref = stack.pop()
            if isinstance(ref, tuple) and ref[0] == "loc":
                local[ref[1]] = (0, 0, 0, 0)
        elif op == 0x7B:  # ldfld
            name = a.token_name(arg & 0xFFFFFFFF)
            obj = stack.pop()
            short = name.split(".")[-1]
            if isinstance(obj, Tile):
                stack.append(getattr(obj, short, 0))
            elif isinstance(obj, Dust):
                stack.append(getattr(obj, short))
            else:
                stack.append(0)
        elif op == 0x7D:  # stfld
            name = a.token_name(arg & 0xFFFFFFFF)
            v, obj = stack.pop(), stack.pop()
            if isinstance(obj, Dust):
                setattr(obj, name.split(".")[-1], v)
        elif op == 0x7E:  # ldsfld
            name = a.token_name(arg & 0xFFFFFFFF)
            stack.append({"F:Main.dust": "dusts", "F:Main.tile": "tiles", "F:TorchID.Dust": self.torch_dust,
                          "F:TorchID.Count": len(self.torch_dust), "F:Main.tileAlch": "alch",
                          "F:Main.rand": "rand", "F:Main.tileSolid": "solid",
                          "F:Main.maxTilesX": 4200}.get(name, 0))
        elif op in (0x9A, 0x94, 0x91, 0x93, 0x90, 0x92):  # ldelem.*
            i, arr = stack.pop(), stack.pop()
            if arr == "dusts":
                stack.append(self.dusts[i] if 0 <= i < len(self.dusts) else Dust(0, 0, None, 1.0, (0, 0)))
            elif arr == "alch":
                stack.append(1 if i in (82, 83, 84) else 0)
            elif arr == "solid":
                stack.append(1 if i in SOLID else 0)
            elif isinstance(arr, list):
                stack.append(arr[i] if 0 <= i < len(arr) else 0)
            else:
                stack.append(0)
        elif op in (0x28, 0x6F, 0x73):  # call, callvirt, newobj
            tk = arg & 0xFFFFFFFF
            name = a.token_name(tk)
            n, has_this, returns = a.signature(tk)
            cargs = [stack.pop() for _ in range(n)][::-1]
            this = stack.pop() if (has_this and op != 0x73) else None
            if op == 0x73:
                stack.append(tuple(cargs))
            elif name == "M:WorldGen.get_genRand":
                stack.append("rand")
            elif name == "M:UnifiedRandom.Next":
                if len(cargs) == 1:
                    stack.append(rng.randrange(cargs[0]) if cargs[0] > 0 else 0)
                elif len(cargs) == 2:
                    stack.append(rng.randrange(cargs[0], cargs[1]) if cargs[1] > cargs[0] else cargs[0])
                else:
                    stack.append(rng.randrange(1 << 30))
            elif name == "R:?.Get":  # Main.tile[x, y]: ground under the tile, air elsewhere
                x, y = cargs[0], cargs[1]
                stack.append(Tile(self.ground, 0, 0, True) if y > self.y else Tile())
            elif name == "M:Tile.active":
                stack.append(1 if this.is_active else 0)
            elif name == "M:WorldGen.SolidTile":
                stack.append(1 if len(cargs) >= 2 and isinstance(cargs[1], int) and cargs[1] > self.y else 0)
            elif name == "M:Dust.NewDust":
                pos, w, h, type, sx, sy, alpha, color, scale = cargs
                if isinstance(color, tuple) and color and color[0] == "loc":
                    color = None
                self.dusts.append(Dust(type, alpha, color, scale, (sx, sy)))
                stack.append(len(self.dusts) - 1)
            elif name == "R:Vector2.op_Multiply":
                v, s = cargs
                stack.append((v[0] * s, v[1] * s) if isinstance(v, tuple) else v)
            elif name == "R:MathHelper.Clamp":
                v, lo, hi = cargs
                stack.append(max(lo, min(hi, v)))
            elif returns:
                stack.append(0)
        elif op == 0xD0:
            stack.append(("token", arg))
        else:
            raise RuntimeError("unhandled opcode %x" % op)

    def dust_for(self, tile_type, fx, fy, ground=2):
        self.ground = ground
        made = {}
        extra = {"no_gravity": False, "velocity": 1.0, "scale": 1.0, "alpha": 0, "speed": [0, 0], "color": None}
        for seed in range(ROLLS):
            rng = random.Random(seed * 7919 + tile_type)
            t = Tile(tile_type, fx, fy, True)
            self.run(self.dust_mi, [10, 10, t], rng)
            for d in self.dusts:
                if d.type < 0:
                    continue
                made[d.type] = made.get(d.type, 0) + 1
                extra["no_gravity"] = extra["no_gravity"] or bool(d.noGravity)
                if isinstance(d.velocity, tuple) and d.velocity != (1.0, 1.0):
                    extra["velocity"] = d.velocity[0]
                if d.scale != 1.0:
                    extra["scale"] = d.scale
                if d.alpha:
                    extra["alpha"] = d.alpha
                if d.speed != (0, 0) and d.speed != (0.0, 0.0):
                    extra["speed"] = [d.speed[0], d.speed[1]]
                if isinstance(d.color, tuple) and len(d.color) >= 3 and any(d.color[:3]):
                    extra["color"] = list(d.color[:3])
        total = sum(made.values())
        out = {"dust": [[t, round(c / total, 3)] for t, c in sorted(made.items(), key=lambda kv: -kv[1])] if total else []}
        hit = self.run(self.amount_mi, [1, Tile(tile_type, fx, fy, True)], random.Random(0))
        kill = self.run(self.amount_mi, [0, Tile(tile_type, fx, fy, True)], random.Random(0))
        out["hit"], out["kill"] = hit, kill
        for k, v in extra.items():
            if v not in (False, 1.0, 0, [0, 0], None):
                out[k] = v
        return out


    def wall_dust_for(self, wall):
        """A wall's dust (KillWall_MakeWallDust); KillWall makes 10, 3 on a hit."""
        made = {}
        for seed in range(ROLLS):
            self.run(self.wall_dust_mi, [10, 10, Tile(wall=wall)], random.Random(seed * 7919 + wall))
            for d in self.dusts:
                if d.type >= 0:
                    made[d.type] = made.get(d.type, 0) + 1
        total = sum(made.values())
        return {"dust": [[t, round(c / total, 3)] for t, c in sorted(made.items(), key=lambda kv: -kv[1])] if total else [],
                "hit": 3, "kill": 10}


def block_wall(b):
    """A block drawn from a Terraria wall sheet (planked wall, disc wall...): its wall type."""
    tex = b.get("tex") or {}
    face = tex.get("all") or tex.get("side") or tex.get("top")
    if isinstance(face, dict) and str(face.get("sheet", "")).startswith("Wall_"):
        return int(face["sheet"].split("_")[1])
    return None


def block_tile(b):
    tex = b.get("tex") or {}
    face = tex.get("all") or tex.get("side") or tex.get("top")
    if not isinstance(face, dict) or not str(face.get("sheet", "")).startswith("Tiles_"):
        return None
    fx, fy = (face.get("frames") or [[0, 0]])[0]
    if isinstance(fx, list):  # [[x, y], ...] per part: the first
        fx, fy = fx
    tile = int(face["sheet"].split("_")[1])
    if tile == 11:  # the open-door sheet: a closed door's dust is the same tile's
        tile = 10
    return tile, int(fx), int(fy)


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    asm = Assembly(sys.argv[1])
    interp = Interp(asm)
    blocks = json.load(open(sys.argv[2]))["blocks"]
    out = {}
    for b in blocks:
        t = block_tile(b)
        if t is None:
            wall = block_wall(b)
            if wall is not None:
                out[b["name"]] = interp.wall_dust_for(wall)
            continue
        ground = next((g for k, g in GROUNDS.items() if k in b["name"]), 2)
        try:
            out[b["name"]] = interp.dust_for(*t, ground)
        except Exception as e:  # noqa: BLE001
            print("%s (tile %d): %s" % (b["name"], t[0], e), file=sys.stderr)
    json.dump({"blocks": out}, open(sys.argv[3], "w"), indent=0, sort_keys=True)
    print("dust for %d blocks" % len(out))


if __name__ == "__main__":
    main()
