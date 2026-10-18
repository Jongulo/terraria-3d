//! World storage, block definitions and Terraria-style flood-fill lighting.
//!
//! Light is packed per cell as four 4-bit channels: sun, red, green, blue.
//! Sunlight travels straight down without decay through open sky, down to
//! each column's "sky floor" (the ground as the world was made); everything
//! else, sunlight below the sky floor included, loses one level per block.
//! That is Terraria's light: ground you dig out keeps its background wall,
//! which stops sunlight, so a shaft darkens as it goes down.

use std::collections::{HashMap, HashSet, VecDeque};

pub const CS: i32 = 32;

pub const RENDER_NONE: u8 = 0;
pub const RENDER_CUBE: u8 = 1;
pub const RENDER_CUTOUT: u8 = 2;
pub const RENDER_CROSS: u8 = 3;
/// Drawn by the game (block models: hull, lathe, extruded... see
/// game/scripts/world/block_models.gd), not by the chunk mesher.
pub const RENDER_MODEL: u8 = 5;

pub const CH_SUN: usize = 0;

/// Liquids: one byte per cell, amount in the low 6 bits, type in the top 2.
pub const LIQ_NONE: u8 = 0;
pub const LIQ_WATER: u8 = 1;
pub const LIQ_LAVA: u8 = 2;
pub const LIQ_MAX: u8 = 63;
/// Lava glows orange like Terraria's.
pub const LAVA_EMIT: [u8; 3] = [14, 7, 2];

#[inline]
pub fn liq_pack(t: u8, amount: u8) -> u8 {
    if amount == 0 { 0 } else { (t << 6) | amount.min(LIQ_MAX) }
}

#[inline]
pub fn liq_unpack(v: u8) -> (u8, u8) {
    if v & LIQ_MAX == 0 { (LIQ_NONE, 0) } else { (v >> 6, v & LIQ_MAX) }
}
const SHIFT: [u16; 4] = [12, 8, 4, 0];

pub const DIRS: [(i32, i32, i32); 6] = [
    (1, 0, 0),
    (-1, 0, 0),
    (0, 1, 0),
    (0, -1, 0),
    (0, 0, 1),
    (0, 0, -1),
];
const DOWN: usize = 3;

#[derive(Clone, Debug, Default)]
pub struct BlockDef {
    pub name: String,
    pub render: u8,
    pub solid: bool,
    /// Blocks light and hides neighbouring faces.
    pub opaque: bool,
    /// Texture layers: top, side, bottom.
    pub tex: [u16; 3],
    pub variants: u8,
    pub emit: [u8; 3],
    /// A platform (not solid): you land on its top from above, and pass
    /// through it from below or sideways (physics::move_aabb).
    pub platform: bool,
    /// Lets sunlight straight down through (opaque otherwise): Terraria's leaf
    /// blocks, which block light but not the sun (nothing but walls does).
    pub sun_through: bool,
    /// Average colours of its top and side textures (far terrain, lod.rs).
    pub color_top: [u8; 3],
    pub color_side: [u8; 3],
    /// Grass (OptiFine's Better Grass, Fancy): a side whose neighbour one
    /// block down is the same grass shows the top texture, so a hillside is
    /// grass all the way down its steps (mesher.rs); far terrain draws its
    /// sides in the top's colour (lod.rs).
    pub better_grass: bool,
}

#[derive(Clone, Debug)]
pub struct Decoration {
    pub kind: String,
    pub pos: (i32, i32, i32),
    pub style: i32,
}

pub struct World {
    pub sx: i32,
    pub sy: i32,
    pub sz: i32,
    pub blocks: Vec<u16>,
    pub light: Vec<u16>,
    pub liquid: Vec<u8>,
    /// Liquid cells that may still move; only these are simulated.
    pub liquid_active: HashSet<(i32, i32, i32)>,
    pub liquid_tick: u64,
    pub defs: Vec<BlockDef>,
    pub decorations: Vec<Decoration>,
    pub spawn: (i32, i32, i32),
    pub seed: i32,
    /// World evil for the next generation: 0 random, 1 Corruption, 2 Crimson.
    pub gen_evil: i32,
    opaque: Vec<bool>,
    sun_through: Vec<bool>,
    solid: Vec<bool>,
    platform: Vec<bool>,
    track_dirty: bool,
    pub dirty: HashSet<(i32, i32, i32)>,
    pub chunk_version: HashMap<(i32, i32, i32), u64>,
    /// Hammered blocks (Terraria's half blocks and slopes): cell index -> shape
    /// (SHAPE_*). Sparse: only player-shaped cells are listed.
    pub shapes: HashMap<usize, u8>,
    /// Per column (x + z * sx): the top opaque cell when the world was made
    /// (-1 none). Sunlight falls freely only above it; dug-out cells at or
    /// below it get sunlight that fades one level per block, like Terraria's
    /// (where dug ground keeps its wall). Empty: taken from the blocks on the
    /// next full relight.
    pub sky_floor: Vec<i16>,
    /// Far terrain leaves out faces in the dark below this height (caves);
    /// above it (floating islands' shaded undersides) they're kept (lod.rs).
    pub lod_cave_level: i32,
}

