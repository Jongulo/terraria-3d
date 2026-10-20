#!/usr/bin/env python3
"""Extracts Terraria's fishing catch table from Terraria.exe.

usage: python3 -I terraria_fishing.py <Terraria.exe> <ids.json> <out.json>

Terraria 1.4.5 decides what a bobber catches with a list of rules
(GameContent.FishDropRules: GameContentFishDropPopulator.Populate and the
methods it calls, in order). Each rule has conditions (the biome, the
height level, the catch's rarity rolls...), a chance (numerator /
denominator) and the items it can give; the first rule whose conditions hold
and whose chance roll succeeds decides the catch (FishDropRuleList.
TryGetItemDropType). A "stopper" (no items) ends the search with nothing.

This runs those methods' CIL in a tiny stack interpreter that only follows
the rule building (AFishDropRulePopulator.Add / AddQuestFish /
AddWithHardmode / AddStopper / Group / Join), and writes, in order:
  [{"rarity": Rarity name, "chance": [numerator, denominator],
    "items": [internal item names], "conditions": [condition names],
    "quest": true for a quest fish (needs it to be the Angler's fish today)}]
The conditions are AFishDropRulePopulator's fields (HardMode, InLava, Ocean,
Height1...), checked by game/scripts/items/fishing.gd.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terraria_recipes as tr  # noqa: E402

POPULATOR = "GameContentFishDropPopulator"


def methods_of(a, typ):
    for i, td in enumerate(a.typedefs):
        if a.s(td[1]) == typ:
            end = a.typedefs[i + 1][5] - 1 if i + 1 < len(a.typedefs) else len(a.methods)
            return {a.s(a.methods[mi][3]): mi for mi in range(td[5] - 1, end)}
    return {}


def run(a, mi, rules, names):
    """Interprets one populator method (straight-line code) into `rules`."""
    stack, local = [], {}
    code = tr.disassemble(a.body(mi))
    for off, op, arg, nxt in code:
        if op == 0x02:  # ldarg.0
            stack.append("this")
        elif 0x16 <= op <= 0x1E:
            stack.append(op - 0x16)
        elif op == 0x15:
            stack.append(-1)
        elif op in (0x1F, 0x20):
            stack.append(arg)
        elif 0x06 <= op <= 0x09:
            stack.append(local[op - 0x06])
        elif 0x0A <= op <= 0x0D:
            local[op - 0x0A] = stack.pop()
        elif op == 0x11:
            stack.append(local[arg & 0xFF])
        elif op == 0x13:
            local[arg & 0xFF] = stack.pop()
        elif op == 0x25:  # dup
            stack.append(stack[-1])
        elif op == 0x26:  # pop
            stack.pop()
        elif op == 0x7B:  # ldfld: one of the populator's conditions
            stack.pop()
            stack.append(("cond", a.token_name(arg & 0xFFFFFFFF).split(".")[-1]))
        elif op == 0x7E:  # ldsfld: a Rarity
            name = a.token_name(arg & 0xFFFFFFFF)
            stack.append(("rarity", name.split(".")[-1]))
        elif op == 0x8D:  # newarr
            stack.append([None] * stack.pop())
        elif op == 0xA2:  # stelem.ref
            v, i, arr = stack.pop(), stack.pop(), stack.pop()
            arr[i] = v
        elif op == 0xD0:  # ldtoken (constant array data)
            stack.append(("token", arg))
        elif op in (0x28, 0x6F):
            name = a.token_name(arg & 0xFFFFFFFF)
            n, has_this, returns = a.signature(arg & 0xFFFFFFFF)
            args = [stack.pop() for _ in range(n)][::-1]
            if has_this:
                stack.pop()
            short = name.split(".")[-1]
            if name == "R:RuntimeHelpers.InitializeArray":
                arr, token = args
                rva = a.field_rva.get((token[1] & 0xFFFFFF) - 1)
                arr[:] = list(struct.unpack_from("<%di" % len(arr), a.data, a.pe.off(rva)))
                continue
            if short == "Group":
                stack.append(list(args[0]))
            elif short == "Join":
                stack.append([c for part in args for c in part])
            elif short == "AddStopper":
                rules.append(rule("Any", 1, 1, [], [args[0]], names))
            elif short == "AddWithHardmode":
                rarity, den, early, hard, conds = args
                rules.append(rule(rarity[1], 1, den, [early], conds + [("cond", "EarlyMode")], names))
                rules.append(rule(rarity[1], 1, den, [hard], conds + [("cond", "HardMode")], names))
            elif short in ("AddQuestFish", "AddQuestFishForRemix"):
                rarity, den, item, conds = args
                r = rule(rarity[1], 1, den, [item], conds, names)
                r["quest"] = True
                if short.endswith("Remix"):
                    r["conditions"].append("Remix")
                rules.append(r)
            elif short == "Add":
                # Add(rarity, [numerator,] denominator, item or items, conditions)
                if len(args) == 5:
                    rarity, num, den, items, conds = args
                else:
                    rarity, den, items, conds = args
                    num = 1
                rules.append(rule(rarity[1], num, den, items if isinstance(items, list) else [items], conds, names))
            elif returns:
                stack.append(None)
        elif op == 0x2A:
            break
    return rules


def rule(rarity, num, den, items, conds, names):
    return {"rarity": rarity, "chance": [num, den], "items": [names.get(i, str(i)) for i in items],
            "conditions": [c[1] for c in conds]}


def extract(exe, ids):
    a = tr.Assembly(exe)
    names = {v: k for k, v in ids["ItemID"].items()}
    ms = methods_of(a, POPULATOR)
    order = []
    for off, op, arg, nxt in tr.disassemble(a.body(ms["Populate"])):
        if op in (0x28, 0x6F):
            n = a.token_name(arg & 0xFFFFFFFF).split(".")[-1]
            if n in ms:
                order.append(n)
    rules = []
    # Populate starts with AddStopper(AnyEnemies): an enemy on the line.
    rules.append(rule("Any", 1, 1, [], [("cond", "AnyEnemies")], names))
    for n in order:
        run(a, ms[n], rules, names)
    return rules


def main():
    ids = json.load(open(sys.argv[2]))
    rules = extract(sys.argv[1], ids)
    doc = ["Terraria's fishing catch table (GameContent.FishDropRules, from Terraria.exe by tools/terraria_fishing.py): "
           "the first rule whose conditions hold, whose chance roll (numerator in denominator) succeeds and whose rarity "
           "roll matches gives one of its items; a rule without items ends the search with nothing. Conditions and "
           "rarities are checked by scripts/items/fishing.gd."]
    with open(sys.argv[3], "w") as f:
        f.write('{\n\t"_doc": %s,\n\t"rules": [\n' % json.dumps(doc))
        f.write(",\n".join("\t\t" + json.dumps(r) for r in rules))
        f.write("\n\t]\n}\n")
    print("%d fishing rules" % len(rules))


if __name__ == "__main__":
    main()
