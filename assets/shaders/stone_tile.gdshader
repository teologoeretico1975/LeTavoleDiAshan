shader_type canvas_item;

// Soglia di luminanza sotto cui il pixel diventa trasparente.
// 0.0 = nessuna trasparenza, 1.0 = tutto trasparente.
// Regola questo valore se i bordi della pietra vengono tagliati (abbassa)
// o se rimane troppo sfondo scuro (alza).
uniform float cutoff : hint_range(0.0, 1.0) = 0.12;
uniform float feather : hint_range(0.0, 0.2) = 0.06;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float alpha = smoothstep(cutoff, cutoff + feather, luma);
	COLOR = vec4(col.rgb, alpha);
}
