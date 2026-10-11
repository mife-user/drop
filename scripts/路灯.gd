extends Node3D

## 路灯：让灯下所有 Light3D 只在夜晚亮起，天亮了就整个关掉。
##
## 亮灭由「太阳高度」驱动 —— 读的是 scripts/sun.gd 里的公共变量 SunLight.height
## （0 = 深夜，0.5 = 地平线，1 = 正午），和 scripts/day_night.gd 是同一套映射，
## 所以路灯、环境光、天色三者天然同步，不会出现「天还没黑灯就亮了」。
##
## 太阳是按分组找的：scripts/sun.gd 在 _ready 里把自己加进了「太阳」组，
## 15 盏路灯都不用在检查器里连 NodePath。
##
## 各光源的亮度基准 = 你在检查器里给该光源设的 light_energy，
## 脚本只是按夜晚系数去缩放它，也就是「检查器里的值 = 全黑时该有的亮度」。
## 想让某个灯更亮，去改那个光源自己的 light_energy 就行，不用动这里。

## 太阳降到这个高度以下，路灯开始亮（0.5 = 地平线，1 = 正午）
@export_range(0.0, 1.0, 0.01) var dusk_height: float = 0.58
## 太阳降到这个高度，路灯完全亮起。和上一项拉开距离就是黄昏/黎明的渐亮渐灭时长
@export_range(0.0, 1.0, 0.01) var night_height: float = 0.44
## 整体亮度倍率：1.0 = 完全按各光源自己的 light_energy 来，2.0 = 全部加倍
@export_range(0.0, 4.0, 0.01) var brightness: float = 1.0
## 取消勾选后脚本不再管光源，方便把时间停在白天单独调灯
@export var auto_control: bool = true

## 夜晚系数小于这个值就当作「天亮了」，直接把光源关掉，不再每帧算能量
const _DAY_EPSILON: float = 0.001

## 本路灯下所有参与自动开关的光源，_ready 时收集一次
var _lights: Array[Light3D] = []
## 与 _lights 一一对应，存各光源在检查器里设的 light_energy 作为亮度基准
var _base_energy: PackedFloat32Array = PackedFloat32Array()
## 提供太阳高度的平行光，按「太阳」分组查找
var _sun: SunLight


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 把灯下所有 Light3D（现为 2 个 OmniLight3D + 2 个 SpotLight3D）都收进来；
	# 以后往路灯下再加光源会自动被接管，不用回来改脚本。
	for node in find_children("*", "Light3D", true, false):
		var light: Light3D = node as Light3D
		_lights.append(light)
		_base_energy.append(light.light_energy)
	# 太阳通常已经进树了，先取一次，让第一帧就是正确的亮灭状态
	_sun = get_tree().get_first_node_in_group(SunLight.GROUP_NAME) as SunLight
	_sync()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# 太阳可能比路灯晚进场景树，没找到就每帧重试，找到之后这里只剩一次很轻的有效性检查
	if not is_instance_valid(_sun):
		_sun = get_tree().get_first_node_in_group(SunLight.GROUP_NAME) as SunLight
		if _sun == null:
			return
	_sync()


## 按太阳高度算出夜晚系数（0 = 白天，1 = 全黑），再同步到本路灯的所有光源。
func _sync() -> void:
	if not auto_control or _sun == null:
		return
	# smoothstep 两端导数为 0，黄昏时灯是渐渐亮起来的，不会「啪」地一下全开
	var night: float = 1.0 - smoothstep(night_height, dusk_height, _sun.height)
	# 白天把 visible 关掉：不可见的光源会从渲染列表里整个拿掉，比只把能量设成 0 更省
	var on: bool = night > _DAY_EPSILON
	for i in _lights.size():
		var light: Light3D = _lights[i]
		light.visible = on
		if on:
			light.light_energy = _base_energy[i] * night * brightness
