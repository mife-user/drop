extends Node

## 开始界面：开局压在游戏世界上的一层幕布 + 菜单。
##
## 背景不是录屏也不是复制品，就是正在跑的主场景本身——太阳照常公转、水面照常流动。
## 本脚本只做三件事，其余全交给 scenes/开始界面.tscn 里看得见的节点：
##   1) 进场：抢过镜头（上帝相机）、亮出光标、把主人公冻住（世界照常跑，只有玩家不动）；
##   2) 「开始游戏」：把镜头还给主人公、解冻、锁光标，幕布淡出后整层隐藏；
##   3) 「退出游戏」：直接退出程序。
## 幕布的浓淡、渐变色标、字体字号、按钮样式全部在检查器里调，这里一个数值都不写死。

## 俯视全城的相机（本场景内的子节点）。点「开始游戏」后把 current 交还给 player_camera。
@export var god_camera: Camera3D
## 本场景的 CanvasLayer，退场时整层隐藏，之后不再吃任何鼠标事件。
@export var ui_layer: CanvasLayer
## 幕布（压暗 + 渐变两层），退场时整块淡出。
@export var curtain: Control
## 标题块 / 按钮组：入场时错开滑入。
@export var title_block: Control
@export var button_block: Control
## 主人公（在 main.tscn 里）。菜单期间会被冻住——否则按 WASD 能把人推走，
## 点空白处还会被 player.gd 抢走鼠标，菜单就点不动了。
@export var player: Node3D
## 主人公自己的第一人称相机，点「开始游戏」后交还给它。
@export var player_camera: Camera3D
## 菜单期间要藏起来的 HUD（main.tscn 的「界面」CanvasLayer）。
@export var hud: CanvasLayer
## 两个按钮，连信号用。
@export var start_button: Button
@export var quit_button: Button

## 入场时标题块与按钮组之间的间隔（秒），做「依次出现」的层次感。
@export_range(0.0, 0.3, 0.01) var stagger: float = 0.07
## 入场时长（秒）。
@export_range(0.05, 2.0, 0.05) var enter_time: float = 0.45
## 退场时长（秒）；按钮比幕布收得快，先人一步让位给游戏画面。
@export_range(0.05, 2.0, 0.05) var exit_time: float = 0.4
## 入场时两个块从左边滑进来的距离（像素），填 0 就只淡入不滑动。
@export_range(0.0, 200.0, 1.0) var slide_distance: float = 28.0

var _started: bool = false   # 「开始游戏」只认第一次点击


func _ready() -> void:
	# 父节点的 _ready 晚于所有子节点（包括 main.tscn 里的主人公），
	# 所以这里做的三件事一定是"最后生效"的那一次，不会和 player.gd 的鼠标捕获打架。
	if is_instance_valid(god_camera):
		god_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(hud):
		hud.visible = false
	if is_instance_valid(start_button):
		start_button.pressed.connect(_on_start_pressed)
		start_button.grab_focus()   # 键盘 Enter / ↑↓ 直接可用，不用先点一下
	if is_instance_valid(quit_button):
		quit_button.pressed.connect(_on_quit_pressed)
	_play_enter()


## 入场：幕布整体淡入，标题块与按钮组错开地从左边滑进来。
func _play_enter() -> void:
	var items: Array[Control] = []
	for candidate: Control in [title_block, button_block]:
		if is_instance_valid(candidate):
			items.append(candidate)
	if is_instance_valid(curtain):
		curtain.modulate.a = 0.0
		create_tween().tween_property(curtain, "modulate:a", 1.0, enter_time)
	for i: int in items.size():
		var item: Control = items[i]
		var target: Vector2 = item.position
		item.position = target - Vector2(slide_distance, 0.0)
		item.modulate.a = 0.0
		var tween: Tween = create_tween().set_parallel()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var delay: float = float(i) * stagger
		tween.tween_property(item, "position", target, enter_time).set_delay(delay)
		tween.tween_property(item, "modulate:a", 1.0, enter_time).set_delay(delay)


## 开始游戏：先把控制权一次交还给玩家（镜头、解冻、锁光标同时完成，不出现"能走但没镜头"的中间态），
## 再收幕布。切镜头不重新加载场景，所以世界状态原样保留。
func _on_start_pressed() -> void:
	if _started:
		return
	_started = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(player_camera):
		player_camera.current = true
	if is_instance_valid(god_camera):
		god_camera.current = false
	var tween: Tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(curtain):
		tween.tween_property(curtain, "modulate:a", 0.0, exit_time)
	for item: Control in [title_block, button_block]:
		if is_instance_valid(item):
			tween.tween_property(item, "modulate:a", 0.0, exit_time * 0.5)
	tween.finished.connect(_on_exit_finished)


## 幕布收干净之后才隐藏整层：既不再挡鼠标，也不用每帧绘制。
func _on_exit_finished() -> void:
	if is_instance_valid(hud):
		hud.visible = true
	if is_instance_valid(ui_layer):
		ui_layer.visible = false


func _on_quit_pressed() -> void:
	get_tree().quit()
