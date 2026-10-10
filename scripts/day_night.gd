extends WorldEnvironment

## 让环境光与背景色跟随太阳的「白天程度」一起变化，配合只有白天和晚霞的昼夜循环。
## 挂在 WorldEnvironment 上，把场景里那个挂了 scripts/sun.gd 的平行光拖到 sun 属性里即可。
##
## 注意：Environment 上的静态设置（Background Mode = Color、Ambient Light Source = Color）
## 写在 scenes/main.tscn 里而不是脚本里，方便直接在检查器里看到和修改。

## 提供白天程度的太阳（挂 scripts/sun.gd 的那个平行光）
@export var sun: SunLight
## 正午时的环境光强度
@export_range(0.0, 4.0, 0.01) var day_ambient_energy: float = 1.0
## 晚霞时的环境光强度：别设成 0，否则晚霞段会暗到看不清
@export_range(0.0, 4.0, 0.01) var dusk_ambient_energy: float = 0.6
## 正午时的环境光颜色（从四面八方均匀照来的底色）
@export var day_ambient_color: Color = Color(0.3, 0.3, 0.3)
## 晚霞时的环境光颜色（偏暖）
@export var dusk_ambient_color: Color = Color(0.34, 0.24, 0.2)
## 正午时的背景色（暂代天空的纯色；以后换成 Sky 时这项就用不上了）
@export var day_background_color: Color = Color(0.45, 0.62, 0.85)
## 晚霞时的背景色
@export var dusk_background_color: Color = Color(0.85, 0.42, 0.28)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sync()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_sync()


## 按太阳的白天程度把环境光与背景色插值到当前该有的样子。
func _sync() -> void:
	if environment == null or not is_instance_valid(sun):
		return
	var daylight: float = clampf(sun.daylight, 0.0, 1.0)
	environment.ambient_light_color = dusk_ambient_color.lerp(day_ambient_color, daylight)
	environment.ambient_light_energy = lerpf(dusk_ambient_energy, day_ambient_energy, daylight)
	environment.background_color = dusk_background_color.lerp(day_background_color, daylight)
