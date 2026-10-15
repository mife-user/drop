extends Node3D
class_name InteractPanel

## 可交互物体的悬浮菜单 —— 是**世界空间**里的一块面板，不是 HUD，
## 所以它会跟着物体、跟着你的视角转，而不是钉在屏幕上。
##
## 它不认识钱、也不认识升级规则：每一行显示什么由外面算好了喂进来（update_row），
## 它只管「长什么样、哪一项被选中、什么时候出现、朝哪儿」，以及把「准星扫到了什么」
## 报回去（hit_test）。
##
## **行 = 本节点下直接挂的「交互选项行」子节点**，从上到下就是第 0、1、2 行 ——
## 有几行是摆出来的、不是写死的，想加一行就再实例一个。
##
## 面板默认收着：场景里它是亮着的（方便你在编辑器里摆位置、改字号），运行时 _ready 会先收掉。
## open() / close() 会连所有「选中区」和 × 的碰撞一起开关，理由见 交互选项行.gd 的文件头。
##
## **朝向**：face_player 勾着时每帧转向摄像机（面板正面是 +Z，用 use_model_front 的 look_at
## 正好对上）。位置不动、只有朝向跟着你，所以转动视角时准星会在面板上移动 ——
## 这是「看着选」的前提：如果让面板跟着视线转，准星就永远钉在面板正中了，选不了。

## 准星没扫到面板上的任何东西。
const HIT_NONE: int = -1
## 准星扫到了右上角的 ×。
const HIT_CLOSE: int = -2

## 「标题」那行字（也可以由外面用 set_title 改）。
@export var title_label: Label3D
## 底部那行字（比如「邮币 x 3」），内容为空时整行隐藏。
@export var footer_label: Label3D
## 中间那行临时提示（「邮币不足」「升级成功」），平时不显示。
@export var message_label: Label3D
## 右上角的 ×。
@export var close_label: Label3D
## × 的选中区（Area3D）。
@export var close_area: Area3D
## 底板（那块深色半透明的背景板）。行数变了它会自己伸缩，别在代码里另存一份尺寸。
@export var back: MeshInstance3D

@export_group("排版")
## 提示那行离最后一行多远（米）。
@export_range(0.0, 1.0, 0.005) var message_gap: float = 0.115
## 底部那行（邮币）离最后一行多远（米）。
@export_range(0.0, 1.0, 0.005) var footer_gap: float = 0.21
## 底板下沿离底部那行留多少（米）。
@export_range(0.0, 0.5, 0.005) var back_bottom_margin: float = 0.045
## 勾上 = 每帧转向玩家；取消 = 固定成场景里摆好的朝向。
@export var face_player: bool = true
## 临时提示停留多久（秒）才开始淡出。
@export_range(0.2, 10.0, 0.1) var message_time: float = 1.4
## 临时提示淡出时长（秒）。
@export_range(0.0, 2.0, 0.05) var message_fade: float = 0.35
## 成功提示的颜色。
@export var ok_color: Color = Color(0.37, 0.83, 0.95)
## 失败提示的颜色。
@export var fail_color: Color = Color(1.0, 0.45, 0.42)
## × 被准星扫到时变成的颜色。
@export var close_highlight: Color = Color(0.37, 0.83, 0.95)

var _rows: Array[InteractOptionRow] = []
var _open: bool = false
var _hit: int = HIT_NONE
var _row_count: int = 0
var _message_tween: Tween
var _close_base_color: Color = Color.WHITE
var _close_layer_when_on: int = 0
var _back_base_height: float = 1.0   # 场景里那块底板的原始高度，伸缩时按它换算
var _back_top: float = 0.0           # 底板顶边的高度（场景里钉死的，不随行数变）


func _ready() -> void:
	for child: Node in get_children():
		if child is InteractOptionRow:
			_rows.append(child as InteractOptionRow)
	if is_instance_valid(close_label):
		_close_base_color = close_label.modulate
	if is_instance_valid(close_area):
		_close_layer_when_on = close_area.collision_layer
	if is_instance_valid(back):
		_back_base_height = (back.mesh as QuadMesh).size.y if back.mesh is QuadMesh else 1.0
		_back_top = back.position.y + _back_base_height * 0.5   # 底板顶边钉死在场景里摆的位置
	_row_count = _rows.size()   # 单独打开这个场景看时，把摆出来的行都显示出来
	_layout()
	close()


func _physics_process(_delta: float) -> void:
	if not _open or not face_player:
		return
	_face_camera()


## 菜单现在是展开着的吗。
func is_open() -> bool:
	return _open


## 这次要用几行。场景里多摆的行会被藏起来、也不参与命中判定，底板跟着伸缩到刚好包住。
func set_row_count(count: int) -> void:
	_row_count = clampi(count, 0, _rows.size())
	for index: int in _rows.size():
		_rows[index].visible = index < _row_count
	_layout()