/// Block shapes made with a hammer. A ramp rises toward its direction
/// (0 +z, 1 +x, 2 -z, 3 -x, as the game's wall normals); a ceiling ramp is a
/// ramp turned upside down.
pub const SHAPE_FULL: u8 = 0;
pub const SHAPE_HALF: u8 = 1;
pub const SHAPE_RAMP: u8 = 2; // 2..=5
pub const SHAPE_CEILING: u8 = 6; // 6..=9
pub const SHAPE_COUNT: u8 = 10;

/// Ramps are pixel staircases, like Terraria's slopes: this many steps across
/// a block (one per art pixel of a block face).
pub const RAMP_STEPS: f32 = 16.0;

/// A ramp's surface height (0..1) at `t` along it: the top of the step there.
/// The first step is a pixel high, the last reaches the top.
#[inline]
pub fn ramp_height(t: f32) -> f32 {
    (((t * RAMP_STEPS).floor() + 1.0).min(RAMP_STEPS)) / RAMP_STEPS
}

/// How far along a ramp of direction `dir` a point is (0 at the low edge, 1 at
/// the high one), from its position (lx, lz) inside the cell.
#[inline]
pub fn ramp_t(dir: u8, lx: f32, lz: f32) -> f32 {
    match dir {
        0 => lz,
        1 => lx,
        2 => 1.0 - lz,
        _ => 1.0 - lx,
    }
}

impl World {
    pub fn new() -> Self {
        let mut w = Self {
            sx: 0,
            sy: 0,
            sz: 0,
            blocks: Vec::new(),
            light: Vec::new(),
            liquid: Vec::new(),
            liquid_active: HashSet::new(),
            liquid_tick: 0,
            defs: vec![BlockDef {
                name: "air".into(),
                ..Default::default()
            }],
            decorations: Vec::new(),
            spawn: (0, 0, 0),
            seed: 0,
            gen_evil: 0,
            opaque: Vec::new(),
            sun_through: Vec::new(),
            solid: Vec::new(),
            platform: Vec::new(),
            track_dirty: false,
            dirty: HashSet::new(),
            lod_cave_level: i32::MAX,
            chunk_version: HashMap::new(),
            shapes: HashMap::new(),
            sky_floor: Vec::new(),
        };
        w.rebuild_tables();
        w
    }

    pub fn resize(&mut self, sx: i32, sy: i32, sz: i32) {
        self.sx = sx;
        self.sy = sy;
        self.sz = sz;
        let n = (sx * sy * sz) as usize;
        self.blocks = vec![0; n];
        self.light = vec![0; n];
        self.liquid = vec![0; n];
        self.liquid_active.clear();
        self.decorations.clear();
        self.dirty.clear();
        self.chunk_version.clear();
        self.shapes.clear();
        self.sky_floor.clear();
    }

    /// Takes the sky floor from the blocks as they are (the world as made).
    pub fn snapshot_sky_floor(&mut self) {
        let (sx, sy, sz) = (self.sx, self.sy, self.sz);
        let mut floor = vec![-1i16; (sx * sz) as usize];
        for z in 0..sz {
            for x in 0..sx {
                let base = self.idx(x, 0, z);
                if let Some(y) = (0..sy).rev().find(|&y| self.stops_sun(base + y as usize)) {
                    floor[(x + z * sx) as usize] = y as i16;
                }
            }
        }
        self.sky_floor = floor;
    }

    /// The column's sky floor (see `sky_floor`), -1 if none.
    #[inline]
    pub fn sky_floor_at(&self, x: i32, z: i32) -> i32 {
        if self.sky_floor.is_empty() {
            return -1;
        }
        self.sky_floor[(x + z * self.sx) as usize] as i32
    }

