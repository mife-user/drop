extends Node

## 开始界面：压在游戏世界上的一层幕布 + 菜单。开局摊开，游戏中**按 Esc 还会再摊开一次**。
##
## 背景不是录屏也不是复制品，就是正在跑的主场景本身——太阳照常公转、水面照常流动。
## 菜单摊开期间**游戏照常跑，只有玩家被冻住**（process_mode 关掉，和暂停不是一回事）。
##
## 本脚本只做四件事（外加第一次叫醒新手教程），其余全交给 scenes/开始界面.tscn 里看得见的节点：
##   1) 摊开菜单：抢过镜头（上帝相机）、亮出光标、把主人公冻住；
##   2) 「开始游戏」：把镜头还给主人公、解冻、锁光标，幕布淡出后整层隐藏 ——
##      第一次的那一下顺带叫醒新手教程（见 tutorial）；之后从 Esc 回来不再重演；
##   3) 按 Esc：把菜单重新摊开（reopen()），世界状态原样保留；
##   4) 「退出游戏」：先把背景音乐淡出，再退出程序。
##
## 幕布的浓淡、渐变色标、字体字号、按钮样式全部在检查器里调，这里一个数值都不写死。

## 俯视全城的相机（本场景内的子节点）。点「开始游戏」后把 current 交还给 player_camera。
@export var god_camera: Camera3D
## 本场景的 CanvasLayer，退场时整层隐藏，之后不再吃任何鼠标事件。
@export var ui_layer: CanvasLayer
## 幕布（压暗 + 渐变两层），退场时整块淡出。
@export var curtain: Control
## 标题块（入场时和按钮组错开滑入）。
@export var title_block: Control
## 按钮组（入场时和标题块错开滑入）。
@export var button_block: Control
## 主人公（在 main.tscn 里）。菜单期间会被冻住——否则按 WASD 能把人推走，
## 点空白处还会被 player.gd 抢走鼠标，菜单就点不动了。
@export var player: Node3D
## 主人公自己的第一人称相机，点「开始游戏」后交还给它。
@export var player_camera: Camera3D
## 菜单期间要藏起来的 HUD（main.tscn 的「界面」CanvasLayer）。
@export var hud: CanvasLayer
## 新手教程（main.tscn 的「界面/新手教程」）。点「开始游戏」那一刻叫它起床。
## 留空 = 没有教程，一切照旧。
@export var tutorial: Tutorial
## 背景音乐（main.tscn 的「背景音乐」）。菜单里的音乐按钮直接调它的开关。
## 留空 = 菜单里的音乐按钮会藏起来。
@export var music: BackgroundMusic
## 「开始游戏」按钮，连信号用。
@export var start_button: Button
## 「退出游戏」按钮，连信号用。
@export var quit_button: Button
## 菜单右上角的音乐开关按钮，连信号、刷文字用。
@export var music_button: Button
## 音乐开着时按钮上的字（可以在检查器里改成别的说法）。
@export var music_on_text: String = "音乐：开"
## 音乐关着时按钮上的字。
@export var music_off_text: String = "音乐：关"

## 入场时标题块与按钮组之间的间隔（秒），做「依次出现」的层次感。
@export_range(0.0, 0.3, 0.01) var stagger: float = 0.07
## 入场时长（秒）。
@export_range(0.05, 2.0, 0.05) var enter_time: float = 0.45
## 退场时长（秒）；按钮比幕布收得快，先人一步让位给游戏画面。
@export_range(0.05, 2.0, 0.05) var exit_time: float = 0.4
## 入场时两个块从左边滑进来的距离（像素），填 0 就只淡入不滑动。
@export_range(0.0, 200.0, 1.0) var slide_distance: float = 28.0

var _menu_open: bool = true           # 菜单现在是不是摊开的（也是「能不能再摊开一次」的闸）
var _tutorial_started: bool = false   # 新手教程全场只叫醒一次
var _quitting: bool = false           # 退出只演一次，防止连点把音乐的淡出等两遍
var _anims: Array[Tween] = []         # 本层正在跑的动画（入场 / 退场），换场面前先全掐掉


func _ready() -> void:
	# 父节点的 _ready 晚于所有子节点（包括 main.tscn 里的主人公），
	# 所以这里做的几件事一定是"最后生效"的那一次，不会和 player.gd 的鼠标捕获打架。
	if is_instance_valid(start_button):
		start_button.pressed.connect(_on_start_pressed)
	if is_instance_valid(quit_button):
		quit_button.pressed.connect(_on_quit_pressed)
	if is_instance_valid(music_button):
		music_button.pressed.connect(_on_music_pressed)
	if is_instance_valid(music):
		music.enabled_changed.connect(_on_music_enabled_changed)
	else:
		push_warning("开始界面：没接「背景音乐」，菜单里的音乐按钮没东西可开关。")
	_show_menu()   # 开局先摊开一次


## 按 Esc（ui_cancel）：把菜单拉回来。**游戏照常跑**（太阳在转、水在流），只有玩家被冻住。
##
## 菜单已经摊开时再按 Esc 什么都不做 —— 回游戏请点菜单里的按钮，
## 这样玩家一路狂按 Esc 也不会在「菜单 / 游戏」之间闪来闪去。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		reopen()


