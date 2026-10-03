shader_type canvas_item;
// Horizontal colour gradient for titles (applied to a Label).

uniform vec4 color_a : source_color = vec4(0.37, 0.97, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.65, 0.55, 0.98, 1.0);
uniform float width = 600.0;
uniform float shimmer = 1.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp(local_pos.x / max(width, 1.0), 0.0, 1.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, t);
	// A slow light sweep across the letters.
	float sweep = smoothstep(0.12, 0.0, abs(fract(TIME * 0.12) * 1.6 - 0.3 - t));
	col = mix(col, vec3(1.0), sweep * 0.45 * shimmer);
	COLOR = vec4(col, texture(TEXTURE, UV).a * COLOR.a);
}
