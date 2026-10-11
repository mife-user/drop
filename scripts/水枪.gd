extends Node3D
class_name WaterGun

## 水枪：按住鼠标左键朝视线方向连续喷水。
##
## 这里只管「什么时候、从哪儿、朝哪个方向吐出一团水」，水一出膛就归 WaterBlob 管：
## 沿视线抛出去之后只受重力走抛物线，撞到墙就散掉、落到地上才停。
## 初速、重力、水长什么样，全部由「水块容器」决定 —— 换水模型或调弹道只改那边，这个脚本不用动。
##
## 注意：因为是自由抛物线，水会明显落在准星下方，玩家得自己抬头补提前量。
## 想让准星重新变准，得改成「射线定落点 + 反解发射角」，那是另一套做法。
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
## 每发之间的间隔（秒）；越小喷得越密。
@export_range(0.02, 2.0, 0.01) var fire_interval: float = 0.12
## 射出时水团的边长（米）。全项目只有这一处定义「一发的初始大小」。
## 水量按边长的立方（立方米）算，所以**把它调大 —— 或者以后做升级系统在运行时抬高它 ——
## 每发灌进水池的水量会真的变多，填满同样容积需要的发数会自动变少**。
@export_range(0.05, 2.0, 0.01) var blob_size: float = 0.35

var _cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0 or not _is_firing():
		return
	_cooldown = fire_interval
	_fire()


## 按住开火键且鼠标处于锁定状态才算开火。
func _is_firing() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if InputMap.has_action(FIRE_ACTION):
		return Input.is_action_pressed(FIRE_ACTION)
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## 朝视线方向、以水块容器设定的初速抛出一团水。
## 这里不打射线也不管落点：水出膛后就归重力管，撞到什么由 WaterBlob 自己一帧一帧查。
func _fire() -> void:
	if not is_instance_valid(field):
		push_error("水枪：field 未指定，射不出水")
		return
	var cam: Camera3D = _camera()
	if cam == null:
		return
	field.spawn_flying(_muzzle_position(cam), -cam.global_basis.z, blob_size)


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
