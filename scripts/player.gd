extends CharacterBody3D
class_name Player

## 主人公移动控制：WASD 相对视线前后左右移动，空格跳跃，鼠标控制第一人称视角。
## 碰撞、阻挡、贴地交给物理引擎（move_and_slide），水平速度和重力由本脚本按物理公式计算，
## 所以起跳是标准抛体运动——初速 v = sqrt(2 * 重力 * 跳跃高度)，空中松手会保持水平惯性。
## 地面水平速度按"起步 / 刹车 / 变向"三档时间参数平滑过渡，不会瞬间启停。
## 所有手感数值都是 @export，可直接在检查器里调，不用改代码。
##
## 另外对外提供两个「临时锁」给交互菜单用（见 交互台.gd）：
## set_move_lock() 不许走也不许跳，lock_look() / unlock_look() 把视角限制在一个锥形里。
## 锁的是"玩家能不能动"，不是"脚本跑不跑"，所以重力、贴地照常工作。


## 第一人称摄像机（挂在主人公眼睛位置上的子节点），W 表示朝视线前方走。
## 留空时会自动取当前场景的摄像机。
@export var camera: Camera3D
## 鼠标灵敏度（弧度/像素）；越大转得越快，转一整圈约需 2π / 该值 像素。
@export_range(0.0002, 0.02, 0.0002) var mouse_sensitivity: float = 0.002
## 上下视角限位（度），防止翻过头顶；也给"朝视线水平方向走"的计算留出余量。
@export_range(30.0, 89.5, 0.5) var pitch_limit: float = 89.0
## 进入场景时是否锁定鼠标；锁定后光标隐藏，Esc 释放、点击画面重新锁定。开发时可临时关掉。
@export var capture_on_start: bool = true
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
var _pitch: float = 0.0              # 摄像机的俯仰角（弧度），负值表示低头
var _move_locked: bool = false       # 临时锁：不许走也不许跳（交互菜单开着时为 true）
var _look_locked: bool = false       # 临时锁：视角被限制在一个锥形里
var _lock_yaw: float = 0.0           # 视线锁的中心偏航角（弧度）
var _lock_pitch: float = 0.0         # 视线锁的中心俯仰角（弧度）
var _lock_range: float = 0.0         # 允许偏离中心多少（弧度）


func _ready() -> void:
	# 没在检查器里指定摄像机时兜底，避免按 WASD 没反应。
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	# 沿用你在编辑器里摆好的初始俯仰角（略微低头），不重置朝向
	if is_instance_valid(camera):
		_pitch = camera.rotation.x
	if capture_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 锁住走动和跳跃（松开后立刻恢复，速度按原本的刹车曲线平滑停下）。
## 视角不受影响 —— 那是 lock_look() 的事。
func set_move_lock(locked: bool) -> void:
	_move_locked = locked
	if locked:
		_jump_buffer_left = 0.0


## 把视角锁在一个朝 direction 的锥形里：只能在那个方向附近 ±range_degrees 度内转。
## direction 传全局方向（比如"摄像机 → 菜单面板"），会自动换算成偏航角和俯仰角。
func lock_look(direction: Vector3, range_degrees: float) -> void:
	var dir: Vector3 = direction.normalized()
	if dir.is_zero_approx():
		return
	# 视线对准 dir 时，偏航角是 atan2(-x, -z)（推导：人物转 θ 后，视线方向的水平分量
	# 正比于 (-sinθ, -cosθ)），俯仰角就是 dir 的仰角（正数 = 抬头）。
	_lock_yaw = atan2(-dir.x, -dir.z)
	# **再减掉摄像机相对人物自己的偏航**。摄像机虽然是人物的子节点，但不是"朝人物的 -Z 看"：
	# 项目里为了跟人物正面（+Z）对齐，它在场景里被转了 180°。不减这个偏移的话，
	# 锁出来的方向整整差 180° —— 表现就是按 E 之后视角被甩到菜单的反面去。
	# 偏移直接读摄像机自己的 rotation.y，不写死 180°，以后谁改了摄像机朝向也不会再错。
	if is_instance_valid(camera):
		_lock_yaw -= camera.rotation.y
	_lock_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_lock_range = deg_to_rad(maxf(range_degrees, 0.0))
	_look_locked = true


## 解开视角锁。
func unlock_look() -> void:
	_look_locked = false


## 固定用物理帧驱动：改速度和 move_and_slide 必须在同一帧内完成，否则会抖动。
func _physics_process(delta: float) -> void:
	# 菜单开着时按"没输入"处理：不是不跑物理（重力、贴地照常），而是玩家推不动他
	var input: Vector2 = Vector2.ZERO
	if not _move_locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = _world_direction(input)
	_update_jump_timers(delta)
	_try_jump()
	_apply_gravity(delta)
	_apply_horizontal(delta, direction)
	# 这里故意不按移动方向转身。摄像机是主人公的子节点，转身体会带着摄像机一起转，
	# 下一帧"前方"就被重新定义，形成正反馈——角色会原地疯狂打转。第一人称下身体只跟视线转。
	# 实际位移与碰撞解算全部交给物理引擎
	move_and_slide()


## 第一人称视角：鼠标左右转身体（人物、水枪一起转），上下只抬摄像机，不碰碰撞体。
## 放在 _unhandled_input 而不是 _physics_process：鼠标事件一帧可能来 0 次也可能来多次，
## 这里逐事件处理、当帧生效，延迟最低；也不做平滑，鼠标和视角严格 1:1。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# 鼠标右移 = 向右转。人物正面是 +Z（不是 Godot 惯例的 -Z），
		# 所以"右边"是 -X 方向，右转对应 rotation.y 减小；写成 += 会左右颠倒。
		rotation.y -= motion.relative.x * mouse_sensitivity
		# 鼠标下移 = 低头。摄像机局部 rotation.x 为正时视线朝上，所以这里同样是减。
		var limit: float = deg_to_rad(pitch_limit)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
		if _look_locked:
			# 视角锁：只允许在以锁定方向为中心的锥形里转。
			# 用 wrapf 取最短角差，这样绕着圈转身也不会在 ±180° 处翻掉。
			rotation.y = _lock_yaw + clampf(wrapf(rotation.y - _lock_yaw, -PI, PI), -_lock_range, _lock_range)
			_pitch = clampf(_pitch, _lock_pitch - _lock_range, _lock_pitch + _lock_range)
		if is_instance_valid(camera):
			camera.rotation.x = _pitch
		return
	# Esc 释放光标（不暂停游戏），点击画面重新锁定
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
## 被锁住时不再接受新的跳跃输入（已经在缓冲里的那一下由 set_move_lock 清掉）。
func _update_jump_timers(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and not _move_locked:
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
