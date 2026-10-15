extends Node3D
class_name InteractOptionRow

## 交互菜单里的一行：左边一句说明，右边一个价格，准星扫到时底下亮起一条高亮。
##
## 它不认识钱、也不认识升级 —— 显示什么由外面算好了喂进来（update()），
## 它只管「把字摆好、按状态上色、选中时亮高亮」。
##
## 「选中区」（Area3D）是给菜单的射线打的那块看不见的判定框；
## 菜单收起来时会被整个关掉（collision_layer 归零），否则一块看不见的碰撞体
## 会横在玩家和物体中间，把「看着物体」变成「看着菜单」。
##
## **排版是按字体量出来的真实字宽算的**：说明贴左边、价格贴右边，两边各占各的，
## 所以文案改成多长都不会跑出框；实在长到放不下会自动缩字号（缩到 min_font_size 为止）。
## 一行有多宽取自「高亮」那条的宽度 —— 想加宽这一行，在编辑器里把高亮条拉宽即可。
##
## 文字是「以节点原点为中心」画的（Label3D 的固有行为），所以贴边位置都减了半个字宽。

## 左边那行说明字。
@export var text_label: Label3D
## 右边的价格。
@export var price_label: Label3D
## 选中时亮起来的底。
@export var highlight: MeshInstance3D
## 准星扫到这里就算选中这一行。
@export var select_area: Area3D
## 文字离行的左右边缘留多少（米）。
@export_range(0.0, 0.3, 0.005) var padding: float = 0.03
## 说明和价格之间至少留多少空隙（米），用来判断会不会撞上。
@export_range(0.0, 0.5, 0.005) var gap: float = 0.06
## 自动缩字号时的下限。
@export_range(8, 96, 1) var min_font_size: int = 22
## 选不了（钱不够 / 条件不满足）时价格的颜色。
@export var blocked_color: Color = Color(1.0, 0.45, 0.42)
## 已经做完了时价格的颜色。
@export var done_color: Color = Color(0.62, 0.66, 0.7)

## 这一行现在能不能选。
enum State {
	OK,     ## 正常，能选
	BLOCK,  ## 选不了（钱不够 / 条件不满足）—— 价格标红
	DONE,   ## 已经做完了 —— 灰字
}

var _layer_when_on: int = 0        # 场景里给「选中区」配的碰撞层，关掉之后按它恢复
var _base_font_size: int = 40      # 场景里摆的字号 = 最大字号，放不下时从它往下缩
var _base_color: Color = Color.WHITE


func _ready() -> void:
	if is_instance_valid(text_label):
		_base_font_size = text_label.font_size
	if is_instance_valid(price_label):
		_base_color = price_label.modulate
	if is_instance_valid(select_area):
		_layer_when_on = select_area.collision_layer
	set_selected(false)
	set_clickable(false)   # 菜单是收着的，先别挡射线


## 换一行字。text 是左边那句说明，price 是右边的价格，state 只影响价格的颜色。
func update(text: String, price: String, state: State) -> void:
	if is_instance_valid(text_label):
		text_label.text = text
	if is_instance_valid(price_label):
		price_label.text = price
		price_label.modulate = _color_for(state)
	_layout(text, price)


## 准星扫到 / 扫开这一行。
func set_selected(on: bool) -> void:
	if is_instance_valid(highlight):
		highlight.visible = on


## 这一行现在能不能被准星扫中。菜单收起时必须关掉，理由见文件头。
## 用 set_deferred：这是物理状态，在物理帧里直接改会被引擎拒绝。
func set_clickable(on: bool) -> void:
	if not is_instance_valid(select_area):
		return
	select_area.set_deferred("collision_layer", _layer_when_on if on else 0)


## 按状态给价格上色。
func _color_for(state: State) -> Color:
	match state:
		State.BLOCK:
			return blocked_color
		State.DONE:
			return done_color
		_:
			return _base_color


## 排版：说明贴左、价格贴右。位置按量出来的真实字宽算，所以文案再长也跑不出框。
func _layout(text: String, price: String) -> void:
	if not is_instance_valid(text_label) or not is_instance_valid(price_label):
		return
	var half: float = _half_width()
	var usable: float = maxf(half * 2.0 - padding * 2.0, 0.01)
	var size: int = _base_font_size
	var text_width: float = _measure(text_label, text, size)
	var price_width: float = _measure(price_label, price, size)
	# 两个加起来都放不下就整体缩字号 —— 字宽和字号大致成正比，所以缩一次就够
	var needed: float = text_width + price_width + gap
	if needed > usable:
		size = maxi(int(float(_base_font_size) * usable / needed), min_font_size)
		text_width = _measure(text_label, text, size)
		price_width = _measure(price_label, price, size)
	if text_label.font_size != size:
		text_label.font_size = size
	if price_label.font_size != size:
		price_label.font_size = size
	text_label.position.x = -half + padding + text_width * 0.5
	price_label.position.x = half - padding - price_width * 0.5


## 这一行有多宽：以「高亮」那条的宽度为准（编辑器里拉宽它，文字会自动跟着重排）。
func _half_width() -> float:
	if is_instance_valid(highlight) and highlight.mesh is QuadMesh:
		return (highlight.mesh as QuadMesh).size.x * 0.5
	return 0.5


## 量一段文字在某个字号下有多宽（米）。
func _measure(label: Label3D, text: String, size: int) -> float:
	var font: Font = label.font
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * label.pixel_size
