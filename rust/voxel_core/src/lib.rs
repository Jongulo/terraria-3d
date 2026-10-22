//! Godot bindings for the voxel core. All heavy lifting lives in the pure-Rust
//! modules; this file converts types and manages threads.

pub mod cabins;
pub mod caves;
pub mod dungeon;
pub mod fishing;
pub mod hives;
pub mod liquid;
pub mod lod;
pub mod mesher;
pub mod mushroom;
pub mod physics;
pub mod save;
pub mod shrines;
pub mod shrink;
pub mod surface;
pub mod hell;
pub mod terrain;
pub mod world;
pub mod worldgen;

use godot::prelude::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex, RwLock};
use world::{BlockDef, World};

struct VoxelExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VoxelExtension {}

type ChunkPos = (i32, i32, i32);

struct Shared {
    world: RwLock<World>,
    progress: AtomicU32,
    busy: AtomicBool,
    message: Mutex<String>,
}

struct MeshResult {
    chunk: ChunkPos,
    version: u64,
    mesh: mesher::ChunkMesh,
}

/// A far-terrain tile: (level, tile x, tile z) and its mesh.
struct LodResult {
    tile: (i32, i32, i32),
    mesh: lod::LodMesh,
}

/// Work for the mesh workers: a chunk, or a far-terrain tile (level, x, z).
enum Job {
    Chunk(ChunkPos),
    Lod(i32, i32, i32),
}

/// Owns the voxel world. Generation/loading run on a background thread
/// (poll `is_busy`); chunk meshes are built by a worker pool (`request_mesh`
/// then `poll_meshes`).
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct VoxelWorld {
    shared: Arc<Shared>,
    job_tx: Option<Sender<Job>>,
    result_rx: Receiver<MeshResult>,
    lod_rx: Receiver<LodResult>,
    applied: HashMap<ChunkPos, u64>,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for VoxelWorld {
    fn init(base: Base<RefCounted>) -> Self {
        let shared = Arc::new(Shared {
            world: RwLock::new(World::new()),
            progress: AtomicU32::new(0),
            busy: AtomicBool::new(false),
            message: Mutex::new(String::new()),
        });
        let (job_tx, job_rx) = channel::<Job>();
        let (result_tx, result_rx) = channel();
        let (lod_tx, lod_rx) = channel::<LodResult>();
        let job_rx = Arc::new(Mutex::new(job_rx));
        let workers = std::thread::available_parallelism().map_or(4, |n| n.get()).saturating_sub(2).max(2);
        for _ in 0..workers {
            let (shared, job_rx, result_tx, lod_tx) = (shared.clone(), job_rx.clone(), result_tx.clone(), lod_tx.clone());
            std::thread::spawn(move || {
                loop {
                    let job = job_rx.lock().unwrap().recv();
                    let Ok(job) = job else { break };
                    match job {
                        Job::Chunk(chunk) => {
                            let w = shared.world.read().unwrap();
                            let version = w.version(chunk);
                            let mesh = mesher::mesh_chunk(&w, chunk.0, chunk.1, chunk.2);
                            drop(w);
                            if result_tx.send(MeshResult { chunk, version, mesh }).is_err() {
                                break;
                            }
                        }
                        Job::Lod(level, x, z) => {
                            // Locks the world a layer at a time: a far tile
                            // takes a while, and the game needs to write.
                            let mesh = lod::mesh_lod(&shared.world, level as u32, x, z);
                            if lod_tx.send(LodResult { tile: (level, x, z), mesh }).is_err() {
                                break;
                            }
                        }
                    }
                }
            });
        }
        Self {
            shared,
            job_tx: Some(job_tx),
            result_rx,
            lod_rx,
            applied: HashMap::new(),
            base,
        }
    }
}

fn val(d: &VarDictionary, key: &str) -> Variant {
    d.get_or_nil(&key.to_variant())
}

fn int_of(v: &Variant, default: i64) -> i64 {
    v.try_to::<i64>().unwrap_or(default)
}

/// A Color variant as 0-255 RGB (grey when missing).
fn color8(v: Variant) -> [u8; 3] {
    let c = v.try_to::<Color>().unwrap_or(Color::from_rgb(0.5, 0.5, 0.5));
    let to8 = |f: f32| (f * 255.0).round().clamp(0.0, 255.0) as u8;
    [to8(c.r), to8(c.g), to8(c.b)]
}

fn v3(v: Vector3) -> [f32; 3] {
    [v.x, v.y, v.z]
}

fn surface_arrays(s: &mesher::Surface) -> Variant {
    if s.is_empty() {
        return Variant::nil();
    }
    let mut arr = VarArray::new();
    let verts: Vec<Vector3> = s.verts.iter().map(|v| Vector3::new(v[0], v[1], v[2])).collect();
    let normals: Vec<Vector3> = s.normals.iter().map(|v| Vector3::new(v[0], v[1], v[2])).collect();
    let colors: Vec<Color> = s.colors.iter().map(|c| Color::from_rgba(c[0], c[1], c[2], c[3])).collect();
    let uvs: Vec<Vector2> = s.uvs.iter().map(|v| Vector2::new(v[0], v[1])).collect();
    let uv2s: Vec<Vector2> = s.uv2s.iter().map(|v| Vector2::new(v[0], v[1])).collect();
    // Mesh.ARRAY_* order: VERTEX, NORMAL, TANGENT, COLOR, TEX_UV, TEX_UV2,
    // CUSTOM0..3, BONES, WEIGHTS, INDEX.
    arr.push(&PackedVector3Array::from(verts).to_variant());
    arr.push(&PackedVector3Array::from(normals).to_variant());
    arr.push(&Variant::nil());
    arr.push(&PackedColorArray::from(colors).to_variant());
    arr.push(&PackedVector2Array::from(uvs).to_variant());
    arr.push(&PackedVector2Array::from(uv2s).to_variant());
    for _ in 0..6 {
        arr.push(&Variant::nil());
    }
    arr.push(&PackedInt32Array::from(s.indices.clone()).to_variant());
    arr.to_variant()
}

impl VoxelWorld {
    fn hit_dict(hit: Option<physics::RayHit>) -> VarDictionary {
        match hit {
            Some(h) => vdict! {
                "block" => Vector3i::new(h.block.0, h.block.1, h.block.2),
                "normal" => Vector3i::new(h.normal.0, h.normal.1, h.normal.2),
                "id" => h.id as i32,
                "distance" => h.distance,
                "liquid" => h.liquid as i32,
            },
            None => VarDictionary::new(),
        }
    }

    fn run_background(&self, task: impl FnOnce(&mut World, &AtomicU32) -> Result<String, String> + Send + 'static) {
        if self.shared.busy.swap(true, Ordering::SeqCst) {
            godot_error!("VoxelWorld is already busy");
            return;
        }
        self.shared.progress.store(0f32.to_bits(), Ordering::Relaxed);
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            let mut w = shared.world.write().unwrap();
            w.enable_dirty_tracking(false);
            let result = task(&mut w, &shared.progress);
            w.enable_dirty_tracking(true);
            drop(w);
            *shared.message.lock().unwrap() = match result {
                Ok(m) => m,
                Err(e) => format!("error: {e}"),
            };
            shared.progress.store(1f32.to_bits(), Ordering::Relaxed);
            shared.busy.store(false, Ordering::SeqCst);
        });
    }

    fn world(&self) -> std::sync::RwLockReadGuard<'_, World> {
        self.shared.world.read().unwrap()
    }
}