    /// The hammered shape of a cell (SHAPE_FULL for most).
    #[inline]
    pub fn shape_at(&self, x: i32, y: i32, z: i32) -> u8 {
        if self.shapes.is_empty() || !self.in_bounds(x, y, z) {
            return SHAPE_FULL;
        }
        *self.shapes.get(&self.idx(x, y, z)).unwrap_or(&SHAPE_FULL)
    }

    /// Reshapes a solid, opaque cube block (a hammer hit). Returns false if the
    /// cell can't take a shape.
    pub fn set_shape(&mut self, x: i32, y: i32, z: i32, shape: u8) -> bool {
        if !self.in_bounds(x, y, z) || shape >= SHAPE_COUNT {
            return false;
        }
        let i = self.idx(x, y, z);
        let id = self.blocks[i];
        let d = self.def(id);
        // Platforms take a ramp: Terraria's platform stairs.
        let stair = d.platform && (shape == SHAPE_FULL || (SHAPE_RAMP..SHAPE_CEILING).contains(&shape));
        if id == 0 || (!stair && (!d.solid || !d.opaque || d.render != RENDER_CUBE)) {
            return false;
        }
        let platform = d.platform;
        let old = self.shape_at(x, y, z);
        if old == shape {
            return true;
        }
        if shape == SHAPE_FULL {
            self.shapes.remove(&i);
        } else {
            self.shapes.insert(i, shape);
        }
        self.mark_dirty(x, y, z);
        // Shaped blocks let light through (and show their neighbours' faces).
        if !platform && (old == SHAPE_FULL) != (shape == SHAPE_FULL) {
            self.relight_cell(x, y, z);
        }
        true
    }

    /// Opaque cell: an opaque block that hasn't been hammered into a shape.
    #[inline]
    fn opaque_cell(&self, i: usize) -> bool {
        self.is_opaque_id(self.blocks[i]) && (self.shapes.is_empty() || !self.shapes.contains_key(&i))
    }

    pub fn set_def(&mut self, id: u16, def: BlockDef) {
        let id = id as usize;
        if self.defs.len() <= id {
            self.defs.resize(id + 1, BlockDef::default());
        }
        self.defs[id] = def;
        self.rebuild_tables();
    }

    fn rebuild_tables(&mut self) {
        self.opaque = self.defs.iter().map(|d| d.opaque).collect();
        self.sun_through = self.defs.iter().map(|d| d.sun_through).collect();
        self.solid = self.defs.iter().map(|d| d.solid).collect();
        self.platform = self.defs.iter().map(|d| d.platform).collect();
    }

    pub fn id_of(&self, name: &str) -> u16 {
        self.defs
            .iter()
            .position(|d| d.name == name)
            .unwrap_or(0) as u16
    }

    #[inline]
    pub fn in_bounds(&self, x: i32, y: i32, z: i32) -> bool {
        x >= 0 && y >= 0 && z >= 0 && x < self.sx && y < self.sy && z < self.sz
    }

    /// Column-major: each (x, z) column is contiguous in y.
    #[inline]
    pub fn idx(&self, x: i32, y: i32, z: i32) -> usize {
        ((z * self.sx + x) * self.sy + y) as usize
    }

    #[inline]
    pub fn get(&self, x: i32, y: i32, z: i32) -> u16 {
        if self.in_bounds(x, y, z) {
            self.blocks[self.idx(x, y, z)]
        } else {
            0
        }
    }

    #[inline]
    pub fn def(&self, id: u16) -> &BlockDef {
        self.defs.get(id as usize).unwrap_or(&self.defs[0])
    }

    #[inline]
    pub fn is_opaque_id(&self, id: u16) -> bool {
        *self.opaque.get(id as usize).unwrap_or(&false)
    }

    /// Whether a cell's block lets sunlight straight down through it.
    #[inline]
    pub fn sun_through_cell(&self, i: usize) -> bool {
        *self.sun_through.get(self.blocks[i] as usize).unwrap_or(&false)
    }

    /// Whether a cell stops the sun coming straight down.
    #[inline]
    fn stops_sun(&self, i: usize) -> bool {
        self.opaque_cell(i) && !self.sun_through_cell(i)
    }

    /// Out of bounds counts as opaque only below the world.
    #[inline]
    pub fn is_opaque(&self, x: i32, y: i32, z: i32) -> bool {
        if !self.in_bounds(x, y, z) {
            return y < 0;
        }
        self.opaque_cell(self.idx(x, y, z))
    }

