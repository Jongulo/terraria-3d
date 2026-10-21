// Block models (scripts/world/block_models.gd): placeable sprites turned into
// 3D. Included by block_model.gdshader (single nodes) and
// block_model_batched.gdshader (MultiMesh batches). Textured meshes (panels, cross, flat, extruded) sample the sprite; voxel
// meshes (hull, lathe) carry each voxel's colour in COLOR. Lit like blocks:
// per-instance voxel light at the block plus sunlight. With `billboard`, the
// mesh turns around its vertical axis to face the camera (tree canopies drawn
// as one MultiMesh, where every instance needs its own facing). They take the
// sun's optional shadows (sun_shadow.gdshaderinc), looked up per texel of the
// sprite (textured meshes) or per voxel face (voxel meshes, whose faces carry
// UVs 0-1 for it).

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform bool textured = false;
// The sprite's texture pixels per art pixel (Terraria's art is drawn at 2x):
// the sun's shadow is looked up once per art pixel.
uniform int art_scale = 1;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
#ifdef BATCHED
// Batched (a MultiMesh per chunk and mesh): each block's light comes in
// INSTANCE_CUSTOM. No instance uniform: Godot reserves a block of its
// instance uniform buffer for every node whose shader declares one, and a big
// world's batches would run it out.
#else
instance uniform vec4 entity_light = vec4(1.0);
#endif
#ifdef NPC_MODEL
// Enemies drawn as 3D models (npc_model.gdshader): Terraria's recolour (slimes)
// and the white flash of a hit, per enemy.
instance uniform vec4 tint = vec4(1.0);
instance uniform float flash = 0.0;
// Below 1 fades it out, dithered (as billboard.gdshaderinc's fade).
instance uniform float fade = 1.0;
#endif
#ifdef NPC_GLASS
// How opaque a see-through model is (npc_model_glass.gdshader).
uniform float glass = 1.0;
#endif
uniform bool billboard = false;
// Billboards: moves the quad this far toward the camera, so a billboard that
// overlaps another on the same axis (a canopy over its trunk) stays in front.
uniform float billboard_offset = 0.0;
// Fixed (not billboard) models: drawn this much nearer the camera (tree
// branches, so the stem that overlaps the trunk's edge stays in front).
uniform float toward_camera = 0.0;
// Spears: only the part in front of this plane (xyz normal, w offset) shows,
// the shaft past your hand being behind you. Off when the normal is zero.
uniform vec4 clip_plane = vec4(0.0);
// Level of detail (canopy sprites): an instance whose middle is less than
// lod_near or more than lod_far across from lod_center isn't drawn (the near
// ones are drawn in full detail by another batch). Off by default.
uniform vec2 lod_center = vec2(0.0);
uniform float lod_near = -1.0;
uniform float lod_far = 1.0e9;
varying vec4 v_light;
varying vec3 v_world;
// Billboards: where the instance stands and which way it faced.
varying vec3 v_origin;
varying vec3 v_right;
varying vec3 v_fwd;
#include "res://shaders/player_light.gdshaderinc"
#define SUN_FACES
#include "res://shaders/sun_shadow.gdshaderinc"

void vertex() {
	float lod_d = distance(MODEL_MATRIX[3].xz, lod_center);
	bool lod_hidden = lod_d < lod_near || lod_d > lod_far;
#ifdef BATCHED
	v_light = INSTANCE_CUSTOM;
#else
	v_light = entity_light;
#endif
	if (billboard) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 to_cam = CAMERA_POSITION_WORLD - origin;
		// The sun's shadow pass (orthographic): toward the sun, so its shadow
		// is its outline as the sun sees it.
		if (PROJECTION_MATRIX[3][3] > 0.5) {
			to_cam = sun_dir;
		}
		to_cam.y = 0.0;
		vec3 fwd = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
		// The instance's scale (a placeable's transform setting) still applies.
		float s = length(MODEL_MATRIX[1].xyz);
		// A z axis longer than the others moves this instance that much
		// further toward the camera (palm segments: each over the one above).
		float nudge = length(MODEL_MATRIX[2].xyz) - s;
		vec3 world = origin + (right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0) + fwd * VERTEX.z) * s + fwd * (billboard_offset + nudge);
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
		v_world = world;
		v_origin = origin;
		v_right = right;
		v_fwd = fwd;
	} else {
		v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		// Writing POSITION anywhere replaces Godot's default transform, so do it here too.
		if (toward_camera > 0.0) {
			vec3 w = v_world + normalize(CAMERA_POSITION_WORLD - v_world) * toward_camera;
			POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
		} else {
			POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		}
	}
	if (lod_hidden) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);  // off screen: not drawn
	}
}

void fragment() {
	vec4 c = textured ? texture(sprite, UV) : vec4(1.0);
	if (c.a < 0.5) {
		discard;
	}
	if (clip_plane.xyz != vec3(0.0) && dot(v_world, clip_plane.xyz) < clip_plane.w) {
		discard;
	}
	vec3 col = c.rgb * COLOR.rgb;
#ifdef NPC_MODEL
	col *= tint.rgb * (1.0 - flash);
#endif
	// As dark as the blocks around it in the dark (voxel_common's light, no floor).
	SUN_SHADOW_COLOUR(col, max(v_light.rgb, extra_light(v_world)), vec3(v_light.a * sky_light) * sky_color, 0.0);
	if (sun_shadows) {
		vec3 at = sun_snap_uv(VERTEX, UV, textured ? vec2(textureSize(sprite, 0)) / float(max(art_scale, 1)) : vec2(1.0));
		if (billboard) {
			// Looked up on the copy of it that faces the sun (the one in the
			// shadow map), a little toward the sun, so it doesn't shade itself.
			vec3 rel = (INV_VIEW_MATRIX * vec4(at, 1.0)).xyz - v_origin;
			vec3 fl = normalize(vec3(sun_dir.x, 0.0, sun_dir.z));
			vec3 rl = normalize(cross(vec3(0.0, 1.0, 0.0), fl));
			vec3 w = v_origin + rl * dot(rel, v_right) + vec3(0.0, rel.y, 0.0) + fl * dot(rel, v_fwd) + sun_dir * 0.1;
			at = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
		}
		LIGHT_VERTEX = at;
	}
#ifdef NPC_MODEL
	EMISSION += vec3(flash);
	if (fade < 1.0 && fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) > fade) {
		discard;
	}
#endif
#ifdef NPC_GLASS
	ALPHA = glass;
#endif
}
