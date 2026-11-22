shader_type canvas_item;
// 屏幕暗角：边缘压暗到约 86% 不透明度，带轻微雾噪，中心保持透明。

uniform float edge_alpha : hint_range(0.0, 1.0) = 0.86;
uniform float inner : hint_range(0.0, 1.5) = 0.42;
uniform float outer : hint_range(0.0, 1.5) = 1.05;
uniform vec4 tint : source_color = vec4(0.010, 0.014, 0.020, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5)) * 1.55;
	float v = smoothstep(inner, outer, d);
	float noise = hash(floor(uv * vec2(280.0, 160.0)) + floor(TIME * 2.0));
	float a = v * edge_alpha * (0.9 + 0.1 * noise);
	COLOR = vec4(tint.rgb, a);
}
