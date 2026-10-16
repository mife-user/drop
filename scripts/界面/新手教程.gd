extends Control
class_name Tutorial

## 新手教程：开局挨着弹七句提示，**该解锁的那几句，在它淡入的那一刻解锁**。
##
## 「进入游戏」的准确定义是**开始界面按下「开始游戏」那一下**：教程由它调 begin() 叫起来，
## 在同一瞬间把开局该收的按键全收走（晚一帧玩家就能先跑两步）。说话则要等幕布收干净
## （见 _wait_for_hud）—— 不去猜开始界面的退场时长，直接问它那层 HUD 亮没亮。
##
## **按键是「收走」，不是「屏蔽」。** 动的是全局的输入映射（InputMap）：把动作上绑的按键
## 临时摘下来，到点原样装回去。所以 player.gd / 水枪.gd / 世界属性面板.gd 一行都不用改 ——
## 它们照常问「W 键按着没有」，答案自然是没有。
##
## 摘的只是**按键**，动作本身留着（用 action_erase_events 而不是 erase_action）：
## 世界属性面板.gd 里有一条「没有 stats 这个动作就直接认 Tab 键」的兜底，
## 动作真被删掉，反而会把 Tab 重新打开。
##
## 由此有一条铁律：**这个节点走人之前必须把按键还回去**（见 _exit_tree）。
## 没还的话那几个键会一直哑着，而且不报错 ——「按 W 没反应」是最难查的一类毛病。
## 同理，等 HUD 也不是无限等（hud_wait_limit 到点就开演）。
##
## 屏幕上只有「提示」这一个 Label，台词在下面那八个 @export 字符串里；
## 字号、颜色（现在是半透明的金黄色）、描边、阴影全在场景里那个 LabelSettings 上，
## 脚本一个色号都不写 —— 想改外观直接在检查器里拖那个 Label。
## 场景里 Label 的 Text 只是为了让你在编辑器里摆位置时看得见，运行时会被清掉。
## 想加一句：加一个 @export 字符串，在 _play_all() 里插一行 _say()；要顺带解锁就再加一行 _unlock()。


## —— 教程会收走哪些动作。**分成四组是为了「一组一组地还」**：
## 第一句期间全收着，之后每念一句还一组回去。
## 名字要和 project.godot 的 [input] 里那几条对得上。**写错了不会报错** ——
## _lock() 用 has_action 挡着，表现只是「那个键一直能用」，所以改动作名时记得连着看这儿。
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back"]
const JUMP_ACTIONS: Array[StringName] = [&"jump"]
const STATS_ACTIONS: Array[StringName] = [&"stats"]
const FIRE_ACTIONS: Array[StringName] = [&"fire"]

@export_group("接线")
## 屏幕上那块字（本场景里的「提示」）。留空 = 不显示字，但解锁流程照走。
@export var prompt_label: Label
## 玩家的水枪发射器（main.tscn 的「主人公/水枪/水枪发射器」）：接它的 tank_emptied，
## 第一次打空时弹「没水了」那句。留空 = 那句永远不会弹。
@export var gun: WaterGun

@export_group("开关")
## 取消勾选 = 七句话不演、一个开局该收的键都不收（自己调试时用）。
## **「没水了」那句不受它管** —— 那句连的是水枪的信号，是个玩法提示，不是教程流程的一部分。
@export var enabled: bool = true
## 等「界面」那层亮起来最多等几秒（见 _wait_for_hud）。填 0 = 不等，叫起来就开演。
@export_range(0.0, 30.0, 0.5) var hud_wait_limit: float = 6.0

@export_group("台词")
## 第一句。这时候什么都还没解锁 —— 留给玩家环顾一下（视角从第一秒起就是自由的）。
@export var line_welcome: String = "欢迎来到这个世界"
## 第二句。念这句的同时解锁 WASD。
@export var line_move: String = "WASD 可以移动"
## 第三句。念这句的同时解锁空格。
@export var line_jump: String = "空格键跳跃"
## 第四句。念这句的同时解锁 Tab。
@export var line_stats: String = "Tab 键查看这个世界"
## 第五句。念这句的同时解锁鼠标左键。
@export var line_fire: String = "鼠标左键可以射水"
## 第六句。**纯文字，一个键都不解锁**（左键上一条已经解锁完了）——
## 它讲的是左键在菜单里的另一个用途。商店要先按 E 才打得开，教程故意不专门讲 E：
## 准星对着台座的时候，下面本来就会自己弹出「按 E 交互」，玩家看得到。
@export var line_buy: String = "鼠标左键购买商品"
## 第七句，收尾的宣言。同样不解锁任何东西 —— 它演完，教程就结束了。
@export var line_finale: String = "最后，用水填满这个世界吧，天堂在迎接你"
## 水枪第一次打空时弹的那句（**全场只弹一次**，见 _on_tank_emptied）。
@export var line_no_water: String = "没水了？也许可以找找附近是否有接水的地方"

@export_group("节奏")
## 幕布收干净之后再等多久开演（秒）。留一口气，别让第一个字和退场动画撞在一起。
@export_range(0.0, 3.0, 0.05) var start_delay: float = 0.25
## 每句淡入多久（秒）。填 0 = 直接出现。
@export_range(0.0, 3.0, 0.05) var fade_in: float = 0.45
## 每句停留多久（秒）：淡入结束到开始淡出之间隔多久。
@export_range(0.1, 10.0, 0.1) var hold_time: float = 1.6
## 每句淡出多久（秒）。填 0 = 到点直接消失。
@export_range(0.0, 3.0, 0.05) var fade_out: float = 0.55

