#!/usr/bin/env python3
"""What each enemy breaks into when it dies, and bleeds when hit, read from
Terraria.exe: runs NPC.HitEffect (life 0: the death; else a hit) in a small IL
interpreter for every NPC in game/data/npcs.json and records its
Gore.NewGore and Dust.NewDust calls.

usage: python3 -I terraria_gore.py <Terraria.exe> <npcs.json> <ids.json> <out.json>

Writes {"npcs": {name: {"gores": [[[gore, dx, dy, vx, vy, scale], ...], ...],
"death_dust": [[DustID, n], ...], "hit_dust": [...]}}}: a few deaths' worth of
gores (one list per roll of its random choices), each gore's Gore_<n> sprite,
where it starts relative to the NPC's top-left (px) and the speed it gets on
top of the NPC's own (px/tick); and the dust a death and a hit throw (how
many of each type, on average).
"""
import json
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terraria_recipes import Assembly, disassemble  # noqa: E402

ROLLS = 24
BR_SHORT = range(0x2B, 0x38)
BR_LONG = range(0x38, 0x45)


class V2:
    __slots__ = ("X", "Y")

    def __init__(self, x=0.0, y=0.0):
        self.X, self.Y = float(x), float(y)

    def copy(self):
        return V2(self.X, self.Y)


class Obj:
    """Any object: unknown fields read as 0."""

    def __init__(self, **kw):
        self.__dict__.update(kw)

    def get(self, name):
        return self.__dict__.get(name, 0)


class Ref:
    """A reference to a local (ldloca) or an array element (ldelema)."""

    def __init__(self, store, key):
        self.store, self.key = store, key

    def get(self):
        return self.store[self.key] if self.key in self.store or isinstance(self.store, list) else 0

    def set(self, v):
        self.store[self.key] = v


def npc_obj(type_id, net_id, life_max, w, h):
    return Obj(type=type_id, netID=net_id, life=0, lifeMax=life_max, position=V2(0, 0), velocity=V2(0, 0),
               width=w, height=h, scale=1.0, ai=[0.0, 0.0, 0.0, 0.0], localAI=[0.0, 0.0, 0.0, 0.0],
               direction=1, spriteDirection=1, alpha=0, color=(0, 0, 0, 0), whoAmI=0, rotation=0.0,
               altTexture=0, oldPos=[V2() for _ in range(10)], active=1)


