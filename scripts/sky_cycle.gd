extends Node
## Continuous day cycle (a full day takes 20 minutes) and clear <-> overcast weather. Port of js/sky.js:
## sky colours, sun colour and strength, fog and exposure blend between keyframes by sun elevation; the moon
## takes over the directional light at night. The sky itself is drawn by shaders/sky.gdshader.

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const ENERGY := 0.6      # three.js light intensity -> Godot light energy

var hour := 14.0
var day_speed := 24.0 / 1200.0
var weather := 0.0
var weather_target := 0.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var sun_dir := Vector3.UP
var cloud_time := 0.0
var params := {}            # last blended keyframe values (the pond water reflects the same sky)
var moon_dir := Vector3.UP
var moon_amt := 0.0

var KEYS := [
	{"el": -14.0, "zenith": Color("#03060f"), "horizon": Color("#0f1828"), "ground": Color("#07080a"), "sun": Color("#ff7040"), "int": 0.0, "glow": 0.0, "disc": 0.0, "stars": 1.0, "fog": 0.009, "exp": 1.25},
	{"el": -5.0, "zenith": Color("#1a2747"), "horizon": Color("#7a5a6a"), "ground": Color("#15141a"), "sun": Color("#ff6a3c"), "int": 0.0, "glow": 1.2, "disc": 0.0, "stars": 0.35, "fog": 0.008, "exp": 1.2},
	{"el": 1.0, "zenith": Color("#34507f"), "horizon": Color("#f09a6a"), "ground": Color("#3a3029"), "sun": Color("#ff8a48"), "int": 1.2, "glow": 2.2, "disc": 1.0, "stars": 0.0, "fog": 0.0065, "exp": 1.08},
	{"el": 8.0, "zenith": Color("#3f6299"), "horizon": Color("#f0c098"), "ground": Color("#4a4238"), "sun": Color("#ffb06a"), "int": 2.2, "glow": 1.6, "disc": 1.0, "stars": 0.0, "fog": 0.0055, "exp": 1.0},
	{"el": 22.0, "zenith": Color("#3d70b6"), "horizon": Color("#cfd9e2"), "ground": Color("#4e5244"), "sun": Color("#ffe4c4"), "int": 2.5, "glow": 1.1, "disc": 1.0, "stars": 0.0, "fog": 0.0048, "exp": 0.96},
	{"el": 45.0, "zenith": Color("#3f78bf"), "horizon": Color("#c3d6e6"), "ground": Color("#4e5244"), "sun": Color("#fff1de"), "int": 2.6, "glow": 1.0, "disc": 1.0, "stars": 0.0, "fog": 0.0045, "exp": 0.95},
]
var moon_color := Color("#9fb6ff")
var moon_int := 0.45


func setup(env_node: WorldEnvironment, sun_light: DirectionalLight3D) -> void:
	sun = sun_light
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env_node.environment = env


func sun_elevation(h: float) -> float:
	return 55.0 * sin((h - 6.0) / 12.0 * PI)   # 0 at 06:00 and 18:00, 55 deg at noon


func is_night() -> bool:
	return sun_elevation(hour) < -3.0


## 0 at night .. 1 in full daylight
func daylight() -> float:
	return smoothstep(-6.0, 12.0, sun_elevation(hour)) * (1.0 - 0.3 * weather)


func phase_name() -> String:
	var el := sun_elevation(hour)
	if el < -6: return "Night"
	if el < 4: return "Sunrise" if hour < 12 else "Sunset"
	if el < 15: return "Morning" if hour < 12 else "Golden hour"
	return "Day"


func clock_text() -> String:
	var hh := int(hour)
	var mm := int((hour - hh) * 60)
	return "%02d:%02d" % [hh, mm]