/// Cells as a flat x, y, z, x, y, z... array (Godot has no packed Vector3i array).
fn flat_cells(cells: &[(i32, i32, i32)]) -> PackedInt32Array {
    let flat: Vec<i32> = cells.iter().flat_map(|&(x, y, z)| [x, y, z]).collect();
    PackedInt32Array::from(flat.as_slice())
}

#[godot_api]
impl VoxelWorld {
    /// Registers a block type. Keys: name, render (0 none, 1 cube, 2 cutout,
    /// 3 cross), solid, opaque, tex_top, tex_side, tex_bottom, variants, emit (Color 0..1),
    /// better_grass (grass sides turn to grass down a slope; BlockDef).
    #[func]
    fn define_block(&mut self, id: i32, def: VarDictionary) {
        let emit = val(&def, "emit").try_to::<Color>().unwrap_or(Color::BLACK);
        let to15 = |c: f32| (c * 15.0).round().clamp(0.0, 15.0) as u8;
        let d = BlockDef {
            name: val(&def, "name").try_to::<GString>().map(|s| s.to_string()).unwrap_or_default(),
            render: int_of(&val(&def, "render"), 1) as u8,
            solid: val(&def, "solid").try_to::<bool>().unwrap_or(true),
            opaque: val(&def, "opaque").try_to::<bool>().unwrap_or(true),
            sun_through: val(&def, "sun_through").try_to::<bool>().unwrap_or(false),
            tex: [
                int_of(&val(&def, "tex_top"), 0) as u16,
                int_of(&val(&def, "tex_side"), 0) as u16,
                int_of(&val(&def, "tex_bottom"), 0) as u16,
            ],
            variants: int_of(&val(&def, "variants"), 1).max(1) as u8,
            emit: [to15(emit.r), to15(emit.g), to15(emit.b)],
            color_top: color8(val(&def, "color_top")),
            color_side: color8(val(&def, "color_side")),
            platform: val(&def, "platform").try_to::<bool>().unwrap_or(false),
            better_grass: val(&def, "better_grass").try_to::<bool>().unwrap_or(false),
            variant_of: int_of(&val(&def, "variant_of"), 0).max(0) as u16,
        };
        self.shared.world.write().unwrap().set_def(id as u16, d);
    }

