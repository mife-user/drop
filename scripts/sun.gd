class_name SunLight
extends DirectionalLight3D

## 让太阳（平行光）绕 Z 轴公转一整圈，模拟完整昼夜：白天 → 晚霞 → 夜晚 → 日出 → 白天。
##
## 光强与光色由「夜晚 / 晚霞 / 正午」三套配色平滑过渡而来，权重只看太阳高度：
##   高度 0（太阳在正下方）= 夜晚   0.5（地平线）= 晚霞   1（正上方）= 正午
## 两段过渡都用 smoothstep，它在两端导数为 0，所以在地平线这个接缝处不会出现硬拐角。

## 太阳所在的分组名。路灯这类需要判断「现在是不是晚上」的节点，靠这个分组找到太阳，
## 不用在场景里一处处连 NodePath —— 见 scripts/路灯.gd。
const GROUP_NAME := "太阳"

## 公转中心点（世界坐标）
@export var orbit_center: Vector3 = Vector3.ZERO
## 公转半径（米）
@export var orbit_radius: float = 44.273
## 公转角速度（度/秒）：360 / 该值 = 一整天多少秒。15 即 24 秒一天，一半是黑夜
@export var angular_speed: float = 15.0
## 初始角度（度）：0° 在 +X 地平线，90° 在 +Y 正上方（正午），180° 在 -X 地平线
@export var start_angle_deg: float = 90.0
## 是否始终朝向公转中心（关闭后只做位移，保持自身朝向不变）
@export var look_at_center: bool = true

## 夜晚的光色（冷蓝，当作月光）
@export var night_color: Color = Color(0.45, 0.55, 0.95)
## 夜晚的光强：设成 0 则夜里完全没有直射光，只剩环境光
@export_range(0.0, 8.0, 0.01) var night_energy: float = 0.07
## 晚霞（日出 / 日落）的光色，偏暖橙
@export var dusk_color: Color = Color(1.0, 0.45, 0.22)
## 晚霞时的光强
@export_range(0.0, 8.0, 0.01) var dusk_energy: float = 0.5
## 正午的光色
@export var day_color: Color = Color(1.0, 0.98, 0.92)
## 正午的光强
@export_range(0.0, 8.0, 0.01) var day_energy: float = 1.0

## 太阳高度角的正弦值：1 = 正上方，0 = 地平线，-1 = 正下方
var elevation: float = 0.0
## 归一化高度：0 = 正下方（深夜），0.5 = 地平线，1 = 正上方（正午）。
## 供 scripts/day_night.gd 读取以联动环境光与背景色，不要在检查器里手动改。
var height: float = 1.0

## 当前时刻（小时，0.0 ~ 24.0 的连续小数）：6.0 = 日出，12.0 = 正午，18.0 = 日落，0.0 = 午夜。
## 供 scripts/时钟.gd 读取以拨动指针，不要在检查器里手动改。
## 想改「开局是几点」就改本节点的 start_angle_deg，想改「一天多长」就改 angular_speed，
## 这里会自动跟上 —— 所有需要「现在几点」的节点都读这一个值，不要各自再算一遍。
var time_of_day: float = 12.0

## 当前角度（弧度）
var _angle_rad: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 加进「太阳」分组，需要按昼夜开关的节点（如路灯）直接按组查找即可
	add_to_group(GROUP_NAME)
	_angle_rad = deg_to_rad(start_angle_deg)
	_apply_orbit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_angle_rad = fmod(_angle_rad + deg_to_rad(angular_speed) * delta, TAU)
	_apply_orbit()


func _apply_orbit() -> void:
	global_position = orbit_center + Vector3(cos(_angle_rad), sin(_angle_rad), 0.0) * orbit_radius
	# 角度换算成钟点：0°（+X 地平线）当日出 6:00，90° 正午，180° 日落，270° 午夜。
	# 一圈 360° 正好 24 小时，所以 15° = 一个游戏小时，fmod 负责把 24~30 点折回 0~6 点。
	time_of_day = fmod(_angle_rad / TAU * 24.0 + 6.0, 24.0)
	# 公转方向始终位于 XY 平面内，用 Vector3.BACK 作为 up 可避免与朝向平行导致的报错
	if look_at_center and orbit_radius > 0.0:
		look_at(orbit_center, Vector3.BACK)
	_update_light()


## 按高度分两段过渡：地平线以下「深夜 → 晚霞」，地平线以上「晚霞 → 正午」。
func _update_light() -> void:
	elevation = sin(_angle_rad)
	height = clampf((elevation + 1.0) * 0.5, 0.0, 1.0)
	# smoothstep 两端导数为 0，两段在 height = 0.5（地平线）处能平滑接上
	var to_dusk: float = smoothstep(0.0, 0.5, height)   # 0 = 深夜，1 = 晚霞
	var to_day: float = smoothstep(0.5, 1.0, height)    # 0 = 晚霞，1 = 正午
	light_color = night_color.lerp(dusk_color, to_dusk).lerp(day_color, to_day)
	light_energy = lerpf(lerpf(night_energy, dusk_energy, to_dusk), day_energy, to_day)
