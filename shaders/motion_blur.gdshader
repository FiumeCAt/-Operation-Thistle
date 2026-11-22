shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.08) = 0.0;
uniform vec2 center = vec2(0.5, 0.54);
uniform int samples : hint_range(1, 16) = 8;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= samples) {
			break;
		}
		float t = float(i) / float(max(samples - 1, 1));
		float w = 1.0 - t * 0.65;
		vec2 offset = (uv - center) * strength * t;
		acc += texture(screen_texture, uv - offset).rgb * w;
		wsum += w;
	}
	COLOR = vec4(acc / max(wsum, 0.0001), 1.0);
}
