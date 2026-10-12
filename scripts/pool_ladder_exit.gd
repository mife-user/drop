extends Area3D
## 梯子入口只做检测；贴梯攀爬并跨上池沿后，立即归还玩家控制。

## 仅允许这个玩家触发。
@export var player: CharacterBody3D
## 贴梯攀爬的顶部脚底位置，X/Z 同时决定角色贴梯的位置。
@export var climb_point: Marker3D
## 跨过梯子后站上池沿的位置。
@export var bank_point: Marker3D
## 靠近并抓住梯子所需时间（秒）。
@export_range(0.1, 1.0, 0.05) var approach_duration: float = 0.25
## 向上攀爬速度（米/秒），水中位置越深，攀爬时间越长。
@export_range(0.3, 2.0, 0.05) var climb_speed: float = 0.9
## 梯子踏步间距（米），决定交替发力的节奏。
@export_range(0.15, 0.5, 0.01) var rung_spacing: float = 0.3
## 攀爬速度的节奏变化量；0 为匀速，不会产生反向下滑。
@export_range(0.0, 0.7, 0.05) var pull_strength: float = 0.35
## 交替发力时的轻微侧移（米），填 0 可关闭，不旋转摄像机。
@export_range(0.0, 0.03, 0.002) var body_sway: float = 0.012
## 跨过池沿所需时间（秒）。
@export_range(0.3, 1.2, 0.05) var step_over_duration: float = 0.65
## 跨步时额外抬脚高度（米），跨过扶梯顶部后立即踩上池沿。
@export_range(0.1, 0.5, 0.01) var step_lift: float = 0.35

var _climbing: bool = false
var _physics_was_enabled: bool = false
var _controls_locked: bool = false
var _movement: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _has_route() -> bool:
	return is_instance_valid(player) and is_instance_valid(climb_point) \
		and is_instance_valid(bank_point)


func _on_body_entered(body: Node3D) -> void:
	if body != player or _climbing or not _has_route():
		return
	_climbing = true
	_start_climb.call_deferred()


func _start_climb() -> void:
	if not _has_route():
		_climbing = false
		return
	_physics_was_enabled = player.is_physics_processing()
	_controls_locked = true
	# 暂停按键位移和重力，保留鼠标观察，摄像机随身体移动。
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var start: Vector3 = player.global_position
	var grip := Vector3(climb_point.global_position.x, start.y, climb_point.global_position.z)
	var top: Vector3 = climb_point.global_position
	top.y = maxf(top.y, start.y)
	var bank: Vector3 = bank_point.global_position
	var height: float = top.y - grip.y
	var steps: int = maxi(1, ceili(height / maxf(rung_spacing, 0.15)))
	var forward: Vector3 = bank - top
	forward.y = 0.0
	var side: Vector3 = forward.normalized().cross(Vector3.UP)
	_movement = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# 各段自行插值；身体的上移带有发力节奏，不在每级踏步处完全停住。
	_movement.tween_method(_approach.bind(start, grip), 0.0, 1.0, maxf(approach_duration, 0.1))
	_movement.tween_method(_climb_rungs.bind(grip, top, steps, side), 0.0, 1.0, maxf(height / maxf(climb_speed, 0.3), 0.2))
	_movement.tween_method(_step_over.bind(top, bank), 0.0, 1.0, maxf(step_over_duration, 0.3))
	_movement.tween_callback(_finish_climb)


func _approach(progress: float, start: Vector3, end: Vector3) -> void:
	_move_player(start.lerp(end, smoothstep(0.0, 1.0, progress)))


func _climb_rungs(progress: float, start: Vector3, end: Vector3, steps: int, side: Vector3) -> void:
	var time: float = smoothstep(0.0, 1.0, progress)
	var phase: float = TAU * float(steps) * time
	# 曲线导数始终大于零：提腿时慢一点，发力时快一点，没有电梯式倒退。
	var pull: float = time - clampf(pull_strength, 0.0, 0.7) * sin(phase) / (TAU * float(steps))
	var position: Vector3 = start.lerp(end, pull)
	position += side * sin(phase * 0.5) * sin(PI * time) * clampf(body_sway, 0.0, 0.03)
	_move_player(position)


func _step_over(progress: float, start: Vector3, end: Vector3) -> void:
	var time: float = smoothstep(0.0, 1.0, progress)
	var position: Vector3 = start.lerp(end, time)
	position.y += sin(PI * time) * maxf(step_lift, 0.0)
	_move_player(position)


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
	# 出口被移除时也归还控制，允许角色按正常重力落下。
	if _movement != null and _movement.is_valid():
		_movement.kill()
	_finish_climb()