    /// Changes the light a block kind gives off (a pulsing torch) and relights
    /// the cells holding it (`cells`: flat x, y, z), like placing it again.
    /// Nothing happens unless its light level (0-15 per channel) changes.
    /// Returns true if it relit.
    #[func]
    fn set_block_emit(&mut self, id: i32, emit: Color, cells: PackedInt32Array) -> bool {
        let to15 = |c: f32| (c * 15.0).round().clamp(0.0, 15.0) as u8;
        let e = [to15(emit.r), to15(emit.g), to15(emit.b)];
        let mut w = self.shared.world.write().unwrap();
        match w.defs.get_mut(id as usize) {
            Some(d) if d.emit != e => d.emit = e,
            _ => return false,
        }
        for c in cells.as_slice().chunks_exact(3) {
            let (x, y, z) = (c[0], c[1], c[2]);
            if w.in_bounds(x, y, z) && w.get(x, y, z) == id as u16 {
                w.relight_cell(x, y, z);
            }
        }
        true
    }

    #[func]
    fn start_generate(&mut self, seed: i32, size: Vector3i) {
        self.applied.clear();
        self.run_background(move |w, progress| {
            w.resize(size.x, size.y, size.z);
            worldgen::generate(w, seed, progress);
            progress.store(0.8f32.to_bits(), Ordering::Relaxed);
            w.compute_all_light();
            Ok(String::new())
        });
    }

    /// Whether any block of the ids lies in the box `extent` blocks each way
    /// from `center` (Terraria's nearby-tile buffs: the Bast Statue's).
    #[func]
    fn any_block_near(&self, center: Vector3i, extent: Vector3i, ids: PackedInt32Array) -> bool {
        let w = self.world();
        let ids: Vec<u16> = ids.as_slice().iter().map(|&v| v as u16).collect();
        let (y0, y1) = ((center.y - extent.y).max(0), (center.y + extent.y).min(w.sy - 1));
        for z in (center.z - extent.z).max(0)..=(center.z + extent.z).min(w.sz - 1) {
            for x in (center.x - extent.x).max(0)..=(center.x + extent.x).min(w.sx - 1) {
                for y in y0..=y1 {
                    if ids.contains(&w.get(x, y, z)) {
                        return true;
                    }
                }
            }
        }
        false
    }

    /// How many of each block id lie in the cube of `radius` around `center`
    /// (index = block id), for biome detection.
    #[func]
    fn count_blocks(&self, center: Vector3i, radius: i32) -> PackedInt32Array {
        let w = self.world();
        let mut counts = vec![0i32; w.defs.len().max(1)];
        for z in center.z - radius..=center.z + radius {
            for x in center.x - radius..=center.x + radius {
                for y in center.y - radius..=center.y + radius {
                    if w.in_bounds(x, y, z) {
                        let b = w.get(x, y, z) as usize;
                        if b < counts.len() {
                            counts[b] += 1;
                        }
                    }
                }
            }
        }
        PackedInt32Array::from(counts.as_slice())
    }

    /// Terraria's housing check in 3D (World::flood_room): the room around
    /// `start` bounded by solid blocks and `walls` (doors, platforms), up to
    /// `max_cells`. {cells, overflow, ids (blocks in and around it), floor
    /// (cells to stand in)}; cells and floor are flat x, y, z triples.
    #[func]
    fn flood_room(&self, start: Vector3i, max_cells: i32, walls: PackedInt32Array) -> VarDictionary {
        let w = self.world();
        let walls: Vec<u16> = walls.as_slice().iter().map(|&v| v as u16).collect();
        let room = w.flood_room((start.x, start.y, start.z), max_cells.max(0) as usize, &walls);
        let ids: Vec<i32> = room.ids.iter().map(|&v| v as i32).collect();
        let (cells, ids, floor) = (flat_cells(&room.cells), PackedInt32Array::from(ids.as_slice()), flat_cells(&room.floor));
        vdict! {
            "cells" => &cells,
            "overflow" => room.overflow,
            "ids" => &ids,
            "floor" => &floor,
        }
    }

    /// Cells within `extent` of `center` holding one of `ids` (at most `max`),
    /// as flat x, y, z triples.
    #[func]
    fn find_blocks(&self, center: Vector3i, extent: Vector3i, ids: PackedInt32Array, max: i32) -> PackedInt32Array {
        let w = self.world();
        let ids: Vec<u16> = ids.as_slice().iter().map(|&v| v as u16).collect();
        flat_cells(&w.find_blocks((center.x, center.y, center.z), (extent.x, extent.y, extent.z), &ids, max.max(0) as usize))
    }

