extends DirectionalLight3D

## 让太阳（平行光）绕 Z 轴公转：在 XY 平面上以 orbit_radius 为半径、绕 orbit_center 画圆，
## 并始终朝向中心照射，从而模拟昼夜变化。

## 公转中心点（世界坐标）
@export var orbit_center: Vector3 = Vector3.ZERO
## 公转半径（米）
@export var orbit_radius: float = 44.273
## 公转角速度（度/秒），正数绕 Z 轴逆时针，负数顺时针
@export var angular_speed: float = 15.0
## 初始角度（度）：0° 在 +X 方向，90° 在 +Y（正上方）
@export var start_angle_deg: float = 90.0
## 是否始终朝向公转中心（关闭后只做位移，保持自身朝向不变）
@export var look_at_center: bool = true

## 当前角度（弧度）
var _angle_rad: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_angle_rad = deg_to_rad(start_angle_deg)
	_apply_orbit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_angle_rad = fmod(_angle_rad + deg_to_rad(angular_speed) * delta, TAU)
	_apply_orbit()


func _apply_orbit() -> void:
	global_position = orbit_center + Vector3(cos(_angle_rad), sin(_angle_rad), 0.0) * orbit_radius
	# 公转方向始终位于 XY 平面内，用 Vector3.BACK 作为 up 可避免与朝向平行导致的报错
	if look_at_center and orbit_radius > 0.0:
		look_at(orbit_center, Vector3.BACK)
