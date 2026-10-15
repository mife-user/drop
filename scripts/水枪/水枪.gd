extends Node3D
class_name WaterGun

## 水枪：按住鼠标左键连续喷水，水箱按发扣水，打空了就滋不出水。
##
## 这里只管「什么时候、从哪儿、朝哪个方向吐出一团水」，水一出膛就归 WaterBlob 管：
## 抛出去之后只受重力走抛物线，撞到墙就散掉、落到地上才停。
## 初速、重力、水长什么样，全部由「水块容器」决定 —— 换水模型或调弧线弯不弯只改那边。
##
## **水箱为什么在这儿**：因为「一发水多大」和「一发水耗多少水」必须是同一个数。
## 耗水量直接算成 blob_size³（见 shot_volume()），不另外配一份 ——
## 于是升级台把水块调大之后，射出去的水更大、水箱也掉得更快，两边永远对得上。
## 全项目只有这一个地方扣水、也只有这一个地方被接水（fill()），
## 所以「水枪上方那块读数」只要盯着这一个数就不会和实际打出来的水脱节。
##
## capacity 填 0 = 关掉这套限制，退回「想射多久射多久」的老行为。
##
## **出膛方向不是照抄视线。** aim_zero_distance 决定水在第几米处穿过准星中心：
##   0  = 不归零，纯自由抛物线，水明显落在准星下方，玩家得自己抬头补提前量；
##   >0 = 从枪口反解一个仰角，让水正好从「准星线上第 N 米那个点」穿过去。
## 抬多少度是按「水块容器」当前的初速和重力现算的，所以在那边改初速/重力、
## 或者在水枪升级台把出水速度买上去，这里都不用重调。
##
## 鼠标没被锁定（按过 Esc）时不喷水，免得玩家在解锁状态下点画面重新锁定鼠标时顺手滋出一发。
##
## **炮台（scripts/水枪/炮台发射器.gd）继承本类**：它白拿这里的水箱、发射间隔和抛物线反解，
## 只覆盖「什么时候开火」（`_is_firing`）和「朝哪开火」（`_launch_direction`）两处 ——
## 所以这两个函数是留给子类的口子，改它们要连着想想炮台那边。
## 另外本类现在只要求「有枪口」，**不再要求有摄像机**（炮台没有摄像机），也是为它开的。


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

@export_group("水箱")
## 水箱能装多少水（立方米）。**一发水耗掉的就是这一发水团的体积（blob_size³）**，
## 所以「一箱能射几发」= capacity ÷ blob_size³ —— 按当前 0.17 米的水块算，1.0 立方米约 203 发。
## 怎么调：想让它是个「射一会儿就得回去接水」的资源，填 0.5 ~ 2.0；
## 填 0 = 不限制，退回老行为（想射多久射多久）。觉得这限制不好玩，一个数字就能撤。
@export_range(0.0, 100.0, 0.001) var capacity: float = 1.0

@export_group("读数")
## 水枪上方那块数字（Label3D）。留空 = 不显示读数。
## **位置就在那个节点自己身上**：在 3D 视图里拖它、或改它的 Transform，
## 脚本从头到尾不碰它的位置，所以随便你摆。字体大小改它的 pixel_size。
@export var readout: Label3D
## 读数怎么写。两个占位符依次是「现在有多少」「一共能装多少」，单位是立方米。
## 想改成「还剩 3 发」这类写法，改这一行 + _refresh_readout() 里那两行。
@export var readout_format: String = "%.3f / %.3f m³"
## capacity 填 0（不限制）时读数写什么。
@export var readout_no_limit_text: String = "∞"
## 打空时读数变成的颜色。**有水的颜色不在这儿配** —— 用的是那个 Label3D 在场景里
## 自己设的 modulate，改外观直接去节点上改。
@export var empty_color: Color = Color(1.0, 0.45, 0.42)

## 水箱里现在有多少水（立方米）。开局是满的，之后由开火（扣）和消防栓接水（加）改动。
## **别在外面直接赋值** —— 直接改不会刷新水枪上方那块读数，走 fill() 或开火那两条路。
var amount: float = 0.0

var _cooldown: float = 0.0
var _readout_base_color: Color = Color.WHITE   # 读数节点在场景里本来的颜色，只在打空时临时盖掉


