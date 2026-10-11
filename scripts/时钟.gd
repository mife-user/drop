extends Node3D

## 时钟：把表盘上的时针 / 分针拨到当前游戏时间，和 scripts/sun.gd 的太阳完全同步。
##
## 时间只有一个来源 —— 太阳。本脚本故意不提供「初始时间」「一天的时长」这类参数，
## 否则钟和昼夜迟早会对不上：
##   想改开局是几点 → 改 DirectionalLight3D 的 start_angle_deg（0° = 6:00，每 15° 一小时）
##   想改一天多长   → 改同一个节点的 angular_speed（度/秒）
## 钟会自动跟上。太阳按分组「太阳」查找，和 scripts/路灯.gd 是同一套写法，
## 所以摆几个钟都不用连 NodePath。
##
## 关于速度：一天 31 秒时（angular_speed = 11.6129），时针 15.5 秒转一圈、分针 1.3 秒转一圈。
## 分针转得飞快是「31 秒过完一天」的忠实结果，不是 bug —— 想让它慢下来，只能把一天拉长。

## 时针节点（已经是 时钟/时针，换了模型才需要重拖）
@export var hour_hand: Node3D
## 分针节点（已经是 时钟/分针，换了模型才需要重拖）
@export var minute_hand: Node3D

## 指针指向 12 点整时，该指针还要绕自身 Z 轴转多少度。
## 两个模型的出厂朝向不一样：时针是沿 -X 横躺的（要补 -90 才能立起来），分针出厂就竖直朝上（补 0）。
## 以后换新的指针模型，如果指歪了就调这两个数，不用改代码。
@export var hour_rest_offset_deg: float = -90.0
## 同上，分针的静止朝向修正
@export var minute_rest_offset_deg: float = 0.0

## 取消勾选后脚本不再管指针，方便把指针停在某个位置单独看
@export var auto_control: bool = true

## 提供时间的太阳，按「太阳」分组查找
var _sun: SunLight


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 太阳通常已经进树了，先取一次，让第一帧就指对时间
	_sun = get_tree().get_first_node_in_group(SunLight.GROUP_NAME) as SunLight
	_sync()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# 太阳可能比时钟晚进场景树，没找到就每帧重试，找到之后这里只剩一次很轻的有效性检查
	if not is_instance_valid(_sun):
		_sun = get_tree().get_first_node_in_group(SunLight.GROUP_NAME) as SunLight
		if _sun == null:
			return
	_sync()


## 按太阳给出的时刻拨指针。表盘是 12 小时的，所以时针 12 小时转一圈、分针 1 小时转一圈。
func _sync() -> void:
	if not auto_control or _sun == null:
		return
	# 折进 12 小时制：0 点和 12 点、24 点和 12 点都指同一处
	var hour12: float = fmod(_sun.time_of_day, 12.0)
	# 表针顺时针走，而绕 +Z 轴正向旋转在表盘正面看是逆时针，所以取负号
	if is_instance_valid(hour_hand):
		hour_hand.rotation.z = deg_to_rad(hour_rest_offset_deg) - TAU * hour12 / 12.0
	if is_instance_valid(minute_hand):
		# fmod 取一小时以内的零头 = 分钟数，60 分钟正好走满一圈
		minute_hand.rotation.z = deg_to_rad(minute_rest_offset_deg) - TAU * fmod(hour12, 1.0)
