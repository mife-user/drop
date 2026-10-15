extends Control
class_name WorldStatsPanel

## 世界属性面板：按 Tab 从屏幕左上角浮出来，再按一次收回。
##
## **打开时世界照常跑** —— 不暂停、不锁鼠标、也不锁人。它是一块盖在画面上的读数板，不是菜单，
## 所以你可以边走边看，水和太阳都不会因为开着它而停下。
##
## **这里不生产任何数值，只把别处已经有的摆到屏幕上**：
##   水块大小 —— 调水枪的 shot_volume()，显示的是一发水的**体积（m³）**，不是边长。
##               它和水箱每发扣掉的水、吸水区涨的水位是同一个数；
##               升级台「水块大小」那一行改的，就是这个体积的来源（边长 blob_size）。
##   频率     —— 由水枪的 fire_interval 换算：那家伙是「隔几秒一发」，这里显示「每秒几发」
##   时间     —— 读太阳的 time_of_day（和 scripts/时钟.gd 读的是同一个数）
## 所以刚在升级台买完、或者太阳转到了傍晚，这里下一帧就跟着变，中间不需要任何联动代码。
## 以后加新属性也照这个规矩来：**先去源头读，别在这个文件里另存一份**（另存的那份迟早对不上）。
##
## 面板长什么样全在 scenes/界面/世界属性面板.tscn 里：底色、圆角、字号、位置、边框粗细
## 都在检查器里改，这个文件一个尺寸都不写死。
## **「再加一行属性」**：把 scenes/界面/属性行.tscn 再实例一份摆进「内容」节点下，
## 然后在下面「要显示的行」这组里加个引用，最后在 _refresh() 里补一句 set_value()。
##
## 开始界面还挡在前面的时候（HUD 那一层整个被藏起来）按 Tab 不作数，
## 免得面板在开局那一瞬间自己冒出来。

## 开关面板用的输入动作名。项目设置里没有这个名字时自动退回「Tab 键」——
## 这样以后改了动作名、或者干脆把动作删了，面板也还开得起来。
const TOGGLE_ACTION: StringName = &"stats"
## 没有配置 TOGGLE_ACTION 时直接认的按键。
const TOGGLE_KEY: Key = KEY_TAB

@export_group("数据来源")
## 水枪发射器：「水块大小」读它的 blob_size，「频率」由它的 fire_interval 换算。
@export var gun: WaterGun
## 提供时间的太阳。留空时按「太阳」分组自动找（和 scripts/时钟.gd 一个找法）。
@export var sun: SunLight

@export_group("要显示的行")
## 「水块大小」那一行（scenes/界面/属性行.tscn 的实例）。
@export var blob_size_row: AttributeRow
## 「频率」那一行。
@export var rate_row: AttributeRow
## 「时间」那一行。
@export var time_row: AttributeRow

@export_group("数字怎么写")
## 取不到数据（比如水枪不在场）时右边写什么。
@export var text_no_data: String = "——"
## 水块大小怎么写。只有一个 %f，**单位是立方米**（显示的是体积，不是边长）。
## 小数位和水枪上方那块读数（readout_format）保持一致，都是三位。
@export var blob_size_format: String = "%.3f m³"
## 频率怎么写。只有一个 %f，单位是「发/秒」。
@export var rate_format: String = "%.2f 发/秒"
## 时间怎么写：第一个 %02d 时、第二个 %02d 分、%s 时段名。
@export var time_format: String = "%02d:%02d  %s"

@export_group("时段怎么分")
## 几点起算清晨（早于它算夜晚）。
@export_range(0.0, 24.0, 0.5) var dawn_hour: float = 5.0
## 几点起算白天。
@export_range(0.0, 24.0, 0.5) var day_hour: float = 8.0
## 几点起算黄昏。
@export_range(0.0, 24.0, 0.5) var dusk_hour: float = 17.0
## 几点起算夜晚。
@export_range(0.0, 24.0, 0.5) var night_hour: float = 19.0
## 四个时段的名字，顺序固定：清晨 / 白天 / 黄昏 / 夜晚。
@export var period_names: PackedStringArray = PackedStringArray(["清晨", "白天", "黄昏", "夜晚"])

@export_group("开关手感")
## 勾上 = 一进游戏面板就是开着的（自己调试时用）。
@export var open_on_start: bool = false
## 浮出 / 收起各用多久（秒）。填 0 = 硬切，不淡入淡出。
@export_range(0.0, 1.0, 0.01) var fade_time: float = 0.12

var _open: bool = false       # 面板现在该是开着的吗（淡出动画还没走完时也算已经关了）
var _tween: Tween             # 正在跑的淡入/淡出，连按 Tab 时会被掐掉重来


func _ready() -> void:
	# 场景里这块面板是亮着的 —— 方便你在编辑器里摆位置、改字号、换颜色。运行时先收掉。
	modulate.a = 1.0
	if not is_instance_valid(sun):
		sun = _find_sun()
	_open = open_on_start
	if _open:
		_refresh()
	else:
		hide()


