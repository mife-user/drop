extends Node3D
class_name HeldItemController

## 单格随身道具：Node3D 与水枪同级，由水枪下的 RemoteTransform3D 同步手持变换。
## 使用后发出效果信号；文字只作说明，不会自动产生增益或减益。
signal inventory_changed
signal item_used(item_id: StringName, effect_text: String)

## 玩家水枪，装备道具时只设置独立的开火阻止标记，不覆盖菜单的 can_fire 状态。
@export var gun: WaterGun
## 水枪外观，切换装备时隐藏或显示。
@export var gun_model: Node3D
## 玩家，用于判断交互台是否锁定操作。
@export var player: Player
## 正面道具手持模型容器。
@export var positive_model: Node3D
## 负面道具手持模型容器。
@export var negative_model: Node3D
## 道具使用键，默认物理 F 键。
@export var use_key: Key = KEY_F

var held_item: StringName = &""
var effect_text: String = ""
var item_selected: bool = false

## 入树后同步固定模型的初始显示。
func _ready() -> void:
	_sync_equipment()

## 炮台购买与放置由原系统控制；每帧跟随其携带状态，不接管炮台滚轮。
func _process(_delta: float) -> void:
	_sync_equipment()

func has_item() -> bool:
	return not held_item.is_empty()

func turret_active() -> bool:
	return get_tree().get_first_node_in_group(&"interact_blocked") != null

func can_receive() -> bool:
	return not has_item() and not turret_active()

## 成功购买后立即选中道具；正面和负面共用一个位置。
func receive_item(id: StringName, description: String) -> bool:
	if not can_receive() or id not in [&"positive", &"negative"]:
		return false
	held_item = id
	effect_text = description
	item_selected = true
	_sync_equipment()
	inventory_changed.emit()
	return true

func controls_available() -> bool:
	return not turret_active() and (not is_instance_valid(player) or not player._move_locked)

func switch_equipment() -> void:
	if not has_item() or not controls_available():
		return
	item_selected = not item_selected
	_sync_equipment()

## 先清空持有状态再发送信号，避免效果回调重复消耗同一件道具。
func use_item() -> void:
	if not has_item() or not item_selected or not controls_available():
		return
	var used_id: StringName = held_item
	var used_text: String = effect_text
	held_item = &""
	effect_text = ""
	item_selected = false
	_sync_equipment()
	inventory_changed.emit()
	item_used.emit(used_id, used_text)

## 只处理游戏内未被界面消费的输入；菜单、鼠标释放及炮台携带时不抢输入。
func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not controls_available() or not has_item():
		return
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel != null and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		switch_equipment()
		get_viewport().set_input_as_handled()
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == use_key and item_selected:
		use_item()
		get_viewport().set_input_as_handled()

func _sync_equipment() -> void:
	var carrying: bool = turret_active()
	var show_item: bool = item_selected and has_item() and not carrying
	if is_instance_valid(positive_model):
		positive_model.visible = show_item and held_item == &"positive"
	if is_instance_valid(negative_model):
		negative_model.visible = show_item and held_item == &"negative"
	if is_instance_valid(gun_model):
		gun_model.visible = not show_item and not carrying
	if is_instance_valid(gun):
		gun.equipment_fire_blocked = show_item or carrying
		if is_instance_valid(gun.readout):
			gun.readout.visible = not show_item and not carrying
