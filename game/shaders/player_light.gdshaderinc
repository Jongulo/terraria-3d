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

// The Underworld's glow (Terraria's ApplyHellLight): everything below its top
// is lit a pulsing orange, set every frame by the game (zero elsewhere).
global uniform float underworld_top;
global uniform vec3 hell_light;

// Light that isn't in the voxel light: the player's and the Underworld's.
vec3 extra_light(vec3 world_pos) {
	vec3 l = player_light(world_pos);
	return world_pos.y < underworld_top ? max(l, hell_light) : l;
}
