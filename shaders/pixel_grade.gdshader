shader_type canvas_item;
// 2.5D 画面滤镜：像素块采样 + 邻域描边 + 色阶量化 + 冷暖分离 + 暗角。
// 目的是把写实光照的 3D 场景压成有限色阶、带硬边轮廓的“模型感”画面，
// 让 3D 墙体与 2D 立绘落在同一种画面语言里。

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 6.0) = 1.5;
uniform int levels : hint_range(8, 64) = 16;
uniform float dither : hint_range(0.0, 1.0) = 0.25;
uniform float saturation : hint_range(0.0, 1.5) = 0.95;
uniform float outline_strength : hint_range(0.0, 1.0) = 0.55;
uniform float outline_threshold : hint_range(0.0, 0.5) = 0.08;
uniform float vignette : hint_range(0.0, 1.0) = 0.26;
uniform vec3 shadow_tint = vec3(0.90, 0.96, 1.08);
uniform vec3 light_tint = vec3(1.06, 1.02, 0.94);

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 block = SCREEN_PIXEL_SIZE * pixel_size;
	vec2 uv = floor(SCREEN_UV / block) * block + block * 0.5;
	vec3 c = texture(screen_texture, uv).rgb;

	// 像素化邻域亮度差做描边，给墙体和角色统一硬轮廓。
	float l0 = luma(texture(screen_texture, uv + vec2(block.x, 0.0)).rgb);
	float l1 = luma(texture(screen_texture, uv - vec2(block.x, 0.0)).rgb);
	float l2 = luma(texture(screen_texture, uv + vec2(0.0, block.y)).rgb);
	float l3 = luma(texture(screen_texture, uv - vec2(0.0, block.y)).rgb);
	float edge = abs(l0 - l1) + abs(l2 - l3);
	edge = smoothstep(outline_threshold, outline_threshold * 3.0, edge);
	c = mix(c, c * 0.3, edge * outline_strength);

	float l = luma(c);
	c = mix(vec3(l), c, saturation);
	// 暗部偏冷、亮部偏暖，避免整屏同一种蓝灰。
	c *= mix(shadow_tint, light_tint, smoothstep(0.15, 0.75, l));

	float v = clamp(1.0 - pow(distance(SCREEN_UV, vec2(0.5)) * 1.35, 2.4), 0.0, 1.0);
	c *= mix(1.0, v, vignette);

	float b = bayer4(FRAGCOORD.xy);
	c += (b - 0.5) * dither / float(levels);
	c = floor(c * float(levels) + 0.5) / float(levels);
	COLOR = vec4(c, 1.0);
}
