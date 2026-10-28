shader_type spatial;
// Achsenparallele Schnittebene durch ein 3D-Skalarfeld.
// axis 0: z konstant (xy), 1: y konstant (xz), 2: x konstant (yz).
// Die Textur ist [ny, nx, nz] (Breite ny, Hoehe nx), daher wird (x, y) vertauscht.
render_mode unshaded, cull_disabled;

#include "res://colormap.gdshaderinc"

uniform sampler3D vol : filter_linear, repeat_disable;
uniform int axis = 0;
uniform float slice : hint_range(0.0, 1.0) = 0.5;
uniform int colormap = 0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 v;
	if (axis == 0) {
		v = vec3(UV.x, UV.y, slice);
	} else if (axis == 1) {
		v = vec3(UV.x, slice, UV.y);
	} else {
		v = vec3(slice, UV.x, UV.y);
	}
	float r = textureLod(vol, vec3(v.y, v.x, v.z), 0.0).r;
	ALBEDO = apply_colormap(r, colormap);
	ALPHA = alpha;
}
