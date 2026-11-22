shader_type canvas_item;
render_mode unshaded;

uniform vec3 ray_origin;
uniform vec3 ray_tl;
uniform vec3 ray_dx;
uniform vec3 ray_dy;
uniform vec2 player_xz;
uniform vec2 forward_xz = vec2(0.0, 1.0);

void fragment() {
	// 地面投影视野提示，不是墙体遮挡或 AI 的真实视线。
	vec3 ray = ray_tl + UV.x * ray_dx + UV.y * ray_dy;
	float t = -ray_origin.y / min(ray.y, -0.0001);
	vec2 offset = (ray_origin + ray * t).xz - player_xz;
	float radius = length(offset);
	float facing = dot(offset / max(radius, 0.001), forward_xz);
	float rear = 1.0 - smoothstep(-0.55, 0.35, facing);
	float buffer = smoothstep(1.25, 3.0, radius);
	COLOR = vec4(0.015, 0.02, 0.03, 0.55 * rear * buffer);
}
