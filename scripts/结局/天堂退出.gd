extends Node

## 天堂退出：在最终场景里按 Esc，切回主场景。
##
## 主场景**本身就带着「开始界面」**（scenes/main.tscn 末尾那个实例），开局就是摊开的菜单，
## 所以切回去正好就是「回菜单」—— 屏幕上那句「按 Esc 回菜单」落到实处的就是这一下。
##
## **注意这是重新开始，不是继续**：主场景一加载，上一次的世界（水、邮币、炮台、木碗里的水）
## 就随着旧场景一起销毁了。想改成别的去向（回标题、退出程序），改下面那个 @export 就行。
##
## 和主场景里的「开始界面.gd」是同一个分工：那边管菜单什么时候摊开、什么时候收起，
## 这边只管「天堂里按 Esc 会去哪儿」。两边都听 ui_cancel（Esc 在 Godot 里就是这个动作），
## 但它们从不出现在同一个场景里，所以不会抢。

## 按 Esc 之后切到哪个场景。留空 = 什么都不做（那样天堂里就出不去了）。
@export_file("*.tscn") var exit_scene: String = "res://scenes/main.tscn"
## 切之前先把黑幕淡上来几秒，别硬切。填 0 = 直接切。要用这个就得接上 curtain。
@export_range(0.0, 10.0, 0.05) var fade_time: float = 0.6
## 那块黑幕（天堂「界面」层下的 ColorRect），和天堂开场用的是同一块。
@export var curtain: ColorRect

var _leaving: bool = false   # 只认第一次按 Esc


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		leave()


## 按 Esc：黑幕淡上来，然后切场景。重复调用无副作用。
func leave() -> void:
	if _leaving:
		return
	if exit_scene.is_empty():
		push_warning("天堂退出：没填要切到哪个场景，按 Esc 不会有反应。")
		return
	_leaving = true
	if is_instance_valid(curtain) and fade_time > 0.0:
		curtain.visible = true
		curtain.modulate.a = 0.0
		await create_tween().tween_property(curtain, "modulate:a", 1.0, fade_time).finished
	get_tree().change_scene_to_file(exit_scene)