func _ready() -> void:
	amount = capacity   # 满水开局
	if is_instance_valid(readout):
		_readout_base_color = readout.modulate   # 记下节点自己的颜色，打空只是临时盖掉它
	_refresh_readout()


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


## 从枪口抛出一团水，方向由 _launch_direction() 按归零距离算；射出去了才扣水。
## 这里不打射线也不管落点：水出膛后就归重力管，撞到什么由 WaterBlob 自己一帧一帧查。
func _fire() -> void:
	if not is_instance_valid(field):
		push_error("水枪：field 未指定，射不出水")
		return
	if not has_water():
		return   # 水箱空了：不出水也不扣水，读数会变红提醒（见 _refresh_readout）
	var cam: Camera3D = _camera()
	if cam == null and not is_instance_valid(muzzle):
		return   # 枪口和摄像机总得有一样：枪口有填就不需要摄像机（炮台走的就是这条）
	var from: Vector3 = _muzzle_position(cam)
	var blob: WaterBlob = field.spawn_flying(from, _launch_direction(cam, from), blob_size)
	if blob == null:
		return   # 水块容器没配好（没填 blob_scene），射不出来 —— 那就一发的水也不扣
	amount = maxf(amount - shot_volume(), 0.0)
	_refresh_readout()


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


# —— 水箱 ——
# 只对外给这几个函数：读数的口径、消防栓判断"接满了没有"、以后要加音效/飘字，都走它们，
# 别各自去读 amount 再自己算一遍，免得几处口径对不上。


## 一发水要耗掉多少水（立方米）：就是这一发水团的体积 = 边长³。
## 全项目只有 blob_size 定义「一发多大」，所以射出去的水和水箱里扣掉的水**永远是同一个数**；
## 升级台把水块调大之后，每发耗水会跟着变多，不用另外配一份（也没有第二份可配错）。
func shot_volume() -> float:
	return blob_size * blob_size * blob_size


## 水箱里还够不够射一发。capacity 填 0（不限制）时永远够。
func has_water() -> bool:
	return capacity <= 0.0 or amount >= shot_volume() - 0.000001


## 往水箱里加水（立方米），返回**实际加进去多少** —— 加满之后就一滴不收，
## 接水的人靠这个返回值知道"满了没有、停了没有"。
## capacity 填 0（不限制）时永远返回 0：没有"加满"这回事。
func fill(cubic: float) -> float:
	if capacity <= 0.0 or cubic <= 0.0:
		return 0.0
	var before: float = amount
	amount = minf(amount + cubic, capacity)
	var gained: float = amount - before
	if gained > 0.0:
		_refresh_readout()
	return gained


## 改水箱容量（立方米）。**升级台买「水量容量」时调的就是它。**
## 和水箱的另一个入口 fill() 一样：别在外面直接写 capacity —— 那样水枪上方那块读数不会跟着变。
## **只抬高上限、不加水**：想把多出来的容量用上，还得回消防栓接水。
func set_capacity(cubic: float) -> void:
	capacity = maxf(cubic, 0.0)
	if capacity > 0.0:
		amount = minf(amount, capacity)   # 万一把容量改小了，别让箱里的水超过上限
	_refresh_readout()


## 还能装多少（立方米）。
func free_space() -> float:
	return 0.0 if capacity <= 0.0 else maxf(capacity - amount, 0.0)


## 满了吗。capacity 填 0 时永远算满 —— 否则消防栓会一直显示「接水中」。
func is_full() -> bool:
	return capacity <= 0.0 or amount >= capacity - 0.000001


## 装了几成（0 ~ 1）。capacity 填 0 时返回 1。
func fill_ratio() -> float:
	return 1.0 if capacity <= 0.0 else clampf(amount / capacity, 0.0, 1.0)


## 按当前水量重写水枪上方那块数字。
## 正常颜色取的是那个 Label3D 在场景里自己配的色（所以改外观去节点上改，这儿不存第二份），
## 只有「打空了」这一种情况才临时盖成 empty_color。
func _refresh_readout() -> void:
	if not is_instance_valid(readout):
		return
	if capacity <= 0.0:
		readout.text = readout_no_limit_text
		readout.modulate = _readout_base_color
		return
	readout.text = readout_format % [amount, capacity]
	readout.modulate = _readout_base_color if has_water() else empty_color
