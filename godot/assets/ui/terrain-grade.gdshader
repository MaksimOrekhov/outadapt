shader_type canvas_item;
// Quiet the terrain's high frequency contrast so units remain the visual foreground.
void fragment() {
	vec4 texel = COLOR;
	float value = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 muted = mix(vec3(value), texel.rgb, 0.76);
	COLOR = vec4(mix(vec3(0.13, 0.17, 0.15), muted, 0.80), texel.a);
}
