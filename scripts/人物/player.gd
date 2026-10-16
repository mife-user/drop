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
##
## 它还顺手管着人物模型的动画（`人物.tscn` 里那个 AnimationPlayer），两个状态：站立 / 走。
## 动画是**照着移动结果放的**，一点玩法都不影响 —— 反过来说，把 `anim` 留空整套动画逻辑就不工作，
## 移动照常。判定用的全是本脚本自己已经算好的东西（velocity、is_on_floor），没有新数值。


## 玩家组名。交互台没在检查器里显式指定主人公时，就按这个组把玩家捞出来 ——
## 名字要和 scripts/交互框/交互台.gd 里的 GROUP_PLAYER 一致。
const GROUP: StringName = &"player"

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

@export_group("动画")

## 人物模型上的动画播放器（`scenes/人物.tscn` 里的 AnimationPlayer）。
## **留空 = 整套动画逻辑不工作，移动照常**，要临时关掉动画排查问题时把它清空即可。
@export var anim: AnimationPlayer
## 站着不动时播的动画。**库名前缀「人物/」不能省** —— 库里叫「站立」，代码里认的名字是「库名/动画名」。
## 这两条填错不会崩，只会在输出里报一句「动画库里没有…」，照着改就行。
@export var idle_anim: StringName = &"人物/站立"
## 在地面上有速度时播的动画（循环）。它只动两条腿和另一侧那只自由手，**不碰端水枪的手臂**，
## 所以和「手臂俯仰」不打架，可以放心混着用。
@export var walk_anim: StringName = &"人物/走"
## 走路动画是按「每秒几米」做出来的。填成 move_speed 表示：全速走时动画原速播。
## 填大了动画偏慢（看着像滑步），填小了动画偏快（看着像原地蹬腿）。
@export_range(0.1, 20.0, 0.1) var walk_ref_speed: float = 4.0
## 走路动画的最慢倍率：速度掉到很低时，动画至少按这个倍率播，免得慢得像卡住。
@export_range(0.05, 1.0, 0.05) var min_walk_scale: float = 0.4
## 速度低于这个值（米/秒）就算「站住」，切回站立动画。
## 留一点余量是为了贴着墙蹭、走下缓坡时不会在走/站之间来回抖。
@export_range(0.01, 1.0, 0.01) var move_threshold: float = 0.15
## 站立 ↔ 走 的交叉淡入时间（秒）；填 0 = 硬切。
@export_range(0.0, 1.0, 0.01) var fade_time: float = 0.2

# **这里没有「跳」动画是故意的，不是漏写**（2026-10-16 去掉的）。
# `resources/人物/跳.res` 和 `resources/人物/jump.fbx` 都还在磁盘上，只是没挂进 `人物.tscn` 的动画库。
# 当时卡住的两点：① 那条动画的根骨骼带着一条位移轨道，而摄像机和骨架是两棵独立的分支，
# 跳起来模型会连带水枪相对镜头上下晃；② 它长 0.958 秒，对不上 0.633 秒的滞空时间。
# 要加回来的话：在编辑器里给 AnimationPlayer 添一条库条目，再在这里补一个 jump_anim 和对应分支。

var _coyote_left: float = 0.0        # 土狼时间剩余量
var _jump_buffer_left: float = 0.0   # 跳跃缓冲剩余量
var _current_anim: StringName = &""  # 正在播的动画名；用来避免每帧重复 play()（play 会把动画从头重放）
var _pitch: float = 0.0              # 摄像机的俯仰角（弧度），负值表示低头
var _move_locked: bool = false       # 临时锁：不许走也不许跳（交互菜单开着时为 true）
var _look_locked: bool = false       # 临时锁：视角被限制在一个锥形里
var _lock_yaw: float = 0.0           # 视线锁的中心偏航角（弧度）
var _lock_pitch: float = 0.0         # 视线锁的中心俯仰角（弧度）
var _lock_range: float = 0.0         # 允许偏离中心多少（弧度）


## 登记进「玩家」组。放在 _enter_tree 而不是 _ready：所有节点的 _enter_tree 都跑完了
## 才会有第一个 _ready，所以交互台在自己的 _ready 里一定捞得到玩家。
func _enter_tree() -> void:
	add_to_group(GROUP)


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
	# 放在 move_and_slide() 之后：这才是本帧最终的 is_on_floor() 和 velocity，动画照它切
	_update_animation()


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


## 两个状态之间切换：走 / 站。
## **空中什么都不做**（`not is_on_floor()` 直接返回），所以跳起来之后会一直保持起跳前那一条动画，
## 落地再按当时还剩多少水平速度回到「走」或「站」。现在没有跳动画，这正是想要的效果。
func _update_animation() -> void:
	if not is_instance_valid(anim):
		return
	if not is_on_floor():
		return
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed < move_threshold:
		_play_anim(idle_anim, fade_time)
		return
	# 走的倍率跟着实际速度走，加减速、以后改 move_speed 都不会"滑步"。
	# 只卡下限不卡上限：真跑得比基准快时，动画就该放得比原速快，那才对得上脚。
	var scale: float = maxf(speed / maxf(walk_ref_speed, 0.01), min_walk_scale)
	_play_anim(walk_anim, fade_time, scale)


## 切动画，顺带把播放倍率设好。
## **已经在播这一条就什么都不做** —— play() 会把动画从头重放，走路这种循环每帧调一次会变成一帧一卡。
func _play_anim(clip: StringName, fade: float, scale: float = 1.0) -> void:
	if not is_instance_valid(anim) or clip == &"":
		return
	anim.speed_scale = scale
	if clip == _current_anim:
		return
	_current_anim = clip     # 先记下来：名字填错时下面会报警告，这样不会每帧刷屏
	if not anim.has_animation(clip):
		# **这里故意只警告、不 return**：万一 has_animation() 对「库名/动画名」这种写法不认，
		# 动画也照样能播（play() 是认的），顶多多一句警告，不至于整套动画一声不吭地哑掉。
		push_warning("player.gd：动画库里没有「%s」，检查检查器里的 站立/走 两个名字（库名前缀「人物/」不能省）" % clip)
	anim.play(clip, fade)
