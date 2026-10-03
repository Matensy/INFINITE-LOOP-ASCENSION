shader_type canvas_item;
// Soft "aurora" mesh gradient with drifting bokeh lights and film grain.
// Deliberately cheap: three gaussian colour blobs, one bokeh lookup and a
// hash per pixel. `detail` = 0 keeps only the gradient (low effects).

uniform vec4 top_color : source_color = vec4(0.07, 0.07, 0.22, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform vec4 accent_color : source_color = vec4(0.23, 0.16, 0.54, 1.0);
uniform vec4 glow_a : source_color = vec4(0.37, 0.97, 1.0, 1.0);
uniform vec4 glow_b : source_color = vec4(0.65, 0.55, 0.98, 1.0);
uniform int style = 0;
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 2.0) = 0.0;
uniform float aspect = 0.5625;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float blob(vec2 p, vec2 c, float r) {
	vec2 d = p - c;
	return exp(-dot(d, d) / (r * r));
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x, uv.y / aspect);
	float h = 1.0 / aspect;
	float t = TIME * 0.05;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));

	// Aurora blobs drifting on slow Lissajous paths.
	vec2 c1 = vec2(0.25 + 0.2 * sin(t * 1.3), h * (0.2 + 0.08 * cos(t * 1.7)));
	vec2 c2 = vec2(0.8 + 0.15 * cos(t * 1.1), h * (0.55 + 0.1 * sin(t * 0.9)));
	vec2 c3 = vec2(0.4 + 0.25 * sin(t * 0.7 + 2.0), h * (0.95 + 0.06 * sin(t * 1.3)));
	col += accent_color.rgb * blob(p, c1, 0.55) * 0.55;
	col += glow_a.rgb * blob(p, c2, 0.45) * 0.10 * (0.6 + detail * 0.4);
	col += glow_b.rgb * blob(p, c3, 0.5) * 0.12 * (0.6 + detail * 0.4);

	if (detail > 0.0) {
		// Bokeh: at most one soft disc per cell, rising slowly.
		vec2 q = p * 6.0 + vec2(0.0, TIME * 0.06);
		vec2 cell = floor(q);
		float r = hash(cell);
		vec2 centre = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.6 + 0.2;
		float size = 0.08 + 0.18 * hash(cell + 1.3);
		float twinkle = 0.55 + 0.45 * sin(TIME * (0.4 + r) + r * 30.0);
		float disc = 1.0 - smoothstep(size * 0.55, size, length(fract(q) - centre));
		vec3 tint = mix(glow_a.rgb, glow_b.rgb, hash(cell + 9.4));
		col += tint * disc * step(0.72, r) * 0.07 * twinkle * detail;
		if (style == 3) {
			// Soft round star dust (never hard-edged pixels).
			vec2 sq = p * 28.0;
			vec2 sc = floor(sq);
			float sr = hash(sc + 5.5);
			vec2 sp = vec2(hash(sc + 2.2), hash(sc + 8.8)) * 0.7 + 0.15;
			float sd = length(fract(sq) - sp);
			float star = (1.0 - smoothstep(0.0, 0.09, sd)) * step(0.9, sr);
			col += mix(vec3(1.0), glow_a.rgb, 0.3) * star * (0.5 + 0.5 * sin(TIME * 1.5 + sr * 60.0)) * 0.22 * detail;
		}
	}
	col += mix(glow_a.rgb, glow_b.rgb, uv.x) * energy * 0.22 * (1.0 - uv.y * 0.6);
	float vignette = smoothstep(1.2, 0.3, length((uv - vec2(0.5, 0.45)) * vec2(1.0, 0.85)));
	col *= mix(0.6, 1.0, vignette);
	col += (hash(uv * 977.0 + fract(TIME)) - 0.5) * 0.012;
	COLOR = vec4(col, 1.0);
}