## 展开菜单：显示自己，并把所有「选中区」打开，让准星能扫到。
func open() -> void:
	if _open:
		return
	_open = true
	show()
	_set_clickable(true)
	_face_camera()   # 展开的这一瞬间先摆正，别一边出现一边转
	_clear_message()


## 收起菜单：连「选中区」一起关掉，免得一块看不见的判定框继续挡在射线中间。
func close() -> void:
	_open = false
	_hit = HIT_NONE
	_apply_hit()
	_set_clickable(false)
	_clear_message()
	hide()


## 准星扫到的是哪一项：>= 0 = 第几行，HIT_CLOSE = ×，HIT_NONE = 没扫到。
## collider 是射线打到的那个物体；菜单收着时一律返回 HIT_NONE。
func hit_test(collider: Object) -> int:
	if not _open or collider == null:
		return HIT_NONE
	if is_instance_valid(close_area) and collider == close_area:
		return HIT_CLOSE
	for index: int in _row_count:
		var row: InteractOptionRow = _rows[index]
		if is_instance_valid(row.select_area) and row.select_area == collider:
			return index
	return HIT_NONE


## 高亮准星扫到的那一项，别的都熄掉。
func set_hit(hit: int) -> void:
	if hit == _hit:
		return
	_hit = hit
	_apply_hit()


## 换标题。
func set_title(text: String) -> void:
	if is_instance_valid(title_label):
		title_label.text = text


## 换底部那行；传空字符串就整行隐藏。
func set_footer(text: String) -> void:
	if not is_instance_valid(footer_label):
		return
	footer_label.text = text
	footer_label.visible = not text.is_empty()


## 换掉某一行的文字。index：0 = 第一行，往下顺延。
func update_row(index: int, text: String, price: String, state: InteractOptionRow.State) -> void:
	if index < 0 or index >= _row_count:
		return
	_rows[index].update(text, price, state)


## 弹一句临时提示（「邮币不足」「升级成功」），停一会儿自己淡掉。
## 重复调用会掐掉上一条重新计时，不会叠成两句。
func show_message(text: String, ok: bool) -> void:
	if not is_instance_valid(message_label):
		return
	if is_instance_valid(_message_tween):
		_message_tween.kill()
	message_label.text = text
	message_label.modulate = ok_color if ok else fail_color
	message_label.show()
	_message_tween = create_tween()
	_message_tween.tween_interval(message_time)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, maxf(message_fade, 0.01))
	_message_tween.tween_callback(message_label.hide)


## 按实际显示的行数，把「提示」「底部」「底板」排好。
##
## **行本身的位置不动** —— 那几行是你在编辑器里摆的，想怎么放怎么放（间距不一样也行）；
## 这里只跟着最后一行往下排下面那两行字，再把底板伸缩到刚好包住它们。
## 所以 1 行的贩卖机、3 行的合成台共用同一个面板场景，谁都不用手调：
## 台座说自己有几行（row_count），多余的自动藏，底板自动缩。
func _layout() -> void:
	if _row_count <= 0:
		return
	var last_y: float = _rows[_row_count - 1].position.y
	var message_y: float = last_y - message_gap
	var footer_y: float = last_y - footer_gap
	if is_instance_valid(message_label):
		message_label.position.y = message_y
	if is_instance_valid(footer_label):
		footer_label.position.y = footer_y
	if not is_instance_valid(back):
		return
	# 底板顶边钉死在场景里摆好的位置，只往下长：高度用缩放做，中心跟着挪到中线上。
	# 缩放不会改到 QuadMesh 这个子资源本身，所以多个面板实例之间不会互相串。
	var bottom: float = footer_y - back_bottom_margin
	var height: float = maxf(_back_top - bottom, 0.05)
	back.scale.y = height / maxf(_back_base_height, 0.001)
	back.position.y = (_back_top + bottom) * 0.5


## 把面板转到正对摄像机。位置不动，只改朝向。
func _face_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	# 贴脸时 look_at 会因为「目标正好在正上/正下」翻掉，索性不转
	if global_position.distance_squared_to(eye) < 0.04:
		return
	look_at(eye, Vector3.UP, true)   # use_model_front：让 +Z（面板正面）朝向摄像机


func _apply_hit() -> void:
	for index: int in _rows.size():
		_rows[index].set_selected(index == _hit)
	if is_instance_valid(close_label):
		close_label.modulate = close_highlight if _hit == HIT_CLOSE else _close_base_color


func _set_clickable(on: bool) -> void:
	for row: InteractOptionRow in _rows:
		row.set_clickable(on)
	if is_instance_valid(close_area):
		close_area.set_deferred("collision_layer", _close_layer_when_on if on else 0)


func _clear_message() -> void:
	if is_instance_valid(_message_tween):
		_message_tween.kill()
	if is_instance_valid(message_label):
		message_label.hide()
