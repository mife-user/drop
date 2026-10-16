extends WaterTurret
class_name NegativePlacedItem

## 复用炮台的携带、地面探测、半透明预览和落点圈，不使用喷水及拆除逻辑。
## 放置后只旋转模型，根节点固定，避免旋转改变吸水位置。
@export var pool: WaterSink
## 放下后的生效时长（秒），携带预览期间不计时。
@export_range(0.1, 600.0, 0.1) var duration: float = 10.0
## 每秒最多吸收的水量（立方米），水池没有水时只旋转。
@export_range(0.0, 100.0, 0.001) var drain_per_second: float = 0.1
## 模型每秒绕竖直轴旋转的角度。
@export var spin_speed: float = 180.0
## 池底碰撞与吸水区底面的允许高度误差（米）。
@export_range(0.0, 1.0, 0.01) var bottom_tolerance: float = 0.3

var remaining: float = 0.0
var in_pool: bool = false
var activated: bool = false

## 覆盖炮台发射循环：预览时沿用跟随，放置后只自转和吸水。
func _physics_process(delta: float) -> void:
	if carrying:
		_update_carry(delta)
		return
	if not activated:
		return
	var elapsed: float = minf(maxf(delta, 0.0), remaining)
	if is_instance_valid(model):
		model.rotate_y(deg_to_rad(spin_speed) * elapsed)
	if in_pool and is_instance_valid(pool):
		pool.remove_water(maxf(drain_per_second, 0.0) * elapsed)
	remaining = maxf(remaining - elapsed, 0.0)
	if remaining <= 0.000001:
		activated = false
		queue_free()

func place() -> void:
	if not carrying or not _shadow_valid:
		return
	super()
	in_pool = _point_in_pool(global_position)
	remaining = maxf(duration, 0.0)
	activated = true

## 池内允许放置，仍由炮台原有射线保证下方存在落点。
func _blocked_at(_point: Vector3) -> bool:
	return false

## 仅响应左键放置，不支持滚轮调整或 P 拆除。
func _unhandled_input(event: InputEvent) -> void:
	if not carrying or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _is_place_pressed(event):
		get_viewport().set_input_as_handled()
		place()

func _is_firing() -> bool:
	return false

## 用实际水池碰撞盒判断落点，不能只按射线是否穿过水面判断岸边物体。
func _point_in_pool(point: Vector3) -> bool:
	if not is_instance_valid(pool) or not is_instance_valid(pool.shape_node):
		return false
	var box: BoxShape3D = pool.shape_node.shape as BoxShape3D
	if box == null:
		return false
	var local: Vector3 = pool.shape_node.to_local(point)
	var half: Vector3 = box.size * 0.5
	var tolerance: float = bottom_tolerance / maxf(pool.shape_node.global_basis.y.length(), 0.001)
	return absf(local.x) < half.x and absf(local.z) < half.z and local.y <= half.y and local.y >= -half.y - tolerance