    /// The world evil for the next `start_generate`: 0 random (by seed),
    /// 1 Corruption, 2 Crimson.
    #[func]
    fn set_world_evil(&mut self, evil: i32) {
        self.shared.world.write().unwrap().gen_evil = evil;
    }

    /// Builds a Corruption (1) or Crimson (2) patch (worldgen's) around column
    /// (x, z) without light updates, like set_blocks_raw. Call `relight_all` after.
    #[func]
    fn generate_evil_patch(&mut self, center: Vector2i, radius: i32, evil: i32, seed: i32) {
        let mut w = self.shared.world.write().unwrap();
        let mut rng = worldgen::Rng::new(seed as u64);
        worldgen::evil_patch(&mut w, &mut rng, (center.x, center.y), radius, evil, seed);
    }

    /// A Snow (1), Desert (2) or Jungle (3) region around (x, z) (test world;
    /// see worldgen::biome_patch). Call `relight_all` after.
    #[func]
    fn generate_biome_patch(&mut self, center: Vector2i, radius: i32, biome: i32, seed: i32) -> i32 {
        let mut w = self.shared.world.write().unwrap();
        let mut rng = worldgen::Rng::new(seed as u64);
        worldgen::biome_patch(&mut w, &mut rng, (center.x, center.y), radius, biome, seed, None) as i32
    }

    /// Terraria's Dungeon entrance with its hall floor at `ground`, its door
    /// facing `door` (0 +z, 1 +x, 2 -z, 3 -x), built of `brick` (test world;
    /// see worldgen::dungeon_entrance). Call `relight_all` after.
    #[func]
    fn generate_dungeon_entrance(&mut self, ground: Vector3i, door: i32, brick: GString) {
        let mut w = self.shared.world.write().unwrap();
        worldgen::dungeon_entrance(&mut w, (ground.x, ground.y, ground.z), door.rem_euclid(4), &brick.to_string());
    }

    /// The Dungeon under an entrance made with generate_dungeon_entrance (test
    /// world; see dungeon::dungeon): `steps` x Terraria's layout steps. Call
    /// `relight_all` after.
    #[func]
    fn generate_dungeon(&mut self, ground: Vector3i, door: i32, brick: GString, steps: f32, seed: i32) -> bool {
        let mut w = self.shared.world.write().unwrap();
        let l = worldgen::layers(w.sy);
        dungeon::dungeon(&mut w, seed as u64, &l, (ground.x, ground.y, ground.z), door.rem_euclid(4), &brick.to_string(), steps as f64)
    }

    /// A bee hive centred on `at`, its balls `scale` x Terraria's, wherever
    /// it is (test world; see hives::hive_at). Returns the larva's cell. Call
    /// `relight_all` after.
    #[func]
    fn generate_hive(&mut self, at: Vector3i, seed: i32, scale: f32) -> Vector3i {
        let mut w = self.shared.world.write().unwrap();
        let l = worldgen::layers(w.sy);
        let ids = hives::Ids::new(&w);
        let p = hives::hive_at(&mut w, &mut worldgen::Rng::new(seed as u64), &ids, &l, (at.x, at.y, at.z), true, scale as f64).unwrap_or((0, 0, 0));
        Vector3i::new(p.0, p.1, p.2)
    }

    /// How much liquid a bobber at `p` sits in (Terraria's fishing pond
    /// measure, fishing::pond) through the vertical slices along x and z:
    /// {x, z: liquid cells, lava, honey}. Counting stops at `cap` cells.
    #[func]
    fn fishing_pond(&self, p: Vector3i, cap: i32) -> VarDictionary {
        let w = self.world();
        let a = fishing::pond(&w, p.x, p.y, p.z, true, cap);
        let b = fishing::pond(&w, p.x, p.y, p.z, false, cap);
        let mut d = VarDictionary::new();
        d.set("x", a.cells);
        d.set("z", b.cells);
        d.set("lava", a.lava || b.lava);
        d.set("honey", a.honey || b.honey);
        d
    }

    /// A Glowing Mushroom biome at `at`, its grass and mushrooms within
    /// `radius`; without `patches`, only the grass and mushrooms on the mud
    /// there (test world; see mushroom::biome_at). Call `relight_all` after.
    #[func]
    fn generate_mushroom_biome(&mut self, at: Vector3i, radius: i32, seed: i32, patches: bool) {
        let mut w = self.shared.world.write().unwrap();
        let l = worldgen::layers(w.sy);
        mushroom::biome_at(&mut w, seed, &l, (at.x, at.y, at.z), radius, patches);
    }

    /// Every block with styles turned to a random one of them (a world saved
    /// before plants had styles; see World::scatter_styles).
    #[func]
    fn scatter_styles(&mut self, seed: i32) {
        self.shared.world.write().unwrap().scatter_styles(seed);
    }

