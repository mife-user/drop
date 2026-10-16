extends CanvasLayer

## 结局黑幕：天堂之门喊「有玩家走进来了」的那一刻，黑幕淡上来盖住画面，然后切到最终场景。
##
## 全场只有这个节点知道「结局是哪个场景」—— 门只管什么时候亮、谁走进来了，
## 幕布只管怎么盖、盖多久、盖完去哪儿。以后想换个触发源（另一道门、倒计时、某个按键），
## 把它接到同一条 entered 信号上就行，这个脚本一行不用改。
##
## 这一层要盖在所有 UI 上面（layer 比开始界面那层还高），否则黑幕会被 HUD 压住。
##
## **切场景之后本节点跟着主场景一起被销毁**，所以「从黑幕淡回来」是做在最终场景那一边的
## （见 scripts/结局/天堂开场.gd）—— 这边的幕布只负责淡到全黑，不负责再亮回来。
##
## 黑幕平时是完全藏起来的（visible = false），所以不开菜单的时候它既看不见也吃不到鼠标。

## 触发源：main.tscn 的「天堂之门」。留空 = 只能自己调 play()。
@export var door: HeavenDoor
## 盖住画面的那块黑幕（本节点下的 ColorRect）。留空 = 不黑屏，到点直接切。
@export var curtain: ColorRect
## 黑幕淡到全黑用几秒；填 0 = 立刻就黑。
@export_range(0.0, 10.0, 0.05) var fade_time: float = 1.5
## 全黑之后、切场景之前再停几秒（留一口气，以后要加音效也在这里）；填 0 = 黑透就切。
@export_range(0.0, 10.0, 0.1) var hold_black: float = 0.5
## 切到哪个场景。**别填错**：切过去的瞬间主场景连同这个世界一起被销毁，回不来了。
@export_file("*.tscn") var next_scene: String = "res://scenes/奶蛋-天堂.tscn"

var _playing: bool = false   # 结局只演一次


func _ready() -> void:
	if is_instance_valid(curtain):
		curtain.visible = false
	if is_instance_valid(door):
		door.entered.connect(play)
	else:
		push_warning("结局黑幕：没接「天堂之门」，玩家走进去不会有反应。")


## 演一遍结局。重复调用只认第一次。
func play() -> void:
	if _playing:
		return
	_playing = true
	if is_instance_valid(curtain):
		curtain.visible = true
		curtain.modulate.a = 0.0
		if fade_time > 0.0:
			# tween_property 的时长必须大于 0，所以填 0 时走下面那条「立刻就黑」
			await create_tween().tween_property(curtain, "modulate:a", 1.0, fade_time).finished
		else:
			curtain.modulate.a = 1.0
	if hold_black > 0.0:
		await get_tree().create_timer(hold_black).timeout
	if next_scene.is_empty():
		push_warning("结局黑幕：没填要切到哪个场景，画面就停在全黑了。")
		return
	get_tree().change_scene_to_file(next_scene)