    /// Out of bounds is solid so nothing can leave the world.
    #[inline]
    pub fn is_solid(&self, x: i32, y: i32, z: i32) -> bool {
        if !self.in_bounds(x, y, z) {
            return y < self.sy;
        }
        *self
            .solid
            .get(self.blocks[self.idx(x, y, z)] as usize)
            .unwrap_or(&false)
    }

    /// A platform: its top (y + 1) holds you up from above.
    #[inline]
    pub fn is_platform(&self, x: i32, y: i32, z: i32) -> bool {
        self.in_bounds(x, y, z) && *self.platform.get(self.blocks[self.idx(x, y, z)] as usize).unwrap_or(&false)
    }

    #[inline]
    pub fn light_at(&self, x: i32, y: i32, z: i32) -> u16 {
        if !self.in_bounds(x, y, z) {
            return if y >= self.sy { 15 << SHIFT[CH_SUN] } else { 0 };
        }
        self.light[self.idx(x, y, z)]
    }

    #[inline]
    fn ch(&self, i: usize, c: usize) -> u8 {
        ((self.light[i] >> SHIFT[c]) & 15) as u8
    }

    #[inline]
    fn set_ch(&mut self, i: usize, c: usize, v: u8) {
        self.light[i] = (self.light[i] & !(15 << SHIFT[c])) | ((v as u16) << SHIFT[c]);
    }

    pub fn chunk_count(&self) -> (i32, i32, i32) {
        (
            (self.sx + CS - 1) / CS,
            (self.sy + CS - 1) / CS,
            (self.sz + CS - 1) / CS,
        )
    }

    /// Marks every chunk whose mesh samples this cell (meshing reads a 1-cell border).
    fn mark_dirty(&mut self, x: i32, y: i32, z: i32) {
        if !self.track_dirty {
            return;
        }
        let (cx0, cx1) = ((x - 1).div_euclid(CS), (x + 1).div_euclid(CS));
        let (cy0, cy1) = ((y - 1).div_euclid(CS), (y + 1).div_euclid(CS));
        let (cz0, cz1) = ((z - 1).div_euclid(CS), (z + 1).div_euclid(CS));
        let (nx, ny, nz) = self.chunk_count();
        for cx in cx0.max(0)..=cx1.min(nx - 1) {
            for cy in cy0.max(0)..=cy1.min(ny - 1) {
                for cz in cz0.max(0)..=cz1.min(nz - 1) {
                    if self.dirty.insert((cx, cy, cz)) {
                        *self.chunk_version.entry((cx, cy, cz)).or_insert(0) += 1;
                    }
                }
            }
        }
    }

    pub fn take_dirty(&mut self) -> Vec<(i32, i32, i32)> {
        self.dirty.drain().collect()
    }

    pub fn version(&self, c: (i32, i32, i32)) -> u64 {
        *self.chunk_version.get(&c).unwrap_or(&0)
    }

    // ---------------------------------------------------------------- lighting

