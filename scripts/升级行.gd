extends Node3D
class_name UpgradeRow

## 升级面板里的一行：左边一句说明（「出水速度 15.0 → 17.5 m/s」），右边一个价格（「3 枚」），
## 准星扫到这一行时底下亮起一条青色高亮。
##
## 它不认识邮币、也不认识水枪 —— 显示什么由升级台算好了喂进来（update()），
## 它只负责「把字显示出来、按状态给价格上色、选中时亮高亮」。
##
## 「选中区」（Area3D）是专门给升级台的射线打的那块看不见的判定框：
## 准星扫到它就等于选中这一行。**面板收起来的时候会被整个关掉**（collision_layer 归零），
## 否则一块看不见的碰撞体横在水枪前面，玩家"看着水枪"会变成"看着面板"。

## 左边那行说明字。
@export var text_label: Label3D
## 右边的价格。
@export var price_label: Label3D
## 选中时亮起来的底。
@export var highlight: MeshInstance3D
## 准星扫到这里就算选中这一行。
@export var select_area: Area3D
## 价格买不起时的颜色。
@export var poor_color: Color = Color(1.0, 0.45, 0.42)
## 已经升到头时的颜色。
@export var max_color: Color = Color(0.62, 0.66, 0.7)

## 这一行现在能不能买。
enum State {
	OK,   ## 买得起
	POOR, ## 邮币不够
	MAX,  ## 已经升到头了
}

var _layer_when_on: int = 0   # 场景里给「选中区」配的碰撞层，关掉之后要按它恢复


func _ready() -> void:
	if is_instance_valid(select_area):
		_layer_when_on = select_area.collision_layer
	set_selected(false)
	set_clickable(false)   # 面板是收着的，先别挡射线


## 换一行字。text 是左边那句说明，price 是右边的价格（「3 枚」/「已满级」），
## state 只影响价格的颜色：买得起白色、买不起红色、满级灰色。
func update(text: String, price: String, state: State) -> void:
	if is_instance_valid(text_label):
		text_label.text = text
	if not is_instance_valid(price_label):
		return
	price_label.text = price
	match state:
		State.POOR:
			price_label.modulate = poor_color
		State.MAX:
			price_label.modulate = max_color
		_:
			price_label.modulate = Color.WHITE


## 准星扫到 / 扫开这一行。
func set_selected(on: bool) -> void:
	if is_instance_valid(highlight):
		highlight.visible = on


## 这一行现在能不能被准星扫中。面板收起时必须关掉，理由见文件头。
## 用 set_deferred：这是物理状态，在物理帧里直接改会被引擎拒绝。
func set_clickable(on: bool) -> void:
	if not is_instance_valid(select_area):
		return
	select_area.set_deferred("collision_layer", _layer_when_on if on else 0)
