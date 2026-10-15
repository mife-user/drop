extends Node3D
class_name WaterGun

## 水枪：按住鼠标左键连续喷水。
##
## 这里只管「什么时候、从哪儿、朝哪个方向吐出一团水」，水一出膛就归 WaterBlob 管：
## 抛出去之后只受重力走抛物线，撞到墙就散掉、落到地上才停。
## 初速、重力、水长什么样，全部由「水块容器」决定 —— 换水模型或调弧线弯不弯只改那边。
##
## **出膛方向不是照抄视线。** aim_zero_distance 决定水在第几米处穿过准星中心：
##   0  = 不归零，纯自由抛物线，水明显落在准星下方，玩家得自己抬头补提前量；
##   >0 = 从枪口反解一个仰角，让水正好从「准星线上第 N 米那个点」穿过去。
## 抬多少度是按「水块容器」当前的初速和重力现算的，所以在那边改初速/重力、
## 或者在水枪升级台把出水速度买上去，这里都不用重调。
##
## 鼠标没被锁定（按过 Esc）时不喷水，免得玩家在解锁状态下点画面重新锁定鼠标时顺手滋出一发。


## 开火用的输入动作名；项目设置里没有这个名字时自动退回「鼠标左键」。
const FIRE_ACTION: StringName = &"fire"

## 水块容器：水团的出生由它负责。拖场景里那个挂 WaterField 的节点过来。
@export var field: WaterField
## 出膛点（枪口）。留空时退回「摄像机前方 muzzle_offset 米」，所以没摆 Marker 也能先玩。
@export var muzzle: Node3D
## 没有配置 muzzle 时，水团从摄像机前方多少米处出生。
@export_range(0.05, 3.0, 0.05) var muzzle_offset: float = 0.6
## 用哪台摄像机的朝向瞄准；留空时自动取当前摄像机。
@export var camera: Camera3D
## 归零距离（米）：水飞到这条距离上时正好压在准星中心。**调手感主要就动这一个。**
##
## 0 = 关掉归零，退回纯自由抛物线（枪口照着视线方向平抛），水会明显落在准星下方。
## 大于 0 时出膛方向改为反解：从枪口指向「准星线上第 N 米那个点」，并额外抬一个角度
## 把这一段的重力下坠补掉。**枪口 Marker 摆得准不准、水枪模型朝向对不对，都不影响结果** ——
## 解的是「枪口 → 那个点」，Marker 挪个位置水照样从准星中心穿过去。
##
## 怎么调：填得越大，弧线越拱、归零点越远，近处越容易从准星上方飞过去；
## 填得越小，弧线越平、越贴近直射。填小了打不着远处，填大了打不准近处。
## 主场景里水池在 8 米左右、木碗在 12 米开外，可以先把 8 当起点来回试。
## 另外注意初速 15 m/s 时水在 12 米外已经掉下去 3 米 —— 想让远近都服帖，
## 与其把归零距离往大调，不如顺手把「水块容器」的 muzzle_speed 提上去。
@export_range(0.0, 60.0, 0.5) var aim_zero_distance: float = 8.0
## 每发之间的间隔（秒）；越小喷得越密。
@export_range(0.02, 2.0, 0.01) var fire_interval: float = 0.12
## 射出时水团的边长（米）。全项目只有这一处定义「一发的初始大小」。
## 水量按边长的立方（立方米）算，所以**把它调大 —— 或者以后做升级系统在运行时抬高它 ——
## 每发灌进水池的水量会真的变多，填满同样容积需要的发数会自动变少**。
@export_range(0.05, 2.0, 0.01) var blob_size: float = 0.35
## 能不能开火。交互菜单打开时由交互台临时关掉 —— 菜单里左键是「确认」，
## 不关掉的话玩家按左键会顺手滋出一发水。平时保持勾选；取消勾选 = 这把枪彻底不喷水。
@export var can_fire: bool = true

var _cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0 or not _is_firing():
		return
	_cooldown = fire_interval
	_fire()


## 按住开火键、鼠标处于锁定状态、且没被临时关掉，才算开火。
func _is_firing() -> bool:
	if not can_fire:
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if InputMap.has_action(FIRE_ACTION):
		return Input.is_action_pressed(FIRE_ACTION)
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## 从枪口抛出一团水，方向由 _launch_direction() 按归零距离算。
## 这里不打射线也不管落点：水出膛后就归重力管，撞到什么由 WaterBlob 自己一帧一帧查。
func _fire() -> void:
	if not is_instance_valid(field):
		push_error("水枪：field 未指定，射不出水")
		return
	var cam: Camera3D = _camera()
	if cam == null:
		return
	var from: Vector3 = _muzzle_position(cam)
	field.spawn_flying(from, _launch_direction(cam, from), blob_size)


## 算出这一发的出膛方向（单位向量）。
## aim_zero_distance 填 0 时就是视线本身 —— 以前那套纯自由抛物线，水落在准星下方。
func _launch_direction(cam: Camera3D, from: Vector3) -> Vector3:
	var sight: Vector3 = -cam.global_basis.z
	if aim_zero_distance <= 0.0:
		return sight
	# 靶点是「准星线上第 N 米」那个点 —— 它一定投影在屏幕正中心，所以水会从准星中间穿过去
	var target: Vector3 = cam.global_position + sight * aim_zero_distance
	return _ballistic_direction(from, target, field.muzzle_speed, field.gravity)


## 反解抛体：以 speed 的初速、在 gravity 下从 from 抛出，要正好经过 target，出膛方向该朝哪。
##
## 水平面上走直线，竖直面上解课本里的抛体方程。目标比枪口低时它有两个解（低伸 / 高抛），
## 这里取仰角小的那个 —— 高抛那条会拱到树冠和屋檐上去。
## 判别式小于 0 表示这个初速压根够不着那么远，退到极限角 v²/(g·d)：
## 那是「在这个水平距离上最高能擦到哪」的角度，落点离目标最近。
func _ballistic_direction(from: Vector3, target: Vector3, speed: float, gravity: float) -> Vector3:
	var flat: Vector3 = Vector3(target.x - from.x, 0.0, target.z - from.z)
	var d: float = flat.length()
	var h: float = target.y - from.y
	# 靶点几乎就在枪口正上/正下方（比如低头看脚）：没有水平距离，抛体方程退化，直接指着打
	if d < 0.05 or speed <= 0.0 or gravity <= 0.0:
		return (target - from).normalized()
	var v2: float = speed * speed
	var disc: float = v2 * v2 - gravity * (gravity * d * d + 2.0 * h * v2)
	var tan_pitch: float = v2 / (gravity * d) if disc < 0.0 else (v2 - sqrt(disc)) / (gravity * d)
	var pitch: float = atan(tan_pitch)
	var horizontal: Vector3 = flat / d
	return horizontal * cos(pitch) + Vector3.UP * sin(pitch)


## 摄像机可能比水枪晚进场景树，没找到就每帧重试一次。
func _camera() -> Camera3D:
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	return camera


## 有枪口 Marker 就用它，没有就退到摄像机前方，保证不摆 Marker 也能先玩起来。
func _muzzle_position(cam: Camera3D) -> Vector3:
	if is_instance_valid(muzzle):
		return muzzle.global_position
	return cam.global_position - cam.global_basis.z * muzzle_offset