    /// Where worldgen put the big biomes: [{biome, x, z, radius}].
    #[func]
    fn get_biome_regions(&self) -> VarArray {
        let w = self.world();
        let mut out = VarArray::new();
        for (b, x, z, r) in worldgen::biome_regions(w.sx, w.sz, w.seed) {
            out.push(&vdict! { "biome" => b, "x" => x, "z" => z, "radius" => r }.to_variant());
        }
        out
    }

    /// Flat test world (see worldgen::generate_flat), generated in the background.
    #[func]
    fn start_generate_flat(&mut self, seed: i32, size: Vector3i, ground: i32) {
        self.applied.clear();
        self.run_background(move |w, progress| {
            w.resize(size.x, size.y, size.z);
            worldgen::generate_flat(w, seed, ground);
            progress.store(0.8f32.to_bits(), Ordering::Relaxed);
            w.compute_all_light();
            Ok(String::new())
        });
    }

    /// Bulk edit without per-block light updates (building structures before
    /// play): quadruples of x, y, z, block id. Call `relight_all` afterwards.
    #[func]
    fn set_blocks_raw(&mut self, data: PackedInt32Array) {
        let mut w = self.shared.world.write().unwrap();
        for q in data.as_slice().chunks_exact(4) {
            if w.in_bounds(q[0], q[1], q[2]) {
                let i = w.idx(q[0], q[1], q[2]);
                w.blocks[i] = q[3] as u16;
                if w.is_solid(q[0], q[1], q[2]) {
                    w.liquid[i] = 0;
                }
            }
        }
    }

    /// Builds a floating island (worldgen's) centred on (x, top, z) without
    /// light updates, like set_blocks_raw: kind 0 plain, 1 house with a Skyware
    /// chest, 2 lake. Call `relight_all` afterwards.
    #[func]
    fn generate_island(&mut self, center: Vector3i, radius: i32, kind: i32, seed: i32) {
        let mut w = self.shared.world.write().unwrap();
        let mut rng = worldgen::Rng::new(seed as u64);
        worldgen::floating_island(&mut w, &mut rng, (center.x, center.y, center.z), radius, kind, seed);
    }

    /// Bulk liquid fill without light updates: x, y, z, type, amount per entry.
    #[func]
    fn set_liquids_raw(&mut self, data: PackedInt32Array) {
        let mut w = self.shared.world.write().unwrap();
        for q in data.as_slice().chunks_exact(5) {
            if w.in_bounds(q[0], q[1], q[2]) && !w.is_solid(q[0], q[1], q[2]) {
                let i = w.idx(q[0], q[1], q[2]);
                w.liquid[i] = world::liq_pack(q[3] as u8, q[4].clamp(0, 63) as u8);
            }
        }
    }

    /// Recomputes all light (after raw edits) and wakes any unsettled liquid.
    /// The world as it now stands counts as made: its ground sets the sky
    /// floor (see World::sky_floor), so call this only while building a world.
    #[func]
    fn relight_all(&mut self) {
        let mut w = self.shared.world.write().unwrap();
        w.snapshot_sky_floor();
        w.compute_all_light();
        w.activate_unsettled_liquid();
    }

    /// Loads a world in the background; afterwards `get_message` returns the metadata string.
    #[func]
    fn start_load(&mut self, path: GString) {
        self.applied.clear();
        let path = path.to_string();
        self.run_background(move |w, _| {
            let file = std::fs::File::open(&path).map_err(|e| e.to_string())?;
            save::load(w, &mut std::io::BufReader::new(file)).map_err(|e| e.to_string())
        });
    }

    #[func]
    fn save(&self, path: GString, meta: GString) -> bool {
        let path = path.to_string();
        let tmp = format!("{path}.tmp");
        let result = std::fs::File::create(&tmp).and_then(|f| {
            let mut out = std::io::BufWriter::new(f);
            save::save(&self.world(), &meta.to_string(), &mut out)?;
            std::io::Write::flush(&mut out)?;
            drop(out);
            std::fs::rename(&tmp, &path)
        });
        if let Err(e) = &result {
            godot_error!("saving world failed: {e}");
        }
        result.is_ok()
    }

    #[func]
    fn is_busy(&self) -> bool {
        self.shared.busy.load(Ordering::SeqCst)
    }

    #[func]
    fn get_progress(&self) -> f32 {
        f32::from_bits(self.shared.progress.load(Ordering::Relaxed))
    }

    /// Result of the last background task: load metadata, or "error: ...".
    #[func]
    fn get_message(&self) -> GString {
        GString::from(self.shared.message.lock().unwrap().as_str())
    }

    #[func]
    fn get_size(&self) -> Vector3i {
        let w = self.world();
        Vector3i::new(w.sx, w.sy, w.sz)
    }