    /// Recomputes all light from scratch (after generation or loading).
    pub fn compute_all_light(&mut self) {
        self.track_dirty = false;
        if self.sky_floor.len() != (self.sx * self.sz) as usize {
            self.snapshot_sky_floor();
        }
        self.light.iter_mut().for_each(|l| *l = 0);
        let (sx, sy, sz) = (self.sx, self.sy, self.sz);

        // Straight-down sunlight per column, down to the sky floor.
        for z in 0..sz {
            for x in 0..sx {
                let base = self.idx(x, 0, z);
                let floor = self.sky_floor_at(x, z);
                for y in (0..sy).rev() {
                    if y <= floor || self.stops_sun(base + y as usize) {
                        break;
                    }
                    self.light[base + y as usize] = 15 << SHIFT[CH_SUN];
                }
            }
        }

        // Seed sideways spreading from sunlit cells next to shaded air.
        let mut queue = VecDeque::new();
        for z in 0..sz {
            for x in 0..sx {
                let base = self.idx(x, 0, z);
                for y in (0..sy).rev() {
                    let i = base + y as usize;
                    if self.ch(i, CH_SUN) != 15 {
                        break;
                    }
                    // Sideways into shade, or down past the sky floor (a dug shaft).
                    let spreads = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, -1, 0)].iter().any(|(dx, dy, dz)| {
                        let (nx, ny, nz) = (x + dx, y + dy, z + dz);
                        self.in_bounds(nx, ny, nz) && {
                            let j = self.idx(nx, ny, nz);
                            !self.opaque_cell(j) && self.ch(j, CH_SUN) < 14
                        }
                    });
                    if spreads {
                        queue.push_back((x, y, z));
                    }
                }
            }
        }
        self.propagate(CH_SUN, &mut queue);

        // Emissive blocks.
        let mut emitters = VecDeque::new();
        for z in 0..sz {
            for x in 0..sx {
                for y in 0..sy {
                    let i = self.idx(x, y, z);
                    let e = self.cell_emit(i);
                    if e != [0, 0, 0] {
                        for c in 0..3 {
                            self.set_ch(i, c + 1, e[c]);
                        }
                        emitters.push_back((x, y, z));
                    }
                }
            }
        }
        for c in 1..4 {
            let mut q = emitters.clone();
            self.propagate(c, &mut q);
        }
        self.track_dirty = true;
    }

    fn propagate(&mut self, c: usize, queue: &mut VecDeque<(i32, i32, i32)>) {
        while let Some((x, y, z)) = queue.pop_front() {
            let v = self.ch(self.idx(x, y, z), c);
            if v <= 1 {
                continue;
            }
            for (d, (dx, dy, dz)) in DIRS.iter().enumerate() {
                let (nx, ny, nz) = (x + dx, y + dy, z + dz);
                if !self.in_bounds(nx, ny, nz) {
                    continue;
                }
                let j = self.idx(nx, ny, nz);
                let straight_sun = c == CH_SUN && d == DOWN && v == 15;
                if self.opaque_cell(j) && !(straight_sun && self.sun_through_cell(j)) {
                    continue;
                }
                let nv = if straight_sun && ny > self.sky_floor_at(nx, nz) {
                    15
                } else {
                    v - 1
                };
                if nv > self.ch(j, c) {
                    self.set_ch(j, c, nv);
                    self.mark_dirty(nx, ny, nz);
                    queue.push_back((nx, ny, nz));
                }
            }
        }
    }

    /// Clears light that depended on (x, y, z) and returns border cells to relight from.
    fn remove_light(&mut self, c: usize, x: i32, y: i32, z: i32, relight: &mut VecDeque<(i32, i32, i32)>) {
        let i = self.idx(x, y, z);
        let start = self.ch(i, c);
        self.set_ch(i, c, 0);
        let mut queue = VecDeque::from([(x, y, z, start)]);
        while let Some((x, y, z, v)) = queue.pop_front() {
            for (d, (dx, dy, dz)) in DIRS.iter().enumerate() {
                let (nx, ny, nz) = (x + dx, y + dy, z + dz);
                if !self.in_bounds(nx, ny, nz) {
                    continue;
                }
                let j = self.idx(nx, ny, nz);
                let nv = self.ch(j, c);
                if nv == 0 {
                    continue;
                }
                let dependent = nv < v || (c == CH_SUN && d == DOWN && v == 15 && nv == 15);
                if dependent {
                    self.set_ch(j, c, 0);
                    self.mark_dirty(nx, ny, nz);
                    queue.push_back((nx, ny, nz, nv));
                } else {
                    relight.push_back((nx, ny, nz));
                }
            }
        }
    }

    /// Light a cell emits: its block's, or lava's if it holds lava.
    pub fn cell_emit(&self, i: usize) -> [u8; 3] {
        let e = self.defs.get(self.blocks[i] as usize).map_or([0, 0, 0], |d| d.emit);
        if liq_unpack(self.liquid[i]).0 == LIQ_LAVA {
            [e[0].max(LAVA_EMIT[0]), e[1].max(LAVA_EMIT[1]), e[2].max(LAVA_EMIT[2])]
        } else {
            e
        }
    }

    /// Recomputes light around a cell whose opacity or emission changed.
    pub fn relight_cell(&mut self, x: i32, y: i32, z: i32) {
        let i = self.idx(x, y, z);
        let emit = self.cell_emit(i);
        for c in 0..4 {
            let mut relight = VecDeque::new();
            self.remove_light(c, x, y, z, &mut relight);
            for (dx, dy, dz) in DIRS {
                if self.in_bounds(x + dx, y + dy, z + dz) {
                    relight.push_back((x + dx, y + dy, z + dz));
                }
            }
            if y == self.sy - 1 && c == CH_SUN && !self.opaque_cell(i) {
                self.set_ch(i, c, 15);
                relight.push_back((x, y, z));
            }
            if c > 0 && emit[c - 1] > 0 {
                self.set_ch(i, c, emit[c - 1]);
                relight.push_back((x, y, z));
            }
            self.propagate(c, &mut relight);
        }
    }

    /// Sets a block and incrementally updates lighting, liquids and dirty chunks.
    /// Solid blocks displace any liquid in their cell.
    pub fn set(&mut self, x: i32, y: i32, z: i32, id: u16) -> bool {
        if !self.in_bounds(x, y, z) {
            return false;
        }
        let i = self.idx(x, y, z);
        if self.blocks[i] == id {
            return true;
        }
        self.blocks[i] = id;
        self.shapes.remove(&i);
        if self.is_solid(x, y, z) {
            self.liquid[i] = 0;
        }
        self.mark_dirty(x, y, z);
        self.relight_cell(x, y, z);
        self.activate_liquid_around(x, y, z);
        true
    }

    #[inline]
    pub fn liquid_at(&self, x: i32, y: i32, z: i32) -> (u8, u8) {
        if !self.in_bounds(x, y, z) {
            return (LIQ_NONE, 0);
        }
        liq_unpack(self.liquid[self.idx(x, y, z)])
    }

    /// Sets a cell's liquid (buckets, flow), keeping light and meshes in sync.
    pub fn set_liquid(&mut self, x: i32, y: i32, z: i32, t: u8, amount: u8) -> bool {
        if !self.in_bounds(x, y, z) || (amount > 0 && self.is_solid(x, y, z)) {
            return false;
        }
        let i = self.idx(x, y, z);
        let old = self.liquid[i];
        let new = liq_pack(t, amount);
        if old == new {
            return true;
        }
        let was_lava = liq_unpack(old).0 == LIQ_LAVA;
        self.liquid[i] = new;
        self.mark_dirty(x, y, z);
        if was_lava != (liq_unpack(new).0 == LIQ_LAVA) {
            self.relight_cell(x, y, z);
        }
        self.activate_liquid_around(x, y, z);
        true
    }

    /// Wakes the liquid simulation for a cell and its neighbours.
    pub fn activate_liquid_around(&mut self, x: i32, y: i32, z: i32) {
        for (dx, dy, dz) in [(0, 0, 0), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            let (nx, ny, nz) = (x + dx, y + dy, z + dz);
            if self.in_bounds(nx, ny, nz) && self.liquid[self.idx(nx, ny, nz)] != 0 {
                self.liquid_active.insert((nx, ny, nz));
            }
        }
    }

    /// Topmost solid block in a column, or -1.
    pub fn surface_y(&self, x: i32, z: i32) -> i32 {
        if !self.in_bounds(x, 0, z) {
            return -1;
        }
        (0..self.sy)
            .rev()
            .find(|&y| self.is_solid(x, y, z))
            .unwrap_or(-1)
    }

    pub fn enable_dirty_tracking(&mut self, on: bool) {
        self.track_dirty = on;
    }
}