## 每帧重刷。收起来时一帧都不跑；开着时三个数值里只有时间会真的在变，
## 另外两个由 属性行.set_value() 自己判断「文字没变就不写」，所以这里不用再省。
func _process(_delta: float) -> void:
	if not visible:
		return
	# 太阳可能比面板晚进场景树，没找到就每帧重试（和 scripts/时钟.gd 一个写法）
	if not is_instance_valid(sun):
		sun = _find_sun()
	_refresh()


## Tab 开、Tab 关。
##
## **用 _input 而不是 _unhandled_input**：Tab 在 Godot 里默认是「切换焦点」键，
## 将来界面上只要出现一个能拿到焦点的按钮（开始界面的按钮就在用 grab_focus），
## 焦点导航会抢先把 Tab 吃掉，面板就安安静静地再也开不起来了 —— 不报错，最难查。
## 所以这里抢在所有节点前面认下这个键；认下了就标成已处理，免得别处再拿它做别的事。
func _input(event: InputEvent) -> void:
	if not _is_toggle(event):
		return
	if not _hud_showing():
		return
	get_viewport().set_input_as_handled()
	_toggle()


## 面板现在开着吗。
func is_open() -> bool:
	return _open


## 展开面板并立刻刷一次数值。
func open() -> void:
	if _open and visible:
		return
	_open = true
	_refresh()
	show()
	_play(true)


## 收起面板。淡出走完才真的 hide() —— 收干净之后就一帧都不再画、也不再刷数值。
func close() -> void:
	_open = false
	_play(false)


## 开 / 关一次。
func _toggle() -> void:
	if _open:
		close()
	else:
		open()


## 这一下按键是不是「开关面板」。长按不算：按住 Tab 不要一直开开关关。
func _is_toggle(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if InputMap.has_action(TOGGLE_ACTION):
		return event.is_action_pressed(TOGGLE_ACTION)
	# 项目设置里没有这个动作时的兜底：直接认 Tab 键本身
	var key: InputEventKey = event as InputEventKey
	return key != null and key.pressed and (key.keycode == TOGGLE_KEY or key.physical_keycode == TOGGLE_KEY)


## 面板挂的那层 HUD 现在露着吗。
## 开始界面挡在前面时它会先把 HUD 整个藏起来，靠这一条把「开局按 Tab」挡掉；
## 万一以后把面板挂到别处去了（找不到 CanvasLayer），就当它是露着的，不影响使用。
func _hud_showing() -> bool:
	var layer: CanvasLayer = get_parent() as CanvasLayer
	return layer == null or layer.visible


## 太阳按「太阳」分组找 —— 和 scripts/时钟.gd、scripts/路灯.gd 是同一套写法，
## 所以太阳叫什么名字、面板摆在哪，都不用连 NodePath。
func _find_sun() -> SunLight:
	return get_tree().get_first_node_in_group(SunLight.GROUP_NAME) as SunLight


## 淡入 / 淡出。fade_time 填 0 就是硬切。
func _play(opening: bool) -> void:
	if is_instance_valid(_tween):
		_tween.kill()   # 连按 Tab 时掐掉上一条，免得被旧动画拽回去
	if fade_time <= 0.0:
		modulate.a = 1.0 if opening else 0.0
		if not opening:
			hide()
		return
	if opening:
		modulate.a = 0.0
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, fade_time)
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)


## 把三行数值重刷一遍。
func _refresh() -> void:
	if is_instance_valid(blob_size_row):
		var size_text: String = text_no_data
		if is_instance_valid(gun):
			size_text = blob_size_format % gun.shot_volume()
		blob_size_row.set_value(size_text)
	if is_instance_valid(rate_row):
		var rate_text: String = text_no_data
		if is_instance_valid(gun):
			rate_text = rate_format % _fire_rate()
		rate_row.set_value(rate_text)
	if is_instance_valid(time_row):
		time_row.set_value(_time_text())


## 每秒能打几发。水枪上的 fire_interval 是「隔几秒一发」，取个倒数就是频率。
## 间隔被填成 0 或负数时不写「无限大」，而是夹一个极小值当上限，免得读数变成一串天文数字。
func _fire_rate() -> float:
	return 1.0 / maxf(gun.fire_interval, 0.001)


## 现在几点，写成「时:分 + 时段」。
## **时间的唯一来源是太阳**（见 scripts/sun.gd）：想改开局几点就改 DirectionalLight3D 的
## start_angle_deg，想改一天多长就改它的 angular_speed，这里跟着走，不另存一份。
func _time_text() -> String:
	if not is_instance_valid(sun):
		return text_no_data
	var hours: float = fposmod(sun.time_of_day, 24.0)
	var hour: int = int(hours)
	var minute: int = int(fmod(hours, 1.0) * 60.0)
	return time_format % [hour, minute, _period_name(hours)]


## 按小时数取时段名。四个名字的顺序固定是 清晨 / 白天 / 黄昏 / 夜晚。
func _period_name(hours: float) -> String:
	if period_names.size() < 4:
		return ""
	if hours < dawn_hour or hours >= night_hour:
		return period_names[3]
	if hours < day_hour:
		return period_names[0]
	if hours < dusk_hour:
		return period_names[1]
	return period_names[2]