    #[func]
    fn get_chunk_count(&self) -> Vector3i {
        let (x, y, z) = self.world().chunk_count();
        Vector3i::new(x, y, z)
    }

    #[func]
    fn get_spawn(&self) -> Vector3i {
        let s = self.world().spawn;
        Vector3i::new(s.0, s.1, s.2)
    }

    #[func]
    fn set_spawn(&mut self, p: Vector3i) {
        self.shared.world.write().unwrap().spawn = (p.x, p.y, p.z);
    }

    #[func]
    fn get_seed(&self) -> i32 {
        self.world().seed
    }

    #[func]
    fn get_layers(&self) -> VarDictionary {
        let w = self.world();
        let l = worldgen::layers(w.sy);
        let o = worldgen::ocean(w.sx, w.sy, w.sz);
        vdict! {
            "underworld_top" => l.underworld_top,
            "cavern_top" => l.cavern_top,
            "surface" => l.surface_base,
            "space" => l.space_top,
            "sea_level" => o.sea_level,
            "ocean_width" => o.width,
            "beach_width" => o.beach,
            "ocean_depth" => o.depth,
        }
    }

    /// For `count` directions round (x, z) (angle i / count of a turn from +x
    /// toward +z), how far you look before the open sea (coast_inland below
    /// `sea_inland`, or off the world), up to `max_dist`: the sky hides its
    /// backdrop where the sea reaches the horizon.
    #[func]
    fn sea_distances(&self, origin: Vector2, count: i32, max_dist: f32, sea_inland: f32) -> PackedFloat32Array {
        let w = self.world();
        let coast = worldgen::Coast::new(w.seed, w.sx, w.sy, w.sz);
        let step = 4.0f32;
        let mut out = Vec::with_capacity(count.max(0) as usize);
        for i in 0..count.max(0) {
            let a = i as f32 / count as f32 * std::f32::consts::TAU;
            let (dx, dz) = (a.cos(), a.sin());
            let mut d = 0.0f32;
            let mut found = max_dist;
            while d <= max_dist {
                let (x, z) = ((origin.x + dx * d).floor() as i32, (origin.y + dz * d).floor() as i32);
                if x < 0 || z < 0 || x >= w.sx || z >= w.sz || coast.inland(x, z) < sea_inland {
                    found = d;
                    break;
                }
                d += step;
            }
            out.push(found);
        }
        PackedFloat32Array::from(out.as_slice())
    }

    /// How far (x, z) is inland from the world's edge, coastline included:
    /// below `ocean_width` (get_layers) is sea, then the beach.
    #[func]
    fn coast_inland(&self, x: i32, z: i32) -> f32 {
        let w = self.world();
        worldgen::Coast::new(w.seed, w.sx, w.sy, w.sz).inland(x, z)
    }

    #[func]
    fn get_block(&self, p: Vector3i) -> i32 {
        self.world().get(p.x, p.y, p.z) as i32
    }

    #[func]
    fn set_block(&mut self, p: Vector3i, id: i32) -> bool {
        self.shared.world.write().unwrap().set(p.x, p.y, p.z, id as u16)
    }

    /// A block's hammered shape: 0 full, 1 half, 2-5 ramp rising toward
    /// direction 0-3 (+z, +x, -z, -x), 6-9 the same upside down.
    #[func]
    fn get_shape(&self, p: Vector3i) -> i32 {
        self.world().shape_at(p.x, p.y, p.z) as i32
    }

    /// Reshapes a solid cube block; false if it can't take a shape.
    #[func]
    fn set_shape(&mut self, p: Vector3i, shape: i32) -> bool {
        if shape < 0 {
            return false;
        }
        self.shared.world.write().unwrap().set_shape(p.x, p.y, p.z, shape as u8)
    }

    /// Every shaped block as quadruples x, y, z, shape (for saving).
    #[func]
    fn get_shapes(&self) -> PackedInt32Array {
        let w = self.world();
        let mut out = Vec::with_capacity(w.shapes.len() * 4);
        for (&i, &shape) in w.shapes.iter() {
            let (x, z, y) = ((i / w.sy as usize) as i32 % w.sx, (i / w.sy as usize) as i32 / w.sx, (i % w.sy as usize) as i32);
            out.extend_from_slice(&[x, y, z, shape as i32]);
        }
        PackedInt32Array::from(out)
    }

    #[func]
    fn is_solid(&self, p: Vector3i) -> bool {
        self.world().is_solid(p.x, p.y, p.z)
    }

    #[func]
    fn surface_y(&self, x: i32, z: i32) -> i32 {
        self.world().surface_y(x, z)
    }

