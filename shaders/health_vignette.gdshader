shader_type canvas_item;
// 低血量视觉反馈：边缘泛红 + 轻微去饱和，随生命比例增强。

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.72, 0.06, 0.06, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = texture(screen_texture, uv).rgb;
	float gray = dot(src, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(src, vec3(gray), clamp(intensity * 0.5, 0.0, 1.0));
	float edge = smoothstep(0.40, 1.00, distance(uv, vec2(0.5)) * 1.6);
	float pulse = 0.9 + 0.1 * sin(TIME * 4.5);
	vec3 col = mix(desat, tint.rgb, edge * intensity * 0.6 * pulse);
	COLOR = vec4(col, 1.0);
}
