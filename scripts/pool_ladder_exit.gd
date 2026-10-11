extends Area3D
## 梯子水下入口：Area3D 只检测玩家，不阻挡移动；岸上位置由 Marker3D 调整。

## 仅允许这个玩家触发，奶蛋和水团不会被移动。
@export var player: CharacterBody3D
## 玩家脚底最终到达的位置，应放在梯子旁无障碍的地面上方。
@export var exit_point: Marker3D
## 从水中升起、移向岸边并落地的总时长（秒）。
@export_range(0.3, 5.0, 0.1) var climb_duration: float = 1.8
## 横移时脚底高于岸上落点的距离，默认避开池沿和旁边的躺椅。
@export_range(0.1, 3.0, 0.05) var clearance_height: float = 1.1

var _climbing: bool = false
var _physics_was_enabled: bool = false
var _controls_locked: bool = false
var _movement: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body != player or not is_instance_valid(player) or not is_instance_valid(exit_point):
		return
	if _climbing:
		return
	_climbing = true
	# 等物理查询结束后再接管位置，避免在碰撞回调中修改物理状态。
	_start_climb.call_deferred()


func _start_climb() -> void:
	if not is_instance_valid(player) or not is_instance_valid(exit_point):
		_climbing = false
		return
	_physics_was_enabled = player.is_physics_processing()
	_controls_locked = true
	# 暂停走路、跳跃和重力；鼠标观察仍然可用，摄像机随角色平滑上岸。
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var start: Vector3 = player.global_position
	var destination: Vector3 = exit_point.global_position
	var top: float = maxf(start.y, destination.y + clearance_height)
	var raised := Vector3(start.x, top, start.z)
	var above_exit := Vector3(destination.x, top, destination.z)
	var duration: float = maxf(climb_duration, 0.3)
	_movement = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 先升起再横移，避免沿直线从水下穿过池壁；最后缓缓落到岸边。
	_movement.tween_method(_move_player, start, raised, duration * 0.5)
	_movement.tween_method(_move_player, raised, above_exit, duration * 0.3)
	_movement.tween_method(_move_player, above_exit, destination, duration * 0.2)
	_movement.tween_callback(_finish_climb)


func _move_player(position: Vector3) -> void:
	if is_instance_valid(player):
		player.global_position = position


func _finish_climb() -> void:
	if _controls_locked and is_instance_valid(player):
		player.velocity = Vector3.ZERO
		player.set_physics_process(_physics_was_enabled)
	_controls_locked = false
	_climbing = false


func _exit_tree() -> void:
	# 出口被移除时也归还移动控制，避免玩家永久失去操作。
	if _movement != null and _movement.is_valid():
		_movement.kill()
	_finish_climb()