/// A room found by `World::flood_room` (Terraria's housing check).
pub struct Room {
    /// The open cells of the room.
    pub cells: Vec<(i32, i32, i32)>,
    /// It spread past `max_cells` or out of the world: a hole in a wall
    /// (or a room too big).
    pub overflow: bool,
    /// Every block id in the room or around it (walls, floor, ceiling).
    pub ids: Vec<u16>,
    /// Cells to stand in: something solid (or a `walls` block, a platform)
    /// underfoot and room for the head above.
    pub floor: Vec<(i32, i32, i32)>,
}

impl World {
    /// Floods the open cells around `start` (not solid, not one of `walls`:
    /// doors and platforms, which close a room off like walls), up to
    /// `max_cells`. Terraria's housing check, in 3D.
    pub fn flood_room(&self, start: (i32, i32, i32), max_cells: usize, walls: &[u16]) -> Room {
        let open = |x: i32, y: i32, z: i32| -> bool {
            self.in_bounds(x, y, z) && !self.is_solid(x, y, z) && !walls.contains(&self.get(x, y, z))
        };
        let mut room = Room { cells: Vec::new(), overflow: false, ids: Vec::new(), floor: Vec::new() };
        if !open(start.0, start.1, start.2) {
            return room;
        }
        let mut seen: HashSet<(i32, i32, i32)> = HashSet::from([start]);
        let mut queue = VecDeque::from([start]);
        let mut ids: HashSet<u16> = HashSet::new();
        while let Some((x, y, z)) = queue.pop_front() {
            room.cells.push((x, y, z));
            ids.insert(self.get(x, y, z));
            if room.cells.len() > max_cells {
                room.overflow = true;
                break;
            }
            for (dx, dy, dz) in DIRS {
                let n = (x + dx, y + dy, z + dz);
                if !self.in_bounds(n.0, n.1, n.2) {
                    room.overflow = true;
                    continue;
                }
                if seen.contains(&n) {
                    continue;
                }
                if open(n.0, n.1, n.2) {
                    seen.insert(n);
                    queue.push_back(n);
                } else {
                    ids.insert(self.get(n.0, n.1, n.2));
                }
            }
        }
        if !room.overflow {
            for &(x, y, z) in &room.cells {
                let below = self.get(x, y - 1, z);
                let stands = y > 0 && (self.is_solid(x, y - 1, z) || walls.contains(&below));
                if stands && seen.contains(&(x, y + 1, z)) {
                    room.floor.push((x, y, z));
                }
            }
        }
        let mut ids: Vec<u16> = ids.into_iter().collect();
        ids.sort_unstable();
        room.ids = ids;
        room
    }