    /// Light at a world position as Color(r, g, b, sun), each 0..1.
    #[func]
    fn get_light(&self, pos: Vector3) -> Color {
        let p = pos.floor();
        let l = world::unpack_light(self.world().light_at(p.x as i32, p.y as i32, p.z as i32));
        Color::from_rgba(l[1] as f32 / 15.0, l[2] as f32 / 15.0, l[3] as f32 / 15.0, l[0] as f32 / 15.0)
    }

    /// Returns {} or {block: Vector3i, normal: Vector3i, id: int, distance: float}.
    #[func]
    fn raycast(&self, origin: Vector3, dir: Vector3, max_dist: f32) -> VarDictionary {
        Self::hit_dict(physics::raycast(&self.world(), v3(origin), v3(dir), max_dist, false))
    }

    /// Like `raycast`, but cells holding liquid also count as hits ("liquid" = type).
    #[func]
    fn raycast_liquid(&self, origin: Vector3, dir: Vector3, max_dist: f32) -> VarDictionary {
        Self::hit_dict(physics::raycast(&self.world(), v3(origin), v3(dir), max_dist, true))
    }

    /// Liquid in a cell as Vector2i(type, amount): type 0 none, 1 water, 2 lava, 3 honey;
    /// amount 0..63 (63 = full).
    #[func]
    fn get_liquid(&self, p: Vector3i) -> Vector2i {
        let (t, a) = self.world().liquid_at(p.x, p.y, p.z);
        Vector2i::new(t as i32, a as i32)
    }

    #[func]
    fn set_liquid(&mut self, p: Vector3i, liquid_type: i32, amount: i32) -> bool {
        self.shared.world.write().unwrap().set_liquid(p.x, p.y, p.z, liquid_type as u8, amount.clamp(0, 63) as u8)
    }

    /// Runs one liquid simulation tick over at most `max_cells` active cells;
    /// returns how many cells are still active.
    #[func]
    fn step_liquids(&mut self, max_cells: i32) -> i32 {
        if self.is_busy() {
            return 0;
        }
        // Only lock the world for writing when there's liquid on the move (a
        // write lock waits for every mesh job reading it).
        if self.world().liquid_active.is_empty() {
            return 0;
        }
        self.shared.world.write().unwrap().step_liquids(max_cells.max(1) as usize) as i32
    }

    /// Moves a box (bottom-centre `pos`, `half` = half width, height, half depth).
    /// Returns {position: Vector3, blocked: Vector3i (1 = axis hit), on_floor: bool}.
    /// With `drop`, the box falls through platforms (and doesn't step up onto them).
    #[func]
    fn move_aabb(&self, pos: Vector3, half: Vector3, motion: Vector3, step_height: f32, drop: bool) -> VarDictionary {
        let r = physics::move_aabb(&self.world(), v3(pos), v3(half), v3(motion), step_height, drop);
        vdict! {
            "position" => Vector3::new(r.pos[0], r.pos[1], r.pos[2]),
            "blocked" => Vector3i::new(r.blocked[0] as i32, r.blocked[1] as i32, r.blocked[2] as i32),
            "on_floor" => r.on_floor,
        }
    }

    /// True if the box overlaps any solid block (used to validate block placement).
    #[func]
    fn box_hits_solid(&self, pos: Vector3, half: Vector3) -> bool {
        let w = self.world();
        let min = (pos - Vector3::new(half.x, 0.0, half.z)).floor();
        let max = (pos + Vector3::new(half.x, half.y, half.z) - Vector3::splat(0.001)).floor();
        for x in min.x as i32..=max.x as i32 {
            for y in min.y as i32..=max.y as i32 {
                for z in min.z as i32..=max.z as i32 {
                    if w.is_solid(x, y, z) {
                        return true;
                    }
                }
            }
        }
        false
    }

    /// Blocks in a chunk whose definition uses the "model" render kind (5), as
    /// quadruples x, y, z, id. The game draws these itself.
    #[func]
    fn get_model_blocks(&self, chunk: Vector3i) -> PackedInt32Array {
        let w = self.world();
        let mut out = Vec::new();
        let cs = world::CS;
        for z in chunk.z * cs..(chunk.z + 1) * cs {
            for x in chunk.x * cs..(chunk.x + 1) * cs {
                for y in chunk.y * cs..(chunk.y + 1) * cs {
                    if !w.in_bounds(x, y, z) {
                        continue;
                    }
                    let id = w.blocks[w.idx(x, y, z)];
                    if id != 0 && w.def(id).render == world::RENDER_MODEL {
                        out.extend_from_slice(&[x, y, z, id as i32]);
                    }
                }
            }
        }
        PackedInt32Array::from(out)
    }

    #[func]
    fn request_mesh(&self, chunk: Vector3i) {
        if let Some(tx) = &self.job_tx {
            let _ = tx.send(Job::Chunk((chunk.x, chunk.y, chunk.z)));
        }
    }

