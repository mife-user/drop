extends Node3D
class_name UpgradePanel

## 悬浮在水枪上方的那块升级面板 —— 是**世界空间**里的东西，不是 HUD，
## 所以它会跟着水枪、跟着你的视角转，而不是钉在屏幕上。
##
## 面板不管钱、也不管升级规则：文字由升级台算好了喂进来（update_row / set_money），
## 它只管「长什么样、哪一行被选中、什么时候出现、朝哪儿」。
##
## 面板默认是收着的：场景文件里它是亮着的（方便你在编辑器里摆位置、改字号），
## 运行时 _ready 会先把它收掉。open() / close() 会连两行的「选中区」一起开关。
##
## **朝向**：face_player 勾着时，面板每帧转向摄像机 —— 面板正面是 +Z（QuadMesh 正面朝 +Z），
## 所以用 use_model_front = true 的 look_at 正好对上。位置不动、只有朝向跟着你，
## 于是从哪边走过来都读得到，而转动视角时准星会在面板上移动（这是"看着选"的前提：
## 如果让它跟着视线转，准星就会永远钉在面板正中，选不了）。
## 取消勾选就固定成你在场景里摆好的朝向，"斜着悬浮"那种感觉。

## 两行选项。顺序和 UpgradeStation.Upgrade 一一对应：0 = 速度、1 = 大小。
@export var speed_row: UpgradeRow
@export var size_row: UpgradeRow
## 左下角那行「邮币 x N」。
@export var money_label: Label3D
## 中间那行临时提示（「邮币不足」「升级成功」），平时不显示。
@export var message_label: Label3D
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

var _open: bool = false
var _selected: int = -1        # 准星当前扫到第几行，-1 = 没扫到
var _message_tween: Tween


func _ready() -> void:
	close()


func _physics_process(_delta: float) -> void:
	if not _open or not face_player:
		return
	_face_camera()


func is_open() -> bool:
	return _open


## 展开面板：显示自己，并把两行的「选中区」打开，让准星能扫到。
func open() -> void:
	if _open:
		return
	_open = true
	show()
	_set_rows_clickable(true)
	_face_camera()   # 展开的这一瞬间先摆正，别一边出现一边转


## 收起面板：连「选中区」一起关掉，免得一块看不见的判定框继续挡在射线中间。
func close() -> void:
	_open = false
	_selected = -1
	_apply_selection()
	_set_rows_clickable(false)
	_clear_message()
	hide()


## 换掉某一行的文字。index：0 = 速度、1 = 大小。
func update_row(index: int, text: String, price: String, state: UpgradeRow.State) -> void:
	var row: UpgradeRow = _row(index)
	if is_instance_valid(row):
		row.update(text, price, state)


## 左下角「邮币 x N」。
func set_money(amount: int) -> void:
	if is_instance_valid(money_label):
		money_label.text = "邮币 x %d" % amount


## 准星扫到的是哪一行（-1 = 没扫到）。collider 是射线打到的那个物体；
## 面板收着的时候一律返回 -1 —— 那时选中区本来也是关的，这只是多一层保险。
func row_index_of(collider: Object) -> int:
	if not _open or collider == null:
		return -1
	for index: int in 2:
		var row: UpgradeRow = _row(index)
		if is_instance_valid(row) and is_instance_valid(row.select_area) and row.select_area == collider:
			return index
	return -1


## 高亮第 index 行（-1 = 全部熄掉）。
func set_selected(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_apply_selection()


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


## 把面板转到正对摄像机。位置不动，只改朝向。
func _face_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	# 贴脸时 look_at 会因为"目标正好在正上/正下"翻掉，索性不转
	if global_position.distance_squared_to(eye) < 0.04:
		return
	look_at(eye, Vector3.UP, true)   # use_model_front：让 +Z（面板正面）朝向摄像机


func _row(index: int) -> UpgradeRow:
	return speed_row if index == 0 else size_row


func _apply_selection() -> void:
	for index: int in 2:
		var row: UpgradeRow = _row(index)
		if is_instance_valid(row):
			row.set_selected(index == _selected)


func _set_rows_clickable(on: bool) -> void:
	for index: int in 2:
		var row: UpgradeRow = _row(index)
		if is_instance_valid(row):
			row.set_clickable(on)


func _clear_message() -> void:
	if is_instance_valid(_message_tween):
		_message_tween.kill()
	if is_instance_valid(message_label):
		message_label.hide()
