extends Node
class_name DiaryBook

## 奶蛋日记：只管两件事 —— 正文内容和「翻开 / 合上」那块面板。
##
## **手持显隐、1/2 键切槽、按 F 的判定全部在 scripts/道具/手持道具.gd 里。**
## 之前我在这个文件里自己藏水枪、自己写 equipment_fire_blocked，
## 结果和手持道具脚本抢同一个字段，玩家的水枪直接消失、射不出水。
## 记住：水枪的可见性和射击开关**只有手持道具.gd 一个地方能写**。

@export_group("接线")
## 阅读面板（全屏、平时隐藏）。
@export var read_panel: Control
## 面板里显示正文的 Label。
@export var read_label: Label
## 第一次拿到时弹的提示 Label。
@export var hint_label: Label
## 手持道具控制器（拿日记 / 切槽都走它）。
@export var inventory: HeldItemController

@export_group("内容")
## 日记正文。换真文本只改这里。
@export_multiline var diary_text: String = "奶蛋"

@export_group("测试")
## 开局就拥有日记本。**测试用**，正式版关掉，改成抽奖时调 acquire()。
@export var start_with_diary: bool = true

const HINT_TEXT: String = "1 键拿出水枪，2 键拿出日记本\n按 F 键阅读日记本"
const HINT_TIME: float = 6.0

var _hint_left: float = 0.0
var _hint_shown: bool = false


func _resolve() -> void:
	if read_panel == null:
		read_panel = get_node_or_null("阅读面板") as Control
	if read_label == null:
		read_label = get_node_or_null("阅读面板/正文") as Label
	if hint_label == null:
		hint_label = get_node_or_null("提示/文字") as Label
	if inventory == null:
		var root: Node = get_tree().current_scene
		if root == null:
			root = get_parent()
		if root != null:
			# 手持道具是 主人公 的子节点（不是 水枪 的）—— gun_model = ../水枪 能证明这一点。
			# 两个路径都试一遍，免得以后挪了节点又找不到。
			inventory = root.get_node_or_null("主人公/手持道具") as HeldItemController
			if inventory == null:
				inventory = root.get_node_or_null("主人公/水枪/手持道具") as HeldItemController


func _ready() -> void:
	_resolve()
	if read_panel != null:
		read_panel.visible = false
	if hint_label != null:
		hint_label.visible = false
	if inventory != null:
		inventory.diary_read_requested.connect(toggle_read)
	else:
		push_warning("日记本：没接上手持道具，1/2 键和 F 都不会响应")
	if start_with_diary:
		acquire()


## 拿到日记本：交给手持道具记下拥有，第一次拿到时弹一次提示。
func acquire() -> void:
	if inventory != null:
		inventory.acquire_diary()
	if not _hint_shown:
		_hint_shown = true
		_show_hint(HINT_TEXT)


func _show_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.visible = true
	_hint_left = HINT_TIME


func toggle_read() -> void:
	if read_panel == null:
		return
	var open: bool = not read_panel.visible
	read_panel.visible = open
	if open and read_label != null:
		read_label.text = diary_text


func _process(delta: float) -> void:
	if _hint_left <= 0.0 or hint_label == null:
		return
	_hint_left -= delta
	if _hint_left <= 0.0:
		hint_label.visible = false
	elif _hint_left < 1.0:
		hint_label.modulate.a = _hint_left
