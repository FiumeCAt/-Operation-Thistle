shader_type canvas_item;
// 标题背景像素化：把高清预渲染图降到低分辨率网格并量化色阶，
// 与游戏内的像素风场景/立绘保持同一画面语言。

uniform vec2 grid = vec2(640.0, 360.0);
uniform int levels : hint_range(8, 64) = 32;

void fragment() {
	vec2 p = (floor(UV * grid) + 0.5) / grid;
	vec4 c = texture(TEXTURE, p);
	c.rgb = floor(c.rgb * float(levels) + 0.5) / float(levels);
	COLOR = c;
}
