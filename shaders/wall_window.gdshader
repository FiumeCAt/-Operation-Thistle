shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform bool triplanar = false;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform bool window_enabled = false;
uniform vec2 window_center = vec2(0.0);
uniform vec2 logical_size = vec2(1920.0, 1080.0);
uniform float window_radius = 120.0;
uniform float window_feather = 40.0;
// 第二窗口：玩家被墙挡住时，在玩家屏幕位置开一个小洞，避免角色看起来浮在墙上。
uniform bool player_window_enabled = false;
uniform vec2 player_window_center = vec2(0.0);
uniform float player_window_radius = 90.0;
uniform float player_window_feather = 28.0;
varying vec3 local_position;
varying vec3 local_normal;

// 4x4 Bayer 抖动：在洞口边缘做羽化，避免硬边圆洞。
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

// 返回 1 表示该像素应被丢弃（窗口内），0 表示保留。screen_uv 由 fragment 传入。
float window_mask(vec2 screen_uv, vec2 center, float radius, float feather) {
	float d = length(screen_uv * logical_size - center);
	float f = max(feather, 1.0);
	if (d < radius - f) {
		return 1.0;
	}
	if (d < radius) {
		float t = (d - (radius - f)) / f;
		if (bayer4(screen_uv * logical_size) > t) {
			return 1.0;
		}
	}
	return 0.0;
}

void vertex() {
	local_position = VERTEX * uv_scale;
	local_normal = NORMAL;
}

void fragment() {
	if (window_enabled && window_mask(SCREEN_UV, window_center, window_radius, window_feather) > 0.5) {
		discard;
	}
	if (player_window_enabled && window_mask(SCREEN_UV, player_window_center, player_window_radius, player_window_feather) > 0.5) {
		discard;
	}
	vec3 color = albedo.rgb;
	if (triplanar) {
		vec3 weights = abs(local_normal);
		weights /= max(dot(weights, vec3(1.0)), 0.00001);
		vec3 p = local_position * vec3(1.0, -1.0, 1.0);
		color *= texture(albedo_texture, p.xy).rgb * weights.z
			+ texture(albedo_texture, p.xz).rgb * weights.y
			+ texture(albedo_texture, p.zy * vec2(-1.0, 1.0)).rgb * weights.x;
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission;
}
