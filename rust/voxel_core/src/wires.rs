//! Terraria's wiring, as worldgen lays it: wire ("wire" decorations: a cell,
//! its colours in the style - 1 red, 2 blue, 4 green, 8 yellow) and actuators
//! ("actuator" decorations on a block). The game loads them into its wiring
//! (scripts/world/wiring.gd) and sends signals along them.

use crate::world::{Decoration, World};

type P = (i32, i32, i32);

pub const RED: i32 = 1;

/// Wire of `colour` from `from` to `to`: across x, then z, then up or down
/// (Terraria's wire runs in straight lines through whatever is there).
pub fn lay(w: &mut World, from: P, to: P, colour: i32) {
    let mut p = from;
    w.decorations.push(Decoration { kind: "wire".into(), pos: p, style: colour });
    for axis in [0, 2, 1] {
        let target = [to.0, to.1, to.2][axis];
        loop {
            let cur = [p.0, p.1, p.2][axis];
            if cur == target {
                break;
            }
            let step = (target - cur).signum();
            match axis {
                0 => p.0 += step,
                1 => p.1 += step,
                _ => p.2 += step,
            }
            w.decorations.push(Decoration { kind: "wire".into(), pos: p, style: colour });
        }
    }
}

/// An actuator on the block at `p`.
pub fn actuator(w: &mut World, p: P) {
    w.decorations.push(Decoration { kind: "actuator".into(), pos: p, style: 0 });
}

/// Every wired cell and its colours (tests).
#[cfg(test)]
pub fn cells(w: &World) -> std::collections::HashMap<P, i32> {
    let mut out = std::collections::HashMap::new();
    for d in w.decorations.iter().filter(|d| d.kind == "wire") {
        *out.entry(d.pos).or_insert(0) |= d.style;
    }
    out
}

/// Whether wire of `colour` joins `a` to `b` (cell to neighbouring cell).
#[cfg(test)]
pub fn joined(w: &World, a: P, b: P, colour: i32) -> bool {
    let cells = cells(w);
    let mut seen = std::collections::HashSet::new();
    let mut todo = vec![a];
    while let Some(p) = todo.pop() {
        if cells.get(&p).copied().unwrap_or(0) & colour == 0 || !seen.insert(p) {
            continue;
        }
        if p == b {
            return true;
        }
        for d in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            todo.push((p.0 + d.0, p.1 + d.1, p.2 + d.2));
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_runs_across_then_up_without_gaps() {
        let mut w = World::new();
        w.resize(32, 32, 32);
        lay(&mut w, (2, 3, 4), (6, 9, 1), RED);
        assert!(joined(&w, (2, 3, 4), (6, 9, 1), RED));
        assert_eq!(cells(&w).len(), 4 + 3 + 6 + 1);
        assert!(!joined(&w, (2, 3, 4), (6, 9, 1), 2), "only red");
    }
}
