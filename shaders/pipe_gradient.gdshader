shader_type canvas_item;
render_mode blend_mix;
// Board pipe layers. Vertices flagged with UV.y >= 2 carry the theme
// gradient value of their tile centre in UV.y - 2; the colour is shifted by
// the gradient difference at the vertex itself, so the energy gradient runs
// smoothly through pipes instead of stepping from tile to tile.

uniform vec4 lit : source_color = vec4(0.37, 0.97, 1.0, 1.0);
uniform vec4 lit2 : source_color = vec4(0.65, 0.55, 0.98, 1.0);
uniform vec2 board_size = vec2(1.0, 1.0);

void vertex() {
	if (UV.y > 1.5) {
		float tc = UV.y - 2.0;
		vec2 b = max(board_size, vec2(0.001));
		float tp = clamp(VERTEX.x / b.x * 0.55 + VERTEX.y / b.y * 0.45, 0.0, 1.0);
		COLOR.rgb = max(COLOR.rgb + (lit2.rgb - lit.rgb) * (tp - tc), vec3(0.0));
		UV.y = 0.5;
	}
}
