class_name SunLight
extends DirectionalLight3D

## 让太阳（平行光）绕 Z 轴在天空上半部分摆动：从一侧贴近地平线的「晚霞」角度升到正上方，
## 再落到另一侧的「晚霞」角度，然后用同样的路径摆回来。
## 太阳永远不会落到地平线以下，所以场景只有白天和晚霞，没有黑夜。
## 摆动由余弦驱动，在两头（晚霞）停留更久、中间（正午）走得更快。

## 公转中心点（世界坐标）
@export var orbit_center: Vector3 = Vector3.ZERO
## 公转半径（米）
@export var orbit_radius: float = 44.273
## 是否始终朝向公转中心（关闭后只做位移，保持自身朝向不变）
@export var look_at_center: bool = true

## 摆动的最低角度（度）：越大离地平线越高、晚霞越淡；12 表示最低时离地平线 12°
@export_range(1.0, 45.0, 0.5) var dusk_angle_deg: float = 12.0
## 一个完整来回「晚霞 → 白天 → 晚霞」的时长（秒）
@export_range(1.0, 600.0, 0.5) var cycle_seconds: float = 24.0
## 起始相位：0 / 0.5 / 1 = 停在晚霞端，0.25 / 0.75 = 停在正午
@export_range(0.0, 1.0, 0.01) var start_phase: float = 0.25

## 正午时的光强
@export_range(0.0, 8.0, 0.01) var noon_energy: float = 1.0
## 晚霞时的光强：别设成 0，否则晚霞段会暗到看不清
@export_range(0.0, 8.0, 0.01) var dusk_energy: float = 0.55
## 正午时的光色
@export var noon_color: Color = Color(1, 1, 1)
## 晚霞时的光色（偏暖橙）
@export var dusk_color: Color = Color(1.0, 0.62, 0.35)

## 当前太阳高度角的正弦值：1 = 正上方，越接近 0 越贴近地平线（本脚本下永远不会是负数）
var elevation: float = 0.0
## 归一化的「白天程度」：0 = 处在最低的晚霞角度，1 = 正午，中间连续过渡。
## 供 scripts/day_night.gd 读取以联动环境光与背景色，不要在检查器里手动改。
var daylight: float = 1.0

## 当前摆动相位（0〜1），0 与 0.5 是两端的晚霞，0.25 / 0.75 是正午
var _phase: float = 0.0
## 当前角度（弧度）
var _angle_rad: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_phase = clampf(start_phase, 0.0, 1.0)
	_apply_orbit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_phase = fmod(_phase + delta / maxf(cycle_seconds, 0.001), 1.0)
	_apply_orbit()


func _apply_orbit() -> void:
	# 余弦来回：0 → 1 → 0，两端（晚霞）停留更久，中间（正午）快速掠过
	var arc: float = (1.0 - cos(_phase * TAU)) * 0.5
	# 在 dusk_angle_deg 与 180-dusk_angle_deg 之间摆动，中途正好经过 90°（正上方）
	_angle_rad = deg_to_rad(lerpf(dusk_angle_deg, 180.0 - dusk_angle_deg, arc))
	global_position = orbit_center + Vector3(cos(_angle_rad), sin(_angle_rad), 0.0) * orbit_radius
	# 摆动方向始终位于 XY 平面内，用 Vector3.BACK 作为 up 可避免与朝向平行导致的报错
	if look_at_center and orbit_radius > 0.0:
		look_at(orbit_center, Vector3.BACK)
	_update_light()


## 按「白天程度」决定光强与光色：最低点也有 dusk_energy / dusk_color，不会黑下去。
func _update_light() -> void:
	elevation = sin(_angle_rad)
	# 把高度角映射成 0（最低的晚霞角度）〜1（正上方）
	var lowest: float = sin(deg_to_rad(dusk_angle_deg))
	daylight = clampf(inverse_lerp(lowest, 1.0, elevation), 0.0, 1.0)
	light_energy = lerpf(dusk_energy, noon_energy, daylight)
	light_color = dusk_color.lerp(noon_color, smoothstep(0.0, 1.0, daylight))