    /// Cells in the box `center` ± `extent` holding one of `ids` (at most
    /// `max`), e.g. the chairs around the player for the housing check.
    pub fn find_blocks(&self, center: (i32, i32, i32), extent: (i32, i32, i32), ids: &[u16], max: usize) -> Vec<(i32, i32, i32)> {
        let mut out = Vec::new();
        for y in (center.1 - extent.1).max(0)..=(center.1 + extent.1).min(self.sy - 1) {
            for z in (center.2 - extent.2).max(0)..=(center.2 + extent.2).min(self.sz - 1) {
                for x in (center.0 - extent.0).max(0)..=(center.0 + extent.0).min(self.sx - 1) {
                    if ids.contains(&self.blocks[self.idx(x, y, z)]) {
                        out.push((x, y, z));
                        if out.len() >= max {
                            return out;
                        }
                    }
                }
            }
        }
        out
    }
}

impl Default for World {
    fn default() -> Self {
        Self::new()
    }
}

pub fn unpack_light(l: u16) -> [u8; 4] {
    [
        ((l >> SHIFT[0]) & 15) as u8,
        ((l >> SHIFT[1]) & 15) as u8,
        ((l >> SHIFT[2]) & 15) as u8,
        ((l >> SHIFT[3]) & 15) as u8,
    ]
}

#[cfg(test)]
pub mod tests {
    use super::*;

