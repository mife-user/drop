shader_type spatial;

// 草的风摆着色器。
// 网格由 scripts/草/草地.gd 用纯三角面程序化生成：
//   UV.y = 0 在草根，1 在草尖；
//   MultiMesh 的「自定义数据」里存了每一丛草的摆动相位、方向和颜色变化。
// 这样整片草共用一个材质、一次绘制，却能各摆各的，不会像一整块板子。

render_mode cull_disabled, diffuse_lambert_wrap;

// 草根颜色
uniform vec4 root_color : source_color = vec4(0.09, 0.20, 0.05, 1.0);
// 草尖颜色
uniform vec4 tip_color : source_color = vec4(0.44, 0.70, 0.25, 1.0);
// 草尖最大摆动幅度（米）；调大风更猛
uniform float wind_strength : hint_range(0.0, 0.5, 0.005) = 0.05;
// 摆动速度
uniform float wind_speed : hint_range(0.0, 10.0, 0.1) = 1.5;
// 第二层阵风的比例，0 = 只有单一节奏，越大越自然
uniform float gust_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
// 每丛草的颜色随机变化幅度
uniform float color_variation : hint_range(0.0, 1.0, 0.01) = 0.18;
// 背光透光感
uniform float translucency : hint_range(0.0, 1.0, 0.01) = 0.15;

varying float v_height;
varying float v_tint;

void vertex() {
	// UV.y 是草叶高度权重；平方一下让根部更稳、草尖摆得更明显
	float h = clamp(UV.y, 0.0, 1.0);
	float bend = h * h;

	// 每一丛草从自定义数据里取自己的相位/方向，整片草就不会同步摆
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	float dir = INSTANCE_CUSTOM.g * 6.2831853;
	float t = TIME * wind_speed + phase;
	float sway = sin(t) + gust_amount * sin(t * 2.3 + phase * 0.7);
	sway *= 0.5;

	VERTEX.x += cos(dir) * sway * wind_strength * bend;
	VERTEX.z += sin(dir) * sway * wind_strength * bend;

	v_height = h;
	v_tint = mix(1.0 - color_variation, 1.0 + color_variation, INSTANCE_CUSTOM.b);
}

void fragment() {
	vec3 grass_color = mix(root_color.rgb, tip_color.rgb, smoothstep(0.0, 1.0, v_height));
	ALBEDO = grass_color * v_tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// 草根压暗，避免整丛草从根到尖一样亮
	AO = mix(0.55, 1.0, v_height);
	// 一点透光感，背光看时草尖不会死黑
	BACKLIGHT = tip_color.rgb * translucency;
}
