// The light the player carries (a held torch, a Mining Helmet), set every
// frame by Player.update_carried_light. It sits at the camera, so whatever
// you can see is in its reach: no shadows to work out. Returns a light level
// (0..1 per channel) to max() with the voxel light before squaring it.
global uniform vec3 player_light_pos;
global uniform vec3 player_light_color;

// Blocks of reach, like a torch's 15 light levels falling one per block.
const float PLAYER_LIGHT_RANGE = 14.0;

vec3 player_light(vec3 world_pos) {
	float d = distance(world_pos, player_light_pos);
	return player_light_color * clamp(1.0 - d / PLAYER_LIGHT_RANGE, 0.0, 1.0);
}

// Lights lying about in the world (a thrown glowstick), set every frame by
// DynamicLights: row 0 of the texture is each one's position and reach, row
// 1 its colour. They shine through blocks, like the carried light.
global uniform sampler2D dynamic_lights;
global uniform int dynamic_light_count;

vec3 dynamic_light(vec3 world_pos) {
	vec3 l = vec3(0.0);
	for (int i = 0; i < dynamic_light_count; i++) {
		vec4 p = texelFetch(dynamic_lights, ivec2(i, 0), 0);
		vec3 c = texelFetch(dynamic_lights, ivec2(i, 1), 0).rgb;
		l = max(l, c * clamp(1.0 - distance(world_pos, p.xyz) / p.w, 0.0, 1.0));
	}
	return l;
}

// The Underworld's glow (Terraria's ApplyHellLight): everything below its top
// is lit a pulsing orange, set every frame by the game (zero elsewhere).
global uniform float underworld_top;
global uniform vec3 hell_light;

// Light that isn't in the voxel light: the player's, what lies about and the
// Underworld's. The top faces of the Underworld's highest blocks lie right on
// its top: a little give keeps them lit, instead of each pixel flipping with
// rounding.
vec3 extra_light(vec3 world_pos) {
	vec3 l = max(player_light(world_pos), dynamic_light(world_pos));
	return world_pos.y < underworld_top + 0.01 ? max(l, hell_light) : l;
}
