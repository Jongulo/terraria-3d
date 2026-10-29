#!/usr/bin/env python3
"""Extracts what Shimmer does to items from Terraria.exe: ItemID.Sets'
ShimmerTransformToItem (an item that turns into another), ShimmerCountsAsItem
and ShimmerCountsAsItemForDecraft (items shimmered as another), and
ShimmerPostMoonlord (those that wait for the Moon Lord), as the static
constructor of ItemID.Sets builds them (constant arrays of id pairs).

usage: python3 -I terraria_shimmer.py <Terraria.exe> <ids.json> <out.json>

Writes {"transform": {item: item}, "counts_as": {item: item},
"counts_as_decraft": {item: item}, "post_moonlord": [item...]} (internal item
names).
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terraria_recipes import Assembly, disassemble  # noqa: E402

FIELDS = {"ShimmerTransformToItem": "transform", "ShimmerCountsAsItem": "counts_as",
          "ShimmerCountsAsItemForDecraft": "counts_as_decraft", "ShimmerPostMoonlord": "post_moonlord"}


def sets_arrays(asm, mi):
    """The constant int arrays a static constructor stores into its fields
    (through Factory.CreateIntSet / CreateBoolSet): {field: [ints]}."""
    stack, out = [], {}
    for _off, op, arg, _nxt in disassemble(asm.body(mi)):
        if 0x16 <= op <= 0x1E:
            stack.append(op - 0x16)
        elif op == 0x15:
            stack.append(-1)
        elif op in (0x1F, 0x20):
            stack.append(arg)
        elif op == 0x8D:  # newarr
            n = stack.pop() if stack else 0
            stack.append([0] * (n if isinstance(n, int) else 0))
        elif op == 0x25:  # dup
            stack.append(stack[-1] if stack else None)
        elif op == 0x9E:  # stelem.i4
            v, i, arr = stack.pop(), stack.pop(), stack.pop()
            if isinstance(arr, list) and isinstance(i, int) and i < len(arr):
                arr[i] = v
        elif op == 0xD0:  # ldtoken
            stack.append(("token", arg & 0xFFFFFFFF))
        elif op in (0x28, 0x6F, 0x73):  # call, callvirt, newobj
            tk = arg & 0xFFFFFFFF
            name = asm.token_name(tk)
            n, has_this, returns = asm.signature(tk)
            args = [stack.pop() if stack else None for _ in range(n)][::-1]
            if has_this and op != 0x73 and stack:
                stack.pop()
            if name == "R:RuntimeHelpers.InitializeArray":
                arr, token = args
                if isinstance(arr, list) and isinstance(token, tuple):
                    rva = asm.field_rva.get((token[1] & 0xFFFFFF) - 1)
                    if rva is not None:
                        arr[:] = list(struct.unpack_from("<%di" % len(arr), asm.data, asm.pe.off(rva)))
            elif name.startswith("M:SetFactory.Create") and args and isinstance(args[-1], list):
                stack.append(args[-1])
            elif op == 0x73 or returns:
                stack.append(None)
        elif op == 0x80:  # stsfld
            field = asm.token_name(arg & 0xFFFFFFFF).split(".")[-1]
            v = stack.pop() if stack else None
            if isinstance(v, list):
                out[field] = v
        elif op in (0x26,):
            if stack:
                stack.pop()
        else:
            # Anything else: forget what's on the stack (it's not ours).
            if op in (0x7E, 0x7B, 0x14, 0x72, 0x06, 0x07, 0x08, 0x09, 0x11, 0x12, 0xFE0C):
                stack.append(None)
    return out


def extract(exe, ids):
    asm = Assembly(exe)
    items = {v: k for k, v in ids["ItemID"].items()}
    for i, td in enumerate(asm.typedefs):
        if asm.s(td[1]) != "Sets":
            continue
        end = asm.typedefs[i + 1][5] - 1 if i + 1 < len(asm.typedefs) else len(asm.methods)
        for mi in range(td[5] - 1, end):
            if asm.s(asm.methods[mi][3]) != ".cctor":
                continue
            arrays = sets_arrays(asm, mi)
            if "ShimmerCountsAsItem" not in arrays:
                continue  # NPCID.Sets and the others
            out = {}
            for field, key in FIELDS.items():
                v = arrays.get(field, [])
                if key == "post_moonlord":
                    out[key] = [items.get(x, x) for x in v]
                else:
                    out[key] = {items.get(v[k], v[k]): items.get(v[k + 1], v[k + 1]) for k in range(0, len(v) - 1, 2)}
            return out
    raise SystemExit("ItemID.Sets not found")


def main():
    ids = json.load(open(sys.argv[2]))
    out = extract(sys.argv[1], ids)
    with open(sys.argv[3], "w") as f:
        json.dump(out, f, indent=1)
    print("shimmer: %d transforms" % len(out["transform"]))


if __name__ == "__main__":
    main()
