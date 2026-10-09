extends CharacterBody3D

## 非玩家奶蛋：由控制器连续安排随机路段，活动结束后沿出口路线离开。
## 场景中始终复用这一只实体；未出场时隐藏并关闭碰撞。
signal crossing_finished(reached_destination: bool)

## 空中水平移动速度（米/秒）。
@export_range(0.1, 10.0, 0.1) var move_speed: float = 1.5
## 每次跳跃的目标高度（米）。
@export_range(0.05, 3.0, 0.05) var jump_height: float = 0.5
## 落地后的停顿时间（秒）。
@export_range(0.0, 2.0, 0.01) var hop_pause: float = 0.12
## 重力加速度（米/秒²）。
@export_range(0.1, 50.0, 0.1) var gravity: float = 16.0
## 起跳拉伸、落地压扁的幅度，设为零关闭。
@export_range(0.0, 0.3, 0.01) var squash_amount: float = 0.12

var active: bool = false
var waiting_for_route: bool = false
var movement_guard: Callable
var _destination: Vector3
var _pause_left: float = 0.0
var _stall_time: float = 0.0
var _visual_scale: Vector3 = Vector3.ONE
var _look_camera: Camera3D

@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D


## 保存模型比例，等待控制器安排第一次出场。
func _ready() -> void:
	_visual_scale = _visual.scale
	deactivate()


## 每次从静止状态开始；复用节点，避免重复生成多个实体。
func begin_crossing(start: Vector3, destination: Vector3, look_camera: Camera3D = null) -> void:
	global_position = start + Vector3.UP * 0.025
	_destination = destination
	velocity = Vector3.ZERO
	_pause_left = hop_pause
	_stall_time = 0.0
	_look_camera = look_camera
	_visual.scale = _visual_scale
	active = true
	waiting_for_route = false
	visible = true
	_collision.disabled = false
	_update_facing()


## 连续换路只更新目的地，不重置位置或跳跃速度，也不隐藏模型。
func travel_to(destination: Vector3) -> void:
	_destination = destination
	_stall_time = 0.0
	waiting_for_route = false
	_update_facing()


## 结束后关闭物理碰撞，等待下一次出场。
func deactivate() -> void:
	active = false
	waiting_for_route = false
	visible = false
	velocity = Vector3.ZERO
	if is_instance_valid(_collision):
		_collision.disabled = true


## 使用真实重力跳跃；到达路点后通知控制器继续选路。
func _physics_process(delta: float) -> void:
	if not active:
		return
	if waiting_for_route:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		_update_facing()
		_update_visual(delta)
		return
	var offset: Vector3 = _destination - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance < 0.08 and is_on_floor():
		_finish(true)
		return
	var direction: Vector3 = offset.normalized() if distance > 0.01 else Vector3.ZERO
	var was_on_floor: bool = is_on_floor()
	var hopping: bool = not was_on_floor
	if was_on_floor:
		_pause_left = maxf(0.0, _pause_left - delta)
		velocity.y = 0.0
		if _pause_left <= 0.0 and distance >= 0.08:
			velocity.y = sqrt(2.0 * gravity * jump_height)
			hopping = true
	else:
		velocity.y -= gravity * delta
	var horizontal_speed: float = minf(move_speed, distance / delta) if hopping and distance >= 0.08 else 0.0
	velocity.x = direction.x * horizontal_speed
	velocity.z = direction.z * horizontal_speed
	# 镜头内活动受可见范围限制；正式退场时控制器允许穿过屏幕边界。
	var next_position: Vector3 = global_position + velocity * delta
	if movement_guard.is_valid() and not movement_guard.call(next_position):
		_finish(false)
		return
	var before_move: Vector3 = global_position
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		_pause_left = hop_pause
	# 小台阶接触时允许下一跳继续；持续被挡住则请求重新选路。
	var progress := Vector2(global_position.x - before_move.x, global_position.z - before_move.z)
	_stall_time = _stall_time + delta if progress.length() < 0.001 and distance >= 0.08 else 0.0
	if _stall_time > 2.0:
		_finish(false)
		return
	_update_facing()
	_update_visual(delta)


func _finish(reached: bool) -> void:
	waiting_for_route = true
	velocity.x = 0.0
	velocity.z = 0.0
	crossing_finished.emit(reached)


## 模型的正面为 +Z，只旋转模型，保持胶囊碰撞体竖直。
func _face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if not direction.is_zero_approx():
		var current_scale: Vector3 = _visual.scale
		_visual.look_at(_visual.global_position + direction, Vector3.UP, true)
		_visual.scale = current_scale


## 朝向镜头的出场只转模型的水平角度，跳跃和碰撞仍沿原路线进行。
func _update_facing() -> void:
	var target: Vector3 = _destination
	if is_instance_valid(_look_camera):
		target = _look_camera.global_position
	_face_direction(target - global_position)


## 保留落地压扁、起跳拉伸的轻微弹性。
func _update_visual(delta: float) -> void:
	var target_scale: Vector3 = Vector3.ONE
	if is_on_floor():
		target_scale = Vector3(1.0 + squash_amount, 1.0 - squash_amount, 1.0 + squash_amount)
	elif velocity.y > 0.0:
		target_scale = Vector3(1.0 - squash_amount * 0.5, 1.0 + squash_amount, 1.0 - squash_amount * 0.5)
	_visual.scale = _visual.scale.lerp(_visual_scale * target_scale, 1.0 - exp(-18.0 * delta))