    pub fn test_world() -> World {
        let mut w = World::new();
        w.set_def(
            1,
            BlockDef {
                name: "stone".into(),
                render: RENDER_CUBE,
                solid: true,
                opaque: true,
                variants: 1,
                ..Default::default()
            },
        );
        w.set_def(
            2,
            BlockDef {
                name: "torch".into(),
                render: RENDER_CROSS,
                emit: [14, 10, 6],
                variants: 1,
                ..Default::default()
            },
        );
        w.resize(64, 64, 64);
        // Solid ground up to y = 31.
        for z in 0..64 {
            for x in 0..64 {
                for y in 0..32 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 1;
                }
            }
        }
        w.compute_all_light();
        w
    }

    #[test]
    fn sunlight_reaches_surface_not_underground() {
        let w = test_world();
        assert_eq!(unpack_light(w.light_at(10, 32, 10))[0], 15);
        assert_eq!(unpack_light(w.light_at(10, 20, 10))[0], 0);
    }

    #[test]
    fn digging_a_shaft_lets_sun_in_and_refilling_removes_it() {
        let mut w = test_world();
        for y in 20..32 {
            w.set(10, y, 10, 0);
        }
        // Like Terraria's: below the ground as made, sunlight fades a level a
        // block (the open surface cell at y = 32 has 15).
        assert_eq!(unpack_light(w.light_at(10, 31, 10))[0], 14);
        assert_eq!(unpack_light(w.light_at(10, 25, 10))[0], 8);
        assert_eq!(unpack_light(w.light_at(10, 20, 10))[0], 3);
        // Side pocket at the bottom gets attenuated light.
        w.set(11, 20, 10, 0);
        assert_eq!(unpack_light(w.light_at(11, 20, 10))[0], 2);
        // A full relight (loading) agrees.
        w.compute_all_light();
        assert_eq!(unpack_light(w.light_at(10, 20, 10))[0], 3);
        // Cap the shaft: everything below goes dark.
        w.set(10, 31, 10, 1);
        assert_eq!(unpack_light(w.light_at(10, 20, 10))[0], 0);
        assert_eq!(unpack_light(w.light_at(11, 20, 10))[0], 0);
    }

    #[test]
    fn open_sky_above_the_ground_stays_fully_lit() {
        let mut w = test_world();
        // A pillar built on the surface, then taken away: open sky again.
        for y in 32..40 {
            w.set(20, y, 20, 1);
        }
        assert_eq!(unpack_light(w.light_at(20, 40, 20))[0], 15);
        for y in 32..40 {
            w.set(20, y, 20, 0);
        }
        assert_eq!(unpack_light(w.light_at(20, 32, 20))[0], 15);
        // A pit there when the world was made (a chasm, a lake bed) is lit to the bottom.
        let mut w = test_world();
        for y in 20..32 {
            let i = w.idx(30, y, 30);
            w.blocks[i] = 0;
        }
        w.snapshot_sky_floor();
        w.compute_all_light();
        assert_eq!(unpack_light(w.light_at(30, 20, 30))[0], 15);
    }

    #[test]
    fn flood_room_finds_closed_rooms() {
        let mut w = test_world();
        // A 4x3x4 room of stone (walls 1 thick) on the ground, with a door (id 2) in a wall.
        for x in 10..16 {
            for y in 32..37 {
                for z in 10..16 {
                    let edge = x == 10 || x == 15 || y == 32 || y == 36 || z == 10 || z == 15;
                    w.set(x, y, z, if edge { 1 } else { 0 });
                }
            }
        }
        w.set(10, 33, 12, 2);
        let room = w.flood_room((12, 33, 12), 500, &[2]);
        assert!(!room.overflow);
        assert_eq!(room.cells.len(), 4 * 3 * 4);
        assert!(room.ids.contains(&1) && room.ids.contains(&2));
        // Standing spots: the floor layer (y 33), with room above.
        assert_eq!(room.floor.len(), 16);
        // Not counting the door as a wall: it leaks out.
        assert!(w.flood_room((12, 33, 12), 500, &[]).overflow);
        // A hole in the roof leaks too.
        w.set(12, 36, 12, 0);
        assert!(w.flood_room((12, 33, 12), 500, &[2]).overflow);
        // Starting in a solid block: nothing.
        assert!(w.flood_room((10, 34, 12), 500, &[2]).cells.is_empty());
        assert_eq!(w.find_blocks((12, 33, 12), (5, 5, 5), &[2], 10), vec![(10, 33, 12)]);
    }

    #[test]
    fn torch_lights_cave_and_removal_clears_it() {
        let mut w = test_world();
        for x in 5..20 {
            w.set(x, 10, 10, 0);
        }
        w.set(5, 10, 10, 2);
        assert_eq!(unpack_light(w.light_at(5, 10, 10))[1], 14);
        assert_eq!(unpack_light(w.light_at(9, 10, 10))[1], 10);
        assert_eq!(unpack_light(w.light_at(9, 10, 10))[3], 2);
        w.set(5, 10, 10, 0);
        assert_eq!(unpack_light(w.light_at(9, 10, 10)), [0, 0, 0, 0]);
    }

    #[test]
    fn set_marks_neighbour_chunks_dirty() {
        let mut w = test_world();
        w.take_dirty();
        w.set(32, 31, 5, 0);
        let d: HashSet<_> = w.take_dirty().into_iter().collect();
        assert!(d.contains(&(0, 0, 0)) && d.contains(&(1, 0, 0)));
    }

    #[test]
    fn only_solid_cubes_take_shapes_and_light_gets_in() {
        let mut w = test_world();
        w.compute_all_light();
        assert!(!w.set_shape(10, 40, 10, SHAPE_HALF), "air can't be shaped");
        w.set(10, 32, 10, 1);
        w.set(10, 33, 10, 1);
        assert_eq!(w.light_at(10, 32, 10) >> 12, 0);
        assert!(w.set_shape(10, 33, 10, SHAPE_HALF) && w.shape_at(10, 33, 10) == SHAPE_HALF);
        assert!(!w.is_opaque(10, 33, 10) && w.is_solid(10, 33, 10));
        assert!(unpack_light(w.light_at(10, 33, 10))[0] > 10, "sunlight gets into a half block");
        w.compute_all_light();
        assert!(unpack_light(w.light_at(10, 33, 10))[0] > 10, "and stays lit when the whole world is relit");
        w.set(10, 33, 10, 0);
        w.set(10, 33, 10, 1);
        assert_eq!(w.shape_at(10, 33, 10), SHAPE_FULL, "a block placed after breaking one starts whole");
        assert!(w.set_shape(10, 33, 10, SHAPE_RAMP) && w.set_shape(10, 33, 10, SHAPE_FULL) && w.shapes.is_empty());
    }
}
