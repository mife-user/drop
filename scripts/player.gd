extends CharacterBody3D

## 主人公移动控制：WASD 相对摄像机前后左右移动，空格跳跃。
## 碰撞、阻挡、贴地交给物理引擎（move_and_slide），水平速度和重力由本脚本按物理公式计算，
## 所以起跳是标准抛体运动——初速 v = sqrt(2 * 重力 * 跳跃高度)，空中松手会保持水平惯性。
## 地面水平速度按"起步 / 刹车 / 变向"三档时间参数平滑过渡，不会瞬间启停。
## 所有手感数值都是 @export，可直接在检查器里调，不用改代码。


## 第一人称摄像机（挂在主人公眼睛位置上的子节点），W 表示朝视线前方走。
## 留空时会自动取当前场景的摄像机。
@export var camera: Camera3D
## 地面最大移动速度（米/秒）。
@export_range(0.5, 20.0, 0.1) var move_speed: float = 4.0
## 起步时间（秒）：从静止加速到全速要多久，决定角色的"重量感"。
@export_range(0.02, 1.0, 0.01) var start_time: float = 0.20
## 刹车时间（秒）：松开按键后从全速停到静止要多久；通常比起步短，否则显得不听话。
@export_range(0.02, 1.0, 0.01) var stop_time: float = 0.12
## 变向时间（秒）：改变相当于一个全速的速度量要多久；比起步快，转身才俐落。
## 注意反向是两倍：从 +全速 掉头到 -全速 要抹掉 2 倍的量。
@export_range(0.02, 1.0, 0.01) var turn_time: float = 0.10
## 空中改变相当于一个全速的速度量要多久；比地面慢得多，跳跃落点只能在起跳前决定。
@export_range(0.02, 2.0, 0.01) var air_time: float = 0.35
## 单次跳跃能达到的高度（米），起跳初速由它和重力反推。
@export_range(0.05, 3.0, 0.05) var jump_height: float = 1.1
## 重力加速度（米/秒²），调大角色更"重"、下落更快。
@export_range(1.0, 60.0, 0.5) var gravity: float = 22.0
## 下落速度上限（米/秒），避免从高处掉下来越掉越快。
@export_range(1.0, 100.0, 1.0) var max_fall_speed: float = 25.0
## 土狼时间（秒）：刚离开地面仍允许起跳的宽限；填 0 关闭，变成严格判定。
@export_range(0.0, 0.5, 0.01) var coyote_time: float = 0.1
## 跳跃缓冲（秒）：落地前按下的空格会被记住，落地瞬间补发；填 0 关闭。
@export_range(0.0, 0.5, 0.01) var jump_buffer_time: float = 0.1

var _coyote_left: float = 0.0        # 土狼时间剩余量
var _jump_buffer_left: float = 0.0   # 跳跃缓冲剩余量


func _ready() -> void:
	# 没在检查器里指定摄像机时兜底，避免按 WASD 没反应。
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()


## 固定用物理帧驱动：改速度和 move_and_slide 必须在同一帧内完成，否则会抖动。
func _physics_process(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = _world_direction(input)
	_update_jump_timers(delta)
	_try_jump()
	_apply_gravity(delta)
	_apply_horizontal(delta, direction)
	# 这里故意不按移动方向转身。摄像机是主人公的子节点，转身体会带着摄像机一起转，
	# 下一帧"前方"就被重新定义，形成正反馈——角色会原地疯狂打转。第一人称下身体只跟视线转。
	# 实际位移与碰撞解算全部交给物理引擎
	move_and_slide()


## 把 WASD 输入转成世界坐标下的单位方向：以摄像机的水平朝向为"前"。
## 摄像机缺失或正好垂直俯视时退回世界坐标轴，保证任何时候都能走。
func _world_direction(input: Vector2) -> Vector3:
	if input.is_zero_approx():
		return Vector3.ZERO
	var forward: Vector3 = Vector3.FORWARD
	if is_instance_valid(camera):
		forward = -camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
	forward = forward.normalized()
	# 右手系下：右 = 前 × 上
	var right: Vector3 = forward.cross(Vector3.UP)
	# input.y 往前是 -1，所以这里是减去
	return (right * input.x - forward * input.y).normalized()


## 两个跳跃计时器：土狼时间（离地后的宽限）与跳跃缓冲（提前按下的按键）。
func _update_jump_timers(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)


## 起跳：用抛体公式反推初速，保证最高点正好是 jump_height。
## 只有"脚踩地面或还在土狼时间内"且"缓冲里有待处理的按键"才生效，空中不会有第二段跳。
func _try_jump() -> void:
	if _jump_buffer_left <= 0.0:
		return
	if not is_on_floor() and _coyote_left <= 0.0:
		return
	velocity.y = sqrt(2.0 * gravity * jump_height)
	_jump_buffer_left = 0.0
	_coyote_left = 0.0


## 重力只在离地时累加；贴地时不碰竖直速度，起跳那一帧的速度才不会被自己抹掉。
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


## 水平速度按"耗时"逼近目标速度，而不是瞬间赋值，启停才有重量感。
## 三档速率：起步、刹车、变向各管一种情况，互不干扰——把起步调柔和不会连带把转身调黏。
## 空中没有输入时完全不施力，水平速度原样保留——这是抛体运动该有的惯性。
func _apply_horizontal(delta: float, direction: Vector3) -> void:
	var moving: bool = not direction.is_zero_approx()
	if not is_on_floor():
		if not moving:
			return
		_approach_velocity(Vector2(direction.x, direction.z) * move_speed, move_speed / air_time, delta)
		return
	if not moving:
		_approach_velocity(Vector2.ZERO, move_speed / stop_time, delta)
		return
	var horizontal := Vector2(velocity.x, velocity.z)
	var target := Vector2(direction.x, direction.z) * move_speed
	var rate: float = move_speed / start_time
	# 已有速度且与目标方向相反或垂直（点积 <= 0）时算变向：要抹掉的速度差可能接近两倍全速，
	# 用起步档会拖泥带水，所以单独走变向档。静止起步不走这里，否则"重量感"就没了。
	if horizontal.length() >= 0.05 and horizontal.dot(target) <= 0.0:
		rate = move_speed / turn_time
	_approach_velocity(target, rate, delta)


## 把水平速度朝目标推进，单帧变化量不超过 rate * delta（等价于恒定加速度）。
func _approach_velocity(target: Vector2, rate: float, delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
