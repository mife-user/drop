extends WorldEnvironment

## 让环境光与背景色跟随太阳高度一起变化，配合 scripts/sun.gd 的完整昼夜循环。
## 挂在 WorldEnvironment 上，把场景里那个挂了 scripts/sun.gd 的平行光拖到 sun 属性里即可。
##
## 配色同样分「夜晚 / 晚霞 / 白天」三套，和 sun.gd 用同一套高度映射：
##   高度 0（太阳在正下方）= 夜晚   0.5（地平线）= 晚霞   1（正上方）= 白天
##
## 注意：Environment 上的静态设置（Background Mode = Color、Ambient Light Source = Color）
## 写在 scenes/main.tscn 里而不是脚本里，方便直接在检查器里看到和修改。

## 提供高度的太阳（挂 scripts/sun.gd 的那个平行光）
@export var sun: SunLight

## 夜晚的环境光颜色（冷蓝，保证黑夜里还看得清轮廓）
@export var night_ambient_color: Color = Color(0.16, 0.22, 0.42)
## 夜晚的环境光强度：设成 0 则夜里只剩直射光，会非常黑
@export_range(0.0, 4.0, 0.01) var night_ambient_energy: float = 0.18
## 夜晚的背景色（夜空）
@export var night_background_color: Color = Color(0.02, 0.03, 0.08)

## 晚霞时的环境光颜色（偏暖）
@export var dusk_ambient_color: Color = Color(0.38, 0.26, 0.24)
## 晚霞时的环境光强度
@export_range(0.0, 4.0, 0.01) var dusk_ambient_energy: float = 0.55
## 晚霞时的背景色
@export var dusk_background_color: Color = Color(0.88, 0.4, 0.24)

## 白天的环境光颜色（从四面八方均匀照来的底色）
@export var day_ambient_color: Color = Color(0.32, 0.34, 0.38)
## 白天的环境光强度
@export_range(0.0, 4.0, 0.01) var day_ambient_energy: float = 1.0
## 白天的背景色（暂代天空的纯色；以后换成 Sky 时这项就用不上了）
@export var day_background_color: Color = Color(0.45, 0.62, 0.85)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sync()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_sync()


## 按太阳高度把三套配色插值成当前该有的样子。
func _sync() -> void:
	if environment == null or not is_instance_valid(sun):
		return
	var h: float = clampf(sun.height, 0.0, 1.0)
	# smoothstep 两端导数为 0，两段在 h = 0.5（地平线）处能平滑接上
	var to_dusk: float = smoothstep(0.0, 0.5, h)   # 0 = 夜晚，1 = 晚霞
	var to_day: float = smoothstep(0.5, 1.0, h)    # 0 = 晚霞，1 = 白天
	environment.ambient_light_color = night_ambient_color.lerp(dusk_ambient_color, to_dusk).lerp(day_ambient_color, to_day)
	environment.ambient_light_energy = lerpf(lerpf(night_ambient_energy, dusk_ambient_energy, to_dusk), day_ambient_energy, to_day)
	environment.background_color = night_background_color.lerp(dusk_background_color, to_dusk).lerp(day_background_color, to_day)