var _running: bool = false            # 七句话还在演
var _no_water_shown: bool = false     # 「没水了」那句弹过了吗（全场只弹一次）
var _pending_no_water: bool = false   # 教程还在演的时候打空了：先记下，演完再弹，免得两句话叠在一起
var _saved: Dictionary = {}           # 动作名 → 它原本绑了哪些按键（收走之前留的底）
var _tween: Tween                     # 正在跑的那一句，连着重来时要掐掉


func _ready() -> void:
	# 场景里那块字是亮着的（方便你在编辑器里摆位置、调字号），运行时先收干净 ——
	# 不收的话，开始界面那块幕布还挡在前面时它就已经露出来了。
	if is_instance_valid(prompt_label):
		prompt_label.text = ""
		prompt_label.modulate.a = 0.0
		prompt_label.hide()
	if is_instance_valid(gun):
		gun.tank_emptied.connect(_on_tank_emptied)


## 由开始界面在「开始游戏」那一下调用。**立刻收按键**（那一下正是控制权交接的时刻），
## 说话等幕布收干净再开始。重复调用无副作用；enabled 取消勾选时七句话不演、键也不收。
func begin() -> void:
	if not enabled or _running:
		return
	_running = true
	_lock(MOVE_ACTIONS)
	_lock(JUMP_ACTIONS)
	_lock(STATS_ACTIONS)
	_lock(FIRE_ACTIONS)
	_play_all()


# —— 七句话 ——


## 一路演下去。**解锁就发生在那一句淡入的同一刻**：玩家可以边看边试着按，不用等字消失。
## 想改顺序、加一句、少一句，改的就是这一段。
func _play_all() -> void:
	await _wait_for_hud()
	await _say(line_welcome)
	_unlock(MOVE_ACTIONS)
	await _say(line_move)
	_unlock(JUMP_ACTIONS)
	await _say(line_jump)
	_unlock(STATS_ACTIONS)
	await _say(line_stats)
	_unlock(FIRE_ACTIONS)
	await _say(line_fire)
	# 最后两句只管把话说完整，没有对应的 _unlock() —— 别以为漏写了：
	# 左键在上一条就解锁完了，这两句只是说明和收尾。
	await _say(line_buy)
	await _say(line_finale)
	_running = false
	_flush_no_water()


## 念一句：淡入 → 停留 → 淡出，整句演完才返回。
## 时间参数和「水量字幕」用的是同一套名字和口径，调起来手感一样。
func _say(text: String) -> void:
	if not is_instance_valid(prompt_label):
		return
	if is_instance_valid(_tween):
		_tween.kill()
	prompt_label.text = text
	prompt_label.show()
	prompt_label.modulate.a = 0.0
	# tween_property 的时长必须大于 0，所以填 0 时给一个极小值，效果上就是「直接出现 / 直接消失」
	_tween = create_tween()
	_tween.tween_property(prompt_label, "modulate:a", 1.0, maxf(fade_in, 0.01))
	_tween.tween_interval(maxf(hold_time, 0.0))
	_tween.tween_property(prompt_label, "modulate:a", 0.0, maxf(fade_out, 0.01))
	await _tween.finished
	if is_instance_valid(prompt_label):
		prompt_label.hide()


## 等「界面」那层亮起来 —— 也就是开始界面把幕布收干净的那一刻。
## 最多等 hud_wait_limit 秒，到点不等了直接开演：万一开始界面那边出了岔子，
## 也不至于永远卡在「按键收着」的状态里（那样按 W 会一直没反应，还不报错，最难查）。
func _wait_for_hud() -> void:
	var deadline: int = Time.get_ticks_msec() + int(hud_wait_limit * 1000.0)
	while not _hud_showing() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout


## 本节点挂的那层 HUD 现在露着吗。和 世界属性面板.gd 的 _hud_showing() 是同一个判断 ——
## 挂到别处去了（找不到 CanvasLayer）就当它露着，不影响使用。
func _hud_showing() -> bool:
	var layer: CanvasLayer = get_parent() as CanvasLayer
	return layer == null or layer.visible


# —— 收按键 / 还按键 ——


## 把这些动作上绑的按键临时收走。**先留一份底**，解锁就是把这一份原样装回去。
## 用 action_erase_events 而不是 erase_action：动作本身要留着（理由见文件头）。
func _lock(actions: Array[StringName]) -> void:
	for action: StringName in actions:
		if _saved.has(action) or not InputMap.has_action(action):
			continue
		_saved[action] = InputMap.action_get_events(action)
		InputMap.action_erase_events(action)


## 把按键还回去。没锁过的动作会被 _saved 挡住，重复调用无副作用。
func _unlock(actions: Array[StringName]) -> void:
	for action: StringName in actions:
		if not _saved.has(action):
			continue
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)
		_saved.erase(action)


## 走人之前把按键全还回去。**这是兜底**：教程演到一半这个节点被删掉（换场景、被别处 free），
## 正常那几条还按键的路就都走不到了 —— 不还的话那几个键会一直哑着，而且不报错。
func _exit_tree() -> void:
	_unlock(MOVE_ACTIONS)
	_unlock(JUMP_ACTIONS)
	_unlock(STATS_ACTIONS)
	_unlock(FIRE_ACTIONS)


# —— 「没水了」那句 ——


## 水枪打空了（每箱只报一次）。教程还在演就先记着，演完再弹 —— 否则两句话会叠在一起。
func _on_tank_emptied() -> void:
	if _no_water_shown:
		return
	if _running:
		_pending_no_water = true
		return
	_show_no_water()


## 把刚才欠下的那句补上。
func _flush_no_water() -> void:
	if not _pending_no_water:
		return
	_pending_no_water = false
	_show_no_water()


## 弹「没水了」。**先立牌子再演**：这句全场只弹一次。
func _show_no_water() -> void:
	_no_water_shown = true
	_say(line_no_water)
