shader_type canvas_item;
// Земля и дорога целиком на GPU. road_tex хранит расстояние до оси дороги (в клетках / 2).

uniform sampler2D road_tex : filter_linear, repeat_disable;
uniform vec2 cells = vec2(16.0, 10.0);
uniform vec3 grass_a : source_color = vec3(0.11, 0.22, 0.16);
uniform vec3 grass_b : source_color = vec3(0.15, 0.30, 0.21);
uniform vec3 grass_c : source_color = vec3(0.20, 0.38, 0.25);
uniform vec3 dirt_a : source_color = vec3(0.35, 0.29, 0.20);
uniform vec3 dirt_b : source_color = vec3(0.43, 0.36, 0.25);
uniform vec3 dirt_edge : source_color = vec3(0.14, 0.11, 0.08);
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float snow = 0.0;
// доля булыжной мостовой на дороге (по биому)
uniform float cobble = 0.8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return v;
}

// Вороной: x — расстояние до шва между камнями, y — номер камня (хеш), z — расстояние до центра камня.
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 o = vec2(hash21(n + g), hash21(n + g + 17.3)) * 0.8 + 0.1;
		vec2 r = g + o - f;
		float d = dot(r, r);
		if (d < md) { md = d; mr = r; mg = g; id = hash21(n + g + 3.1); }
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++)
	for (int i = -2; i <= 2; i++) {
		vec2 g = mg + vec2(float(i), float(j));
		vec2 o = vec2(hash21(n + g), hash21(n + g + 17.3)) * 0.8 + 0.1;
		vec2 r = g + o - f;
		if (dot(mr - r, mr - r) > 0.00001)
			md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
	}
	return vec3(md, id, length(mr));
}

void fragment() {
	vec2 p = UV * cells;

	// трава: крупные пятна оттенков, мелкие штрихи, волны ветра
	float n1 = fbm(p * 1.1);
	float n2 = fbm(p * 3.7 + 7.0);
	vec3 g = mix(grass_a, grass_b, n1);
	g = mix(g, grass_c, smoothstep(0.52, 0.85, n2) * 0.55);
	float blades = vnoise(p * vec2(46.0, 20.0));
	g *= 0.90 + 0.20 * blades;
	float wind = fbm(p * 0.55 + vec2(TIME * 0.10, TIME * 0.04));
	g += vec3(0.035, 0.055, 0.025) * smoothstep(0.52, 0.80, wind);
	// мягкий рельеф: освещение сверху-слева по наклону шума
	float hgt = fbm(p * 0.9 + 21.0);
	float hx = fbm((p + vec2(0.06, 0.0)) * 0.9 + 21.0) - hgt;
	float hy = fbm((p + vec2(0.0, 0.06)) * 0.9 + 21.0) - hgt;
	g *= 1.0 + clamp((-hx - hy) * 6.0, -0.18, 0.18);
	vec2 cell = floor(p);
	g *= 1.0 + 0.022 * mod(cell.x + cell.y, 2.0);

	// дорога
	float d = texture(road_tex, UV).r * 2.0;
	float edge_noise = (fbm(p * 3.0) - 0.5) * 0.11 + (vnoise(p * 14.0) - 0.5) * 0.03;
	float hw = 0.40 + edge_noise;
	float inside = 1.0 - smoothstep(hw - 0.025, hw + 0.025, d);
	vec3 dirt = mix(dirt_a, dirt_b, fbm(p * 6.0));
	float peb = smoothstep(0.74, 0.80, vnoise(p * 20.0));
	dirt = mix(dirt, dirt_b * 1.28, peb * 0.55);
	float pit = smoothstep(0.80, 0.86, vnoise(p * 26.0 + 3.0));
	dirt = mix(dirt, dirt_a * 0.6, pit * 0.5);
	float rut = exp(-pow((d - 0.16) / 0.045, 2.0));
	dirt *= 1.0 - 0.14 * rut;
	dirt *= 1.0 + 0.10 * smoothstep(0.0, 0.12, d) * (1.0 - smoothstep(0.12, 0.30, d));

	// булыжник: камни разного оттенка, со швами и объёмом; посередине протоптано до земли
	vec3 vo = voronoi(p * 4.2);
	float stone_id = vo.y;
	vec3 stone = mix(vec3(0.42, 0.41, 0.40), vec3(0.60, 0.57, 0.52), stone_id);
	stone = mix(stone, dirt_b * 1.15, 0.25);
	stone *= 0.80 + 0.32 * (1.0 - smoothstep(0.0, 0.45, vo.z));
	stone *= 0.92 + 0.12 * vnoise(p * 30.0);
	float seam = 1.0 - smoothstep(0.015, 0.06, vo.x);
	stone = mix(stone, dirt_edge * 0.9, seam * 0.85);
	// бордюр: крупные тёмные камни по краю
	vec3 vc = voronoi(p * 2.6 + 9.0);
	float curb_band = smoothstep(hw - 0.17, hw - 0.10, d);
	vec3 curb = mix(vec3(0.33, 0.33, 0.35), vec3(0.47, 0.46, 0.45), vc.y) * (0.85 + 0.25 * (1.0 - smoothstep(0.0, 0.5, vc.z)));
	curb = mix(curb, dirt_edge * 0.7, 1.0 - smoothstep(0.02, 0.07, vc.x));
	stone = mix(stone, curb, curb_band);
	float worn = smoothstep(0.55, 0.30, d / hw) * smoothstep(0.35, 0.70, fbm(p * 1.3 + 5.0));
	float cob = cobble * (1.0 - worn * 0.85);
	cob *= smoothstep(0.25, 0.5, fbm(p * 0.7 + 2.0) + cobble * 0.45);
	dirt = mix(dirt, stone, clamp(cob, 0.0, 1.0));

	vec3 col = mix(g, dirt, inside);

	// тёмная кромка и мягкая тень на траве рядом с дорогой
	float rim = smoothstep(hw - 0.13, hw - 0.01, d) * inside;
	col = mix(col, dirt_edge, rim * 0.62);
	float outer = (1.0 - inside) * smoothstep(hw + 0.26, hw, d);
	col *= 1.0 - 0.34 * outer;
	// трава у края слегка нависает над дорогой
	float fringe = smoothstep(0.30, 0.62, vnoise(p * 34.0)) * smoothstep(hw - 0.05, hw + 0.02, d) * (1.0 - smoothstep(hw + 0.02, hw + 0.10, d));
	col = mix(col, g * 1.28, fringe * 0.55);

	// снег
	float sn = smoothstep(0.30, 0.78, fbm(p * 1.5 + 3.0)) * snow;
	col = mix(col, vec3(0.86, 0.93, 1.0), sn * (1.0 - inside * 0.78));

	// тени облаков
	float cl = fbm(p * 0.20 + vec2(TIME * 0.025, TIME * 0.006));
	col *= 0.86 + 0.26 * smoothstep(0.34, 0.72, cl);

	// тень по краю поля: обрезка выглядит как рамка, а не срез
	vec2 e = min(UV, 1.0 - UV) * cells;
	float border = smoothstep(0.0, 0.55, min(e.x, e.y));
	col *= 0.62 + 0.38 * border;

	COLOR = vec4(col * tint, 1.0);
}
