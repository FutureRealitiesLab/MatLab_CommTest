// Gemeinsame Farbskalen fuer Volumen- und Hoehenkarten-Shader.
// id: 0 = rainbow, 1 = hot, 2 = gray, 3 = viridis

vec3 apply_colormap(float t, int id) {
	t = clamp(t, 0.0, 1.0);
	if (id == 1) {
		return vec3(clamp(3.0 * t, 0.0, 1.0), clamp(3.0 * t - 1.0, 0.0, 1.0), clamp(3.0 * t - 2.0, 0.0, 1.0));
	}
	if (id == 2) {
		return vec3(t);
	}
	if (id == 3) {
		// Polynom-Naeherung von viridis
		const vec3 c0 = vec3(0.2777273272, 0.0054073445, 0.3340998053);
		const vec3 c1 = vec3(0.1050930431, 1.4046135299, 1.3845901626);
		const vec3 c2 = vec3(-0.3308618287, 0.2148475595, 0.0950951630);
		const vec3 c3 = vec3(-4.6342304990, -5.7991009734, -19.3324409563);
		const vec3 c4 = vec3(6.2282699363, 14.1799333668, 56.6905526007);
		const vec3 c5 = vec3(4.7763849977, -13.7451453777, -65.3530326334);
		const vec3 c6 = vec3(-5.4354558559, 4.6458526122, 26.3124352496);
		return clamp(c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6))))), 0.0, 1.0);
	}
	// rainbow: Blau -> Cyan -> Gelb -> Rot
	vec3 a = vec3(0.05, 0.1, 0.9);
	vec3 b = vec3(0.0, 0.9, 0.9);
	vec3 c = vec3(1.0, 0.9, 0.1);
	vec3 d = vec3(1.0, 0.1, 0.05);
	if (t < 0.33) return mix(a, b, t / 0.33);
	if (t < 0.66) return mix(b, c, (t - 0.33) / 0.33);
	return mix(c, d, (t - 0.66) / 0.34);
}