    /// Returns up to `max` finished meshes as
    /// [chunk: Vector3i, opaque, cutout, water, lava, honey] (surface arrays or null).
    /// Stale results (superseded by a newer edit) are dropped.
    #[func]
    fn poll_meshes(&mut self, max: i32) -> VarArray {
        let mut out = VarArray::new();
        while out.len() < max as usize {
            let Ok(r) = self.result_rx.try_recv() else { break };
            let applied = self.applied.entry(r.chunk).or_insert(0);
            if r.version < *applied {
                continue;
            }
            *applied = r.version;
            let mut item = VarArray::new();
            item.push(&Vector3i::new(r.chunk.0, r.chunk.1, r.chunk.2).to_variant());
            item.push(&surface_arrays(&r.mesh.opaque));
            item.push(&surface_arrays(&r.mesh.cutout));
            item.push(&surface_arrays(&r.mesh.water));
            item.push(&surface_arrays(&r.mesh.lava));
            item.push(&surface_arrays(&r.mesh.honey));
            out.push(&item.to_variant());
        }
        out
    }

    /// Asks for a far-terrain tile (lod.rs): `tile` = (x, level, z), its
    /// cells 2^level blocks, CS of them across, the world's full height.
    #[func]
    fn request_lod_mesh(&self, tile: Vector3i) {
        if let Some(tx) = &self.job_tx {
            let _ = tx.send(Job::Lod(tile.y, tile.x, tile.z));
        }
    }

    /// Up to `max` finished far-terrain tiles as [tile: Vector3i (x, level, z),
    /// terrain surface arrays or null, water surface arrays or null].
    #[func]
    fn poll_lod_meshes(&mut self, max: i32) -> VarArray {
        let mut out = VarArray::new();
        while out.len() < max as usize {
            let Ok(r) = self.lod_rx.try_recv() else { break };
            let mut item = VarArray::new();
            item.push(&Vector3i::new(r.tile.1, r.tile.0, r.tile.2).to_variant());
            item.push(&surface_arrays(&r.mesh.terrain));
            item.push(&surface_arrays(&r.mesh.water));
            out.push(&item.to_variant());
        }
        out
    }

    /// Shrinks an RGBA8 render (`w` x `h`) by `factor` without blur: each
    /// pixel the colour covering most of its block, opaque only if half of it
    /// is (shrink.rs; the NPC picker's rendered sprites).
    #[func]
    fn shrink_majority(data: PackedByteArray, w: i32, h: i32, factor: i32) -> PackedByteArray {
        PackedByteArray::from(shrink::shrink_majority(data.as_slice(), w as usize, h as usize, factor as usize))
    }

    /// A one-pixel outline round an RGBA8 image's opaque parts, `shade` times
    /// their colour (shrink.rs; rendered sprites' "outline").
    #[func]
    fn outline_rgba(data: PackedByteArray, w: i32, h: i32, shade: f32) -> PackedByteArray {
        PackedByteArray::from(shrink::outline(data.as_slice(), w as usize, h as usize, shade))
    }

    /// Far terrain leaves out dark faces only below this height (caves).
    #[func]
    fn set_lod_cave_level(&mut self, y: i32) {
        self.shared.world.write().unwrap().lod_cave_level = y;
    }

    #[func]
    fn take_dirty_chunks(&mut self) -> Array<Vector3i> {
        if self.world().dirty.is_empty() {
            return Array::new();  // no write lock (it would wait for the mesh jobs)
        }
        let dirty = self.shared.world.write().unwrap().take_dirty();
        dirty.into_iter().map(|c| Vector3i::new(c.0, c.1, c.2)).collect()
    }

    #[func]
    fn get_decorations(&self) -> VarArray {
        self.world()
            .decorations
            .iter()
            .map(|d| {
                vdict! {
                    "kind" => d.kind.as_str(),
                    "pos" => Vector3i::new(d.pos.0, d.pos.1, d.pos.2),
                    "style" => d.style,
                }
                .to_variant()
            })
            .collect()
    }

    #[func]
    fn add_decoration(&mut self, kind: GString, pos: Vector3i, style: i32) {
        self.shared.world.write().unwrap().decorations.push(world::Decoration {
            kind: kind.to_string(),
            pos: (pos.x, pos.y, pos.z),
            style,
        });
    }

    #[func]
    fn remove_decorations_at(&mut self, pos: Vector3i) -> i32 {
        let mut w = self.shared.world.write().unwrap();
        let before = w.decorations.len();
        w.decorations.retain(|d| d.pos != (pos.x, pos.y, pos.z));
        (before - w.decorations.len()) as i32
    }
}

impl Drop for VoxelWorld {
    fn drop(&mut self) {
        // Closing the job channel stops the mesh workers.
        self.job_tx.take();
    }
}
