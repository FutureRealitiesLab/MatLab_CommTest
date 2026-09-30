shader_type spatial;
// Hoehenkarte fuer 2D-Felder auf einem PlaneMesh (lokal -0.5..0.5, Hoehe -0.5..0.5).
// height_prev/blend: zeitliche Ueberblendung zwischen dem vorigen und dem aktuellen Frame.
render_mode cull_disabled;

#include "res://colormap.gdshaderinc"

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D height_prev : filter_linear, repeat_disable;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
uniform int colormap = 0;
uniform float value_min = 0.0;
uniform float value_max = 1.0;
uniform float normal_strength = 0.5;

varying float v_val;

float sample_val(vec2 uv) {
	float a = textureLod(height_prev, uv, 0.0).r;
	float b = textureLod(height_tex, uv, 0.0).r;
	return clamp((mix(a, b, blend) - value_min) / (value_max - value_min), 0.0, 1.0);
}

void vertex() {
	float n = sample_val(UV);
	VERTEX.y = n - 0.5;
	v_val = n;
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(height_tex, 0));
	float hl = sample_val(UV - vec2(px.x, 0.0));
	float hr = sample_val(UV + vec2(px.x, 0.0));
	float hd = sample_val(UV - vec2(0.0, px.y));
	float hu = sample_val(UV + vec2(0.0, px.y));
	float dhdx = (hr - hl) / (2.0 * px.x);
	float dhdz = (hu - hd) / (2.0 * px.y);
	vec3 n_local = normalize(vec3(-dhdx * normal_strength, 1.0, -dhdz * normal_strength));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	ALBEDO = apply_colormap(v_val, colormap);
	ROUGHNESS = 0.8;
}