## 把菜单重新摊开 —— 玩家按 Esc 走的就是这条路。菜单已经开着时什么都不做。
func reopen() -> void:
	if _menu_open:
		return
	_show_menu()


## 摊开菜单：抢过镜头、亮出光标、冻住玩家、收起 HUD、亮出这一层，再放一遍入场动画。
##
## **它不碰新手教程** —— 从 Esc 菜单回到游戏不该把教程再演一遍（见 _tutorial_started）。
## 也不重新加载场景，所以世界状态原样保留：水还在池子里、邮币还在、炮台还在原地。
func _show_menu() -> void:
	_kill_anims()
	_menu_open = true
	if is_instance_valid(god_camera):
		god_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(hud):
		hud.visible = false
	if is_instance_valid(ui_layer):
		ui_layer.visible = true
	if is_instance_valid(start_button):
		start_button.grab_focus()   # 键盘 Enter / ↑↓ 直接可用，不用先点一下
	_refresh_music_button()   # 从 Esc 回来时，按钮文字要跟上音乐的当前状态
	_play_enter()


## 把本层正在跑的动画全掐掉。入场演到一半又按 Esc、或者退场演到一半又按开始游戏，
## 不掐的话上一段会接着演完 —— 最难受的一种是退场演完顺手把刚摊开的菜单又收回去。
func _kill_anims() -> void:
	for tween in _anims:
		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()
	_anims.clear()


## 入场：幕布整体淡入，标题块与按钮组错开地从左边滑进来。
func _play_enter() -> void:
	var items: Array[Control] = []
	for candidate: Control in [title_block, button_block]:
		if is_instance_valid(candidate):
			items.append(candidate)
	if is_instance_valid(curtain):
		curtain.modulate.a = 0.0
		var curtain_tween: Tween = create_tween()
		curtain_tween.tween_property(curtain, "modulate:a", 1.0, enter_time)
		_anims.append(curtain_tween)
	# 右上角的音乐按钮不做滑动，只跟着幕布一起淡进来
	if is_instance_valid(music_button):
		music_button.modulate.a = 0.0
		var music_tween: Tween = create_tween()
		music_tween.tween_property(music_button, "modulate:a", 1.0, enter_time)
		_anims.append(music_tween)
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
		_anims.append(tween)


## 开始（或继续）游戏：先把控制权一次交还给玩家（镜头、解冻、锁光标同时完成，不出现"能走但没镜头"的中间态），
## 再收幕布。切镜头不重新加载场景，所以世界状态原样保留。
func _on_start_pressed() -> void:
	if not _menu_open:
		return
	_kill_anims()
	_menu_open = false
	# 教程要在「控制权交还玩家」的同一瞬间把开局该收的按键收走，所以是在这儿叫它、
	# 而不是等幕布淡完（那中间有 0.4 秒玩家已经能跑能跳了）。说话它会自己等幕布收干净。
	# **只在第一次玩时叫一次**：从 Esc 菜单回来再练一遍 WASD 太烦，
	# 而且教程会把按键重新收走，回来的人会觉得「怎么突然又走不动了」。
	if not _tutorial_started and is_instance_valid(tutorial):
		_tutorial_started = true
		tutorial.begin()
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
	for item: Control in [title_block, button_block, music_button]:
		if is_instance_valid(item):
			tween.tween_property(item, "modulate:a", 0.0, exit_time * 0.5)
	tween.finished.connect(_on_exit_finished)
	_anims.append(tween)


## 幕布收干净之后才隐藏整层：既不再挡鼠标，也不用每帧绘制。
func _on_exit_finished() -> void:
	if is_instance_valid(hud):
		hud.visible = true
	if is_instance_valid(ui_layer):
		ui_layer.visible = false


## 音乐按钮：按一下切一次开关。文字刷新统一走 enabled_changed 信号，这里不自己改字。
func _on_music_pressed() -> void:
	if is_instance_valid(music):
		music.toggle()


## 音乐开关状态变了（按按钮、或者别处调 set_enabled 都算）：同步按钮上的字。
func _on_music_enabled_changed(_enabled: bool) -> void:
	_refresh_music_button()


## 让按钮文字跟上音乐的真实状态；没接背景音乐时把按钮藏起来，不留一个按了没反应的死按钮。
func _refresh_music_button() -> void:
	if not is_instance_valid(music_button):
		return
	if not is_instance_valid(music):
		music_button.visible = false
		return
	music_button.text = music_on_text if music.is_enabled() else music_off_text


## 退出游戏：先把背景音乐淡出，再关窗口；音乐本来就关着就立刻退。
func _on_quit_pressed() -> void:
	if _quitting:
		return
	_quitting = true
	# 等淡出的这段时间菜单还会被点到，先把三个按钮停掉，免得又开音乐 / 又点一次退出。
	for button: Button in [start_button, quit_button, music_button]:
		if is_instance_valid(button):
			button.disabled = true
	if is_instance_valid(music) and music.is_enabled():
		await music.fade_out_and_stop()
	get_tree().quit()