func _params() -> Dictionary:
	var el := sun_elevation(hour)
	var a: Dictionary = KEYS[0]
	var c: Dictionary = KEYS[0]
	var t := 0.0
	if el >= KEYS[KEYS.size() - 1].el:
		a = KEYS[KEYS.size() - 1]
		c = a
	elif el > KEYS[0].el:
		for i in KEYS.size() - 1:
			if el >= KEYS[i].el and el <= KEYS[i + 1].el:
				a = KEYS[i]
				c = KEYS[i + 1]
				t = (el - a.el) / (c.el - a.el)
				break
	var p := {"el": el}
	for k in ["zenith", "horizon", "ground", "sun"]:
		p[k] = (a[k] as Color).lerp(c[k], t)
	for k in ["int", "glow", "disc", "stars", "fog", "exp"]:
		p[k] = lerpf(a[k], c[k], t)
	# Overcast: grey sky at the same brightness, sun mostly hidden, denser haze
	var w := weather
	if w > 0.001:
		var hz: Color = p.horizon
		var lum := 0.3 * hz.r + 0.59 * hz.g + 0.11 * hz.b
		p.zenith = (p.zenith as Color).lerp(Color("#d0d6dc") * (lum * 1.05 * 0.82), w)
		p.horizon = hz.lerp(Color("#dfe2e5") * (lum * 1.05), w)
		p.int *= 1.0 - 0.85 * w
		p.glow *= 1.0 - 0.85 * w
		p.disc *= 1.0 - w
		p.stars *= 1.0 - w
		p.fog = lerpf(p.fog, maxf(p.fog, 0.0085), w)
		p.exp *= 1.0 + 0.12 * w
	return p


func update(delta: float, focus: Vector3) -> void:
	hour = fmod(hour + delta * day_speed, 24.0)
	weather += (weather_target - weather) * minf(1.0, delta * 0.4)
	cloud_time += delta
	var p := _params()
	var el := deg_to_rad(p.el)
	var az := deg_to_rad(90.0 + (hour - 6.0) / 12.0 * 180.0)   # east -> south -> west
	sun_dir = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	params = p
	moon_dir = Vector3(-sun_dir.x * 0.6 + 0.3, maxf(0.35, -sun_dir.y), -sun_dir.z * 0.6).normalized()
	moon_amt = smoothstep(4.0, 12.0, -p.el) * (1.0 - weather * 0.7)

	var light_dir: Vector3
	if p.el > -2.0:
		light_dir = sun_dir
		if light_dir.y < 0.05:
			light_dir.y = 0.05
			light_dir = light_dir.normalized()
		sun.light_color = p.sun
		sun.light_energy = p.int * smoothstep(-2.0, 3.0, p.el) * ENERGY
	else:
		light_dir = moon_dir
		sun.light_color = moon_color
		sun.light_energy = moon_int * moon_amt * ENERGY
	sun.global_transform = Transform3D(Basis.looking_at(-light_dir, Vector3.UP), focus)

	sky_mat.set_shader_parameter("zenith", p.zenith)
	sky_mat.set_shader_parameter("horizon", p.horizon)
	sky_mat.set_shader_parameter("ground_col", p.ground)
	sky_mat.set_shader_parameter("sun_color", p.sun)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("sun_glow", p.glow)
	sky_mat.set_shader_parameter("sun_disc", p.disc)
	sky_mat.set_shader_parameter("stars", p.stars)
	sky_mat.set_shader_parameter("moon_vis", moon_amt)
	sky_mat.set_shader_parameter("cloud_cover", lerpf(0.42, 0.92, weather))
	sky_mat.set_shader_parameter("cloud_time", cloud_time)
	var day := daylight()
	var sc: Color = p.sun
	sky_mat.set_shader_parameter("cloud_lit", Color(1, 1, 1).lerp(sc, 0.45) * lerpf(0.08, 1.0, day))
	sky_mat.set_shader_parameter("cloud_shade", (p.horizon as Color) * lerpf(0.4, 0.75, day))

	env.fog_light_color = p.horizon
	env.fog_density = p.fog * 0.3
	env.tonemap_exposure = p.exp
	env.ambient_light_energy = lerpf(1.6, 1.0, day)


func sun_visibility() -> float:
	return smoothstep(-1.0, 4.0, sun_elevation(hour)) * (1.0 - 0.85 * weather)
