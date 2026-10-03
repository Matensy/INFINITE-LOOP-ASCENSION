shader_type canvas_item;
// Animated themed backdrop. Deliberately cheap: a gradient plus one detail
// layer chosen by `style`; `detail` = 0 disables the layer (low effects).

uniform vec4 top_color : source_color = vec4(0.04, 0.06, 0.19, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.01, 0.02, 0.05, 1.0);
uniform vec4 accent_color : source_color = vec4(0.1, 0.16, 0.48, 1.0);
uniform int style = 0;
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 2.0) = 0.0;
uniform float aspect = 0.5625;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	vec2 p = vec2(uv.x, uv.y / aspect);
	float t = TIME;
	float layer = 0.0;
	if (detail > 0.0) {
		if (style == 0) {
			float n = vnoise(p * 3.0 + vec2(t * 0.03, t * 0.02)) * 0.6
					+ vnoise(p * 7.0 - vec2(t * 0.05, 0.0)) * 0.4;
			layer = smoothstep(0.45, 0.95, n) * 0.55;
		} else if (style == 1) {
			vec2 g = abs(fract(p * 9.0 + vec2(0.0, t * 0.05)) - 0.5);
			float line = 1.0 - smoothstep(0.0, 0.035, min(g.x, g.y));
			layer = line * 0.22 * (1.0 - uv.y * 0.6);
		} else if (style == 2) {
			float w = sin(p.y * 14.0 + sin(p.x * 3.0 + t * 0.4) * 2.0 - t * 0.6);
			layer = smoothstep(0.85, 1.0, w) * 0.3;
		} else if (style == 3) {
			vec2 cell = floor(p * 38.0);
			float h = hash(cell);
			float twinkle = 0.5 + 0.5 * sin(t * (1.0 + h * 3.0) + h * 40.0);
			vec2 f = fract(p * 38.0) - 0.5;
			float star = step(0.965, h) * (1.0 - smoothstep(0.0, 0.18, length(f))) * twinkle;
			layer = star * 1.4 + vnoise(p * 2.5 + t * 0.01) * 0.12;
		} else {
			vec2 d = uv - vec2(0.5, -0.15);
			float a = atan(d.y, d.x);
			float rays = 0.5 + 0.5 * sin(a * 18.0 + t * 0.25);
			layer = pow(rays, 6.0) * 0.3 * (1.0 - smoothstep(0.0, 1.2, length(d)));
		}
	}
	col += accent_color.rgb * layer * detail;
	col += accent_color.rgb * energy * 0.25 * (1.0 - uv.y);
	float vignette = smoothstep(1.15, 0.35, length(uv - vec2(0.5, 0.45)));
	col *= mix(0.55, 1.0, vignette);
	COLOR = vec4(col, 1.0);
}