class Interp:
    def __init__(self, asm):
        self.asm = asm
        self.gold = [0] * 1000  # NPCID.Sets.IsGoldCritter (from npcs.json's "gold")
        self.mi = asm.type_methods("Terraria", "NPC")["HitEffect"]
        raw = asm.body(self.mi)
        raw = raw if isinstance(raw, (bytes, bytearray)) else raw[0]
        self.code = disassemble(raw)
        self.index = {c[0]: k for k, c in enumerate(self.code)}
        self.switches = {}
        for off, op, arg, nxt in self.code:
            if op == 0x45:
                n = struct.unpack_from("<I", raw, off + 1)[0]
                end = off + 5 + 4 * n
                self.switches[off] = [self.index[end + struct.unpack_from("<i", raw, off + 5 + 4 * i)[0]] for i in range(n)]
        self.names = {}

    def name(self, arg):
        tk = arg & 0xFFFFFFFF
        if tk not in self.names:
            self.names[tk] = self.asm.token_name(tk)
        return self.names[tk]

    def run(self, npc, rng):
        a = self.asm
        code, index = self.code, self.index
        stack, local, k, steps = [], {}, 0, 0
        args = [npc, 1, 10.0]
        self.gores = []
        self.dusts = []
        while k < len(code):
            off, op, arg, nxt = code[k]
            k += 1
            steps += 1
            if steps > 400000:
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
                        x, b = x & 0xFFFFFFFF, b & 0xFFFFFFFF
                    if [x == b, x >= b, x > b, x <= b, x < b, x != b, x >= b, x > b, x <= b, x < b][base - 3]:
                        k = target
                continue
            if op == 0x45:
                v = stack.pop()
                t = self.switches[off]
                if isinstance(v, int) and 0 <= v < len(t):
                    k = t[v]
                continue
            if op in (0x2A, 0xDD, 0xDE):  # ret, leave
                if op == 0x2A:
                    return
                k = index[nxt + arg]
                continue
            self.step(op, arg, stack, local, args, rng)

    def step(self, op, arg, stack, local, args, rng):
        if op == 0x00:  # nop
            return
        if 0x16 <= op <= 0x1E:
            stack.append(op - 0x16)
        elif op == 0x15:
            stack.append(-1)
        elif op in (0x1F, 0x20):
            stack.append(arg)
        elif op == 0x21:
            stack.append(arg)
        elif op == 0x22:
            stack.append(struct.unpack("<f", struct.pack("<i", arg))[0])
        elif op == 0x23:
            stack.append(struct.unpack("<d", arg)[0] if isinstance(arg, bytes) else float(arg))
        elif op == 0x14:
            stack.append(None)
        elif 0x02 <= op <= 0x05:
            stack.append(args[op - 2] if op - 2 < len(args) else 0)
        elif op == 0x0E:
            stack.append(args[arg] if arg < len(args) else 0)
        elif op in (0x0F,):  # ldarga.s
            stack.append(Ref(args, arg))
        elif op in (0x10,):  # starg.s
            args[arg] = stack.pop()
        elif 0x06 <= op <= 0x09:
            stack.append(local.get(op - 6, 0))
        elif op == 0x11 or op == 0xFE0C:
            stack.append(local.get(arg, 0))
        elif op == 0x12 or op == 0xFE0D:
            if arg not in local:
                local[arg] = V2()
            stack.append(Ref(local, arg))
        elif 0x0A <= op <= 0x0D:
            local[op - 0x0A] = stack.pop()
        elif op == 0x13 or op == 0xFE0E:
            local[arg] = stack.pop()
        elif op == 0x25:
            v = stack[-1]
            stack.append(v)
        elif op == 0x26:
            stack.pop()
        elif op in (0x58, 0x59, 0x5A, 0x5B, 0x5D):
            y, x = stack.pop(), stack.pop()
            x = 0 if not isinstance(x, (int, float)) else x
            y = 0 if not isinstance(y, (int, float)) else y
            if op == 0x58:
                r = x + y
            elif op == 0x59:
                r = x - y
            elif op == 0x5A:
                r = x * y
            elif op == 0x5B:
                r = (int(x / y) if isinstance(x, int) and isinstance(y, int) else x / y) if y else 0
            else:
                r = (int(x - y * int(x / y)) if isinstance(x, int) else x % y) if y else 0
            stack.append(r)
        elif op in (0x5F, 0x60, 0x61):  # and, or, xor
            y, x = stack.pop(), stack.pop()
            x, y = int(bool(x)) if not isinstance(x, int) else x, int(bool(y)) if not isinstance(y, int) else y
            stack.append([x & y, x | y, x ^ y][op - 0x5F])
        elif op == 0x65:
            v = stack.pop()
            stack.append(-v if isinstance(v, (int, float)) else 0)
        elif op == 0x66:  # not
            v = stack.pop()
            stack.append(~v if isinstance(v, int) else 0)
        elif op in (0x6B, 0x6C, 0x76):
            v = stack.pop()
            stack.append(float(v) if isinstance(v, (int, float)) else 0.0)
        elif op in (0x67, 0x68, 0x69, 0x6A, 0x6D, 0x6E, 0xD1, 0xD2, 0xD3, 0xD4, 0x84, 0x82):
            v = stack.pop()
            stack.append(int(v) if isinstance(v, (int, float)) else 0)
        elif op in (0xFE01, 0xFE02, 0xFE03, 0xFE04, 0xFE05):
            b, x = stack.pop(), stack.pop()
            if not isinstance(x, (int, float)) or not isinstance(b, (int, float)):
                stack.append(1 if (op == 0xFE01 and x is b) else 0)
            else:
                stack.append(1 if [x == b, x > b, x > b, x < b, x < b][op - 0xFE01] else 0)
        elif op == 0xFE15:  # initobj
            ref = stack.pop()
            if isinstance(ref, Ref):
                ref.set(V2())
        elif op in (0x7B, 0x7C):  # ldfld, ldflda
            obj = stack.pop()
            if isinstance(obj, Ref):
                obj = obj.get()
            f = self.name(arg).split(".")[-1]
            if isinstance(obj, V2):
                stack.append(getattr(obj, f, 0.0))
            elif isinstance(obj, Obj):
                v = obj.get(f)
                stack.append(v.copy() if (op == 0x7B and isinstance(v, V2)) else v)
            else:
                stack.append(V2() if f in ("position", "velocity", "Center") else 0)
        elif op == 0x7D:  # stfld
            v, obj = stack.pop(), stack.pop()
            if isinstance(obj, Ref):
                obj = obj.get()
            f = self.name(arg).split(".")[-1]
            if isinstance(obj, (V2, Obj)):
                try:
                    setattr(obj, f, v)
                except AttributeError:
                    pass
        elif op in (0x7E, 0x7F):  # ldsfld, ldsflda
            n = self.name(arg)
            stack.append({"F:Main.dust": "dusts", "F:Main.gore": "gores", "F:Main.rand": "rand",
                          "F:Main.npc": "npcs", "F:Main.player": "players", "F:Main.maxNPCs": 200,
                          "F:Sets.IsGoldCritter": self.gold}.get(n, 0))
        elif op == 0x80:
            stack.pop()
        elif op in (0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x8F):  # ldelem*, ldelema
            i, arr = stack.pop(), stack.pop()
            if arr == "gores":
                stack.append(self.gores[i][1] if isinstance(i, int) and 0 <= i < len(self.gores) else Obj(velocity=V2()))
            elif arr in ("dusts", "npcs", "players"):
                stack.append(Obj(velocity=V2(), position=V2(), scale=1.0))
            elif isinstance(arr, list) and isinstance(i, int) and 0 <= i < len(arr):
                stack.append(Ref(arr, i) if op == 0x8F else arr[i])
            else:
                stack.append(0)
        elif op in (0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xA0, 0xA1, 0xA2):  # stelem*
            v, i, arr = stack.pop(), stack.pop(), stack.pop()
            if isinstance(arr, list) and isinstance(i, int) and 0 <= i < len(arr):
                arr[i] = v
        elif op in (0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x46, 0x47, 0x48, 0x49, 0x71):  # ldind*, ldobj
            r = stack.pop()
            stack.append(r.get() if isinstance(r, Ref) else (getattr(r, "X", 0) if False else r))
        elif op in (0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x51, 0x81):  # stind*, stobj
            v, r = stack.pop(), stack.pop()
            if isinstance(r, Ref):
                r.set(v)
        elif op == 0x8D:  # newarr
            n = stack.pop()
            stack.append([0] * (n if isinstance(n, int) and 0 <= n < 10000 else 0))
        elif op == 0x8E:  # ldlen
            arr = stack.pop()
            stack.append(len(arr) if isinstance(arr, list) else 0)
        elif op == 0xD0:
            stack.append(("token", arg))
        elif op in (0x74, 0x75, 0xA5, 0x8C, 0x79):  # castclass, isinst, unbox.any, box, unbox
            pass
        elif op in (0x28, 0x6F, 0x73):
            self.call(op, arg, stack, rng)
        elif op == 0xFE16:  # constrained.
            pass
        else:
            raise RuntimeError("opcode %x" % op)

    def call(self, op, arg, stack, rng):
        tk = arg & 0xFFFFFFFF
        name = self.name(tk)
        n, has_this, returns = self.asm.signature(tk)
        cargs = [stack.pop() for _ in range(n)][::-1]
        this = stack.pop() if (has_this and op != 0x73) else None
        short = name.split(".")[-1]
        val = lambda v: v.get() if isinstance(v, Ref) else v  # noqa: E731
        cargs = [val(c) for c in cargs]
        out = None
        if name in ("R:Vector2..ctor",):
            v = V2(*(cargs + [0, 0])[:2]) if cargs else V2()
            if op == 0x73:
                out = v
            elif isinstance(this, Ref):
                this.set(v)
                return
        elif op == 0x73:
            out = V2(*(cargs + [0, 0])[:2]) if "Vector2" in name else Obj()
        elif name == "M:Gore.NewGore" or name == "M:Gore.NewGorePerfect" or name == "M:Gore.NewGoreDirect":
            vs = [c for c in cargs if isinstance(c, V2)]
            ints = [c for c in cargs if isinstance(c, int)]
            fl = [c for c in cargs if isinstance(c, float)]
            if len(vs) >= 2 and ints:
                g = Obj(velocity=vs[1].copy(), position=vs[0].copy(), type=ints[-1], scale=fl[-1] if fl else 1.0)
                self.gores.append((ints[-1], g))
            out = len(self.gores) - 1 if name == "M:Gore.NewGore" else Obj(velocity=V2())
        elif name in ("M:Dust.NewDust", "M:Dust.NewDustDirect"):
            ints = [c for c in cargs if isinstance(c, int)]
            if len(ints) >= 3:
                self.dusts.append(ints[2])  # (position, width, height, type, ...)
            out = 0 if name == "M:Dust.NewDust" else Obj(velocity=V2(), position=V2(), scale=1.0)
        elif name == "M:Dust.NewDustPerfect":
            ints = [c for c in cargs if isinstance(c, int)]
            if ints:
                self.dusts.append(ints[0])
            out = Obj(velocity=V2(), position=V2(), scale=1.0)
        elif short == "Next" and "UnifiedRandom" in name:
            if len(cargs) == 1:
                out = rng.randrange(cargs[0]) if isinstance(cargs[0], int) and cargs[0] > 0 else 0
            elif len(cargs) == 2:
                lo, hi = cargs
                out = rng.randrange(lo, hi) if isinstance(lo, int) and isinstance(hi, int) and hi > lo else (lo if isinstance(lo, int) else 0)
            else:
                out = rng.randrange(1 << 30)
        elif short == "NextDouble" or short == "NextFloat":
            out = rng.random()
        elif short.startswith("NextVector2") or short == "RandomVector":
            out = V2(rng.uniform(-1, 1), rng.uniform(-1, 1))
        elif name == "M:Entity.get_Center":
            p = this.get("position") if isinstance(this, Obj) else V2()
            out = V2(p.X + this.get("width") / 2, p.Y + this.get("height") / 2) if isinstance(this, Obj) else V2()
        elif name in ("M:Entity.get_Top", "M:Entity.get_Bottom", "M:Entity.get_Right", "M:Entity.get_Left"):
            p = this.get("position") if isinstance(this, Obj) else V2()
            w, h = (this.get("width"), this.get("height")) if isinstance(this, Obj) else (0, 0)
            out = {"get_Top": V2(p.X + w / 2, p.Y), "get_Bottom": V2(p.X + w / 2, p.Y + h),
                   "get_Right": V2(p.X + w, p.Y + h / 2), "get_Left": V2(p.X, p.Y + h / 2)}[short]
        elif name.startswith("R:Vector2.op_"):
            a, b = (cargs + [0, 0])[:2]
            ax, ay = (a.X, a.Y) if isinstance(a, V2) else (a, a)
            bx, by = (b.X, b.Y) if isinstance(b, V2) else (b, b)
            o = short[3:]
            if o == "Addition":
                out = V2(ax + bx, ay + by)
            elif o == "Subtraction":
                out = V2(ax - bx, ay - by)
            elif o == "Multiply":
                out = V2(ax * bx, ay * by)
            elif o == "Division":
                out = V2(ax / bx if bx else 0, ay / by if by else 0)
            elif o == "UnaryNegation":
                out = V2(-ax, -ay)
            else:
                out = 0
        elif name in ("M:Utils.RotatedBy", "M:Utils.RotatedByRandom", "R:Vector2.Normalize", "M:Utils.SafeNormalize"):
            out = cargs[0] if cargs and isinstance(cargs[0], V2) else (this.get() if isinstance(this, Ref) else V2())
        elif name == "M:NPC.get_IsShimmerVariant":
            out = 0
        elif returns:
            out = 0
        if returns or op == 0x73:
            stack.append(out)

    def dust_for(self, type_id, net_id, life_max, w, h, life):
        """[[DustID, how many on average], ...] a hit (life left) or the death throws."""
        made = {}
        for seed in range(ROLLS):
            npc = npc_obj(type_id, net_id, life_max, w, h)
            npc.life = life
            self.run(npc, random.Random(seed * 131 + type_id))
            for d in self.dusts:
                made[d] = made.get(d, 0) + 1
        return [[t, round(c / ROLLS, 1)] for t, c in sorted(made.items(), key=lambda kv: -kv[1]) if c / ROLLS >= 0.05]

    def gores_for(self, type_id, net_id, life_max, w, h):
        rolls = []
        for seed in range(ROLLS):
            npc = npc_obj(type_id, net_id, life_max, w, h)
            self.run(npc, random.Random(seed * 977 + type_id))
            roll = []
            for t, g in self.gores:
                roll.append([t, round(g.position.X, 1), round(g.position.Y, 1), round(g.velocity.X, 2), round(g.velocity.Y, 2),
                             round(g.scale, 2) if isinstance(g.scale, float) else 1.0])
            if roll and roll not in rolls:
                rolls.append(roll)
        return rolls


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    asm = Assembly(sys.argv[1])
    npcs = json.load(open(sys.argv[2]))
    ids = json.load(open(sys.argv[3]))["NPCID"]
    it = Interp(asm)
    for name, d in npcs.items():
        if isinstance(d, dict) and d.get("gold") and ids.get(name, -1) >= 0:
            it.gold[ids[name]] = 1
    # The width/height of each NPC in Terraria px (positions are relative anyway).
    out = {}
    for name, d in npcs.items():
        if name.startswith("_") or name not in ids:
            continue
        net = ids[name]
        type_id = 1 if net < 0 else net  # slime colours are Blue Slimes with a net ID
        size = d.get("size", [1, 1])
        life, w, h = int(d.get("life", 10)), int(size[0] * 24), int(size[1] * 24)
        try:
            rolls = it.gores_for(type_id, net, life, w, h)
            entry = {"gores": rolls[:8], "death_dust": it.dust_for(type_id, net, life, w, h, 0),
                     "hit_dust": it.dust_for(type_id, net, life, w, h, max(1, life // 2))}
        except Exception as e:  # noqa: BLE001
            print("%s: %s" % (name, e), file=sys.stderr)
            continue
        out[name] = entry
    json.dump({"npcs": out}, open(sys.argv[4], "w"), indent=0, sort_keys=True)
    print("gores for %d NPCs" % len(out))


if __name__ == "__main__":
    main()
