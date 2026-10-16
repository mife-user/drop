extends WaterGun
class_name WaterTurret

## 自动炮台：**买下来先「拿在手上」，左键放到地上才开始自动喷水，水箱见底就自己消失。**
##
## 它是「一座不用人操作的水枪」，所以直接继承 WaterGun，白拿一大堆：
## 发射间隔的冷却循环、一发水多大（blob_size）、整个水箱（capacity / amount / has_water() /
## shot_volume() / fill()）、上方那块水量读数、以及抛物线反解（_ballistic_direction）。
## **这里只覆盖父类不会的三件事**：
##
##   `_is_firing()`        改成「放下之后就一直想开火」——不认按键、不认鼠标锁定；
##   `_launch_direction()` 改成朝**自己正前方 launch_distance 米的落点**解抛物线 ——
##                         不认摄像机、不认准星，所以转一下炮台就换了它往哪儿浇；
##   `_physics_process()`  多看一眼水箱：`has_water()` 变 false 就收缩消失 ——
##                         这是它和水枪唯一的区别（水枪打空了只是不出水，不会消失）。
##
## **携带期间（买下来、还没放下）它不喷水、不挡人、半透明**，脚下还有一圈投影告诉你
## 它会被放在哪儿。投影是**从炮台正下方打一条射线**找地面得来的：射线打不到地面、
## 或者落点压着「吸水区」（水池、木碗，第 4 层）都不许放 —— 投影变红、左键点了没反应。
## 放置**不能取消**：拿在手上就必须找个地方放下。
##
## 水和水枪走同一个「水块容器」，共用 muzzle_speed 和重力：别处把出水速度买上去，
## 炮台的落点照样不变（每发都按当前初速现解一次抛物线），只是弧线变平。
##
## **枪口（muzzle）要摆在碰撞盒外面** —— 摆在模型炮管尖上就对了。摆在盒子里的话，
## 水一出膛就撞在自己身上散掉：水团打射线只认「世界」层，认不出这是它自己的炮台。
##
## 节点结构见 scenes/炮台发射器.tscn：模型 / 枪口 / 实体 / 读数 / 投影。

## 和交互菜单的「确认」是同一个键（鼠标左键）。项目设置里没有这个动作时退回鼠标左键。
const PLACE_ACTION: StringName = &"select"

## 「这会儿先别开菜单」组：拿在手上时把自己挂进去，全场台座按 E 都不弹菜单 ——
## 那会儿左键是「放置」，弹出菜单的话点选项和放炮台会打起来。
## 名字要和 scripts/交互框/交互台.gd 里的 GROUP_BLOCK_INTERACT 一致。
const GROUP_BLOCK_INTERACT: StringName = &"interact_blocked"

## 「玩家」组，用来把玩家自己排除在放置射线之外 —— 不然低头时投影会落在自己头上。
## 名字要和 scripts/人物/player.gd 里的 GROUP 一致。
const GROUP_PLAYER: StringName = &"player"
## 「准星」组，携带时在屏幕中心那行字上报「能不能放」。
## 名字要和 scripts/交互框/交互准星.gd 里的 GROUP 一致。
const GROUP_CROSSHAIR: StringName = &"interact_crosshair"

## 放好了（左键落地那一刻发一次）。商店接它把玩家的水枪还回来、重算菜单。
signal placed

@export_group("接线")
## 炮台模型（炮台.glb 的实例）。携带时给它套一层半透明材质，放下时还原。
@export var model: Node3D
## 自己的碰撞体。携带期间关掉，免得它一路顶着玩家走。
@export var body: CollisionObject3D
## 脚下那圈落点提示。携带时按「能不能放」换颜色。
@export var shadow: MeshInstance3D

@export_group("发射")
## 落点离自己多远（米）：从枪口朝**自己正前方**这么多米处的地面解抛物线。
## 炮台的前方 = 它自己节点的 -Z（Godot 里蓝色箭头指的那条）；模型转反了就在编辑器里转模型。
@export_range(0.5, 30.0, 0.5) var launch_distance: float = 4.0
## 落点比枪口低多少米。**调到"水正好落在地面上"为止** —— 枪口越高这个值越大。
@export_range(0.0, 10.0, 0.1) var launch_drop: float = 1.0
## 水喷完之后收缩消失用多久（秒）。填 0 = 立刻消失。
@export_range(0.0, 2.0, 0.05) var dry_shrink_time: float = 0.35

@export_group("携带与放置")
## 拿在手上时悬在摄像机前方多少米。
@export_range(0.8, 8.0, 0.1) var hold_distance: float = 2.5
## 拿在手上时比摄像机低多少米（压低一点，别正好糊在屏幕中心）。
@export_range(0.0, 3.0, 0.05) var hold_drop: float = 0.6
## 放置预览时滚轮每格旋转多少度；绕炮台自身中心的世界竖直轴旋转，放下后不再响应。
@export_range(1.0, 90.0, 1.0) var placement_rotation_step: float = 15.0
## 往下打多远的射线找地面（米）。打不到就不许放。
@export_range(0.5, 40.0, 0.5) var ground_probe: float = 10.0
## 找地面查哪些层。默认第 1 层（世界）。
@export_flags_3d_physics var ground_mask: int = 1
## 落点周围这么一大块里压着「吸水区」就不许放（米，半径）。填 0 = 不检查。
@export_range(0.0, 2.0, 0.05) var forbid_radius: float = 0.35
## 「吸水区」在第几层。默认第 4 层（水池、木碗下面那些吸水区）。
@export_flags_3d_physics var forbid_mask: int = 8
## 携带中的模型套什么颜色（半透明预览）；放下去就恢复成模型本来的样子。
@export var preview_color: Color = Color(0.55, 0.85, 1.0, 0.42)
## 能放时投影圈的颜色。
@export var shadow_ok_color: Color = Color(0.372549, 0.827451, 0.952941, 0.75)
## 不能放（底下没地面 / 压着水池）时投影圈的颜色。
@export var shadow_bad_color: Color = Color(1.0, 0.45, 0.42, 0.75)
## 投影圈贴地时抬多高（米），免得和地面打架闪烁。
@export_range(0.0, 0.2, 0.005) var shadow_lift: float = 0.02

@export_group("携带时的话术")
## 能放时准星下面那行字。
@export var hint_carry: String = "滚轮旋转，左键放置炮台"
## 不能放时那行字。
@export var hint_blocked: String = "这里不能放"

## 现在是不是「拿在手上」（还没放下）。商店靠它判断还能不能再卖一座。
var carrying: bool = false
var _placement_yaw_offset: float = 0.0  # 滚轮相对视线累积的水平旋转角（弧度）
var _carry_view_yaw: float = 0.0        # 视线竖直时沿用上一次水平朝向

var _ground_found: bool = false        # 底下找着地面了吗
var _shadow_valid: bool = false        # 这会儿能不能放（有地面、而且不压着水池）
var _ground_point: Vector3 = Vector3.ZERO   # 落点（射线打到的那个地面点）
var _drying: bool = false              # 正在收缩消失，别重复触发
var _body_layer: int = 1               # 实体在场景里配的碰撞层，只是借出去再还回来
var _crosshair: InteractCrosshair
var _preview_material: StandardMaterial3D
var _overrides: Dictionary = {}        # 零件 → 它原本的 material_override，放下时还回去
var _ring_material: StandardMaterial3D
var _forbid_probe: SphereShape3D       # 判「压着水池没有」用的探测球，复用同一个


func _ready() -> void:
	super()   # !!! 父类：满水开局（amount = capacity）+ 刷一遍读数
	if is_instance_valid(body):
		_body_layer = body.collision_layer
	_prepare_shadow()
	_crosshair = get_tree().get_first_node_in_group(GROUP_CROSSHAIR) as InteractCrosshair
	if is_instance_valid(shadow):
		shadow.hide()   # 场景里它是亮着的（方便在编辑器里摆位置），运行时先收掉


## 携带中每帧摆位置，其余时间只盯着水箱。
##
## 和父类那条流程的区别就在这几行：**先看水箱见底没有**（见底 = 这座炮台的任务结束），
## 再交给父类的「冷却 + 到点开火」。
func _physics_process(delta: float) -> void:
	if carrying:
		_update_carry(delta)
		return
	if _drying:
		return
	if not has_water():
		_dry_up()
		return
	super(delta)


# —— 携带与放置（商店买下来之后由它调 begin_carry，左键放下）——


## 由商店调用：把这座炮台拿在手上 —— 不喷水、不挡人、半透明、跟着摄像机走。
func begin_carry() -> void:
	if carrying:
		return
	carrying = true
	_placement_yaw_offset = 0.0
	_carry_view_yaw = global_rotation.y
	add_to_group(GROUP_BLOCK_INTERACT)   # 全场台座先别开菜单，理由见常量那段
	_set_body_active(false)
	_apply_preview(true)
	if is_instance_valid(shadow):
		shadow.show()
	if is_instance_valid(readout):
		readout.hide()   # 半透明的幽灵炮台上挂个实心数字很怪
	_update_carry(0.0)   # 立刻摆到位，别在商店那儿闪一帧


## 左键放下：按到落点上、竖直站好，从这里开始自动喷水。
## 落点不能放（_shadow_valid 为假）时什么都不做 —— 准星下面那行字已经写着「这里不能放」了。
func place() -> void:
	if not carrying or not _shadow_valid:
		return
	carrying = false
	remove_from_group(GROUP_BLOCK_INTERACT)
	global_position = _ground_point
	global_rotation = Vector3(0.0, global_rotation.y, 0.0)   # 保留预览朝向，始终绕世界竖直轴站立
	_set_body_active(true)
	_apply_preview(false)
	if is_instance_valid(shadow):
		shadow.hide()
	if is_instance_valid(readout):
		readout.show()
	if is_instance_valid(_crosshair):
		_crosshair.set_hint("", self)
	placed.emit()


## 左键放下。用事件而不是每帧问 Input，是为了「按一下只算一次」，
## 而且能把这一下**吃掉**，不让它再落到菜单或开火上。
func _unhandled_input(event: InputEvent) -> void:
	if not carrying:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return   # 光标被放出来了（按过 Esc）：这一下左键留给「点画面重新锁定鼠标」
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel != null and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction: float = 1.0 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		var ticks: float = absf(wheel.factor) if not is_zero_approx(wheel.factor) else 1.0
		var angle: float = deg_to_rad(placement_rotation_step) * direction * ticks
		_placement_yaw_offset = wrapf(_placement_yaw_offset + angle, -PI, PI)
		global_rotation = Vector3(0.0, _carry_view_yaw + _placement_yaw_offset, 0.0)
		get_viewport().set_input_as_handled()
		return
	if not _is_place_pressed(event):
		return
	get_viewport().set_input_as_handled()
	place()   # 落点不允许时 place() 自己会不理，但这一下左键仍然归我们


## 这一下事件是不是「按下放置键」。项目设置里没有这个动作时退回鼠标左键。
func _is_place_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(PLACE_ACTION):
		return event.is_action_pressed(PLACE_ACTION)
	var click: InputEventMouseButton = event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT


## 携带中每帧：跟着摄像机摆位置和朝向，再更新脚下的投影。
##
## **位置跟着视线走**（悬在眼前，不是你手上），所以站着不动只转头，就能把它挪到脚边、
## 屋顶上、水池对岸。**朝向只取水平那一段**：抬头低头时炮台不会跟着翻，永远立着。
func _update_carry(_delta: float) -> void:
	var cam: Camera3D = _camera()
	if cam == null:
		return
	var forward: Vector3 = -cam.global_basis.z
	global_position = cam.global_position + forward * hold_distance - Vector3.UP * hold_drop
	# 让节点的 -Z（炮台的前方）对准视线的水平方向；公式和 player.gd 的 lock_look 是同一个
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() > 0.0001:
		_carry_view_yaw = atan2(-flat.x, -flat.z)
	# 滚轮只改变朝向，不挪动中心；每帧保留偏转，避免被跟随视线的逻辑覆盖。
	global_rotation = Vector3(0.0, _carry_view_yaw + _placement_yaw_offset, 0.0)
	_update_shadow()


## 从正下方打一条射线找地面，把投影圈摆上去，并判断这儿能不能放。
func _update_shadow() -> void:
	_ground_found = _probe_ground()
	_shadow_valid = _ground_found and not _blocked_at(_ground_point)
	if is_instance_valid(shadow):
		shadow.visible = _ground_found   # 底下是空的（对着天、对着深渊）：投影先收起来
		if _ground_found:
			shadow.global_position = _ground_point + Vector3.UP * shadow_lift
		if is_instance_valid(_ring_material):
			_ring_material.albedo_color = shadow_ok_color if _shadow_valid else shadow_bad_color
	if is_instance_valid(_crosshair):
		_crosshair.set_hint(hint_carry if _shadow_valid else hint_blocked, self)


## 往下打一条射线找地面。找着了把落点写进 _ground_point 并返回 true。
func _probe_ground() -> bool:
	var from: Vector3 = global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * ground_probe, ground_mask)
	var stander: CollisionObject3D = get_tree().get_first_node_in_group(GROUP_PLAYER) as CollisionObject3D
	if is_instance_valid(stander):
		query.exclude.append(stander.get_rid())   # 别把玩家自己的头顶当成地面
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	_ground_point = hit.position
	return true


## 落点这块地方是不是「不许放」的（默认：压着水池 / 木碗下面的吸水区）。
## 用一个小球去探而不是打点：站在池边往下看时，落点常常正好在沿上，点判定会漏掉。
func _blocked_at(point: Vector3) -> bool:
	if forbid_radius <= 0.0 or forbid_mask == 0:
		return false
	if _forbid_probe == null:
		_forbid_probe = SphereShape3D.new()
	_forbid_probe.radius = forbid_radius
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = _forbid_probe
	params.transform = Transform3D(Basis(), point)
	params.collision_mask = forbid_mask
	params.collide_with_areas = true    # 吸水区是 Area3D
	params.collide_with_bodies = false  # 地面本身不算数
	return not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


# —— 自动发射（覆盖父类那三处）——


## 自动发射：放下之后就**一直想开火**（父类那圈冷却会按住 fire_interval 限速），
## 拿在手上时当然不喷 —— 这是买之前特意叮嘱的那一条。
## 父类原本是「按住左键 + 鼠标锁着」才喷，炮台没有手，整套换成这一句。
func _is_firing() -> bool:
	return not carrying and can_fire and has_water()


## 朝自己正前方 launch_distance 米、再往下 launch_drop 米那个点解抛物线。
## 用父类的 _ballistic_direction()，和玩家水枪是同一套反解 —— 所以改初速、改重力都能自适应。
func _launch_direction(_cam: Camera3D, from: Vector3) -> Vector3:
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.DOWN   # 炮台被竖起来了（不该发生）：朝下打，好歹别射到天上
	forward = forward.normalized()
	var target: Vector3 = from + forward * launch_distance - Vector3.UP * launch_drop
	if not is_instance_valid(field):
		return (target - from).normalized()   # 正常走不到：父类的 _fire() 已经挡过一道
	return _ballistic_direction(from, target, field.muzzle_speed, field.gravity)


## 水箱见底：这一座的任务结束了，收缩消失。
## 先把碰撞和「别开菜单」两件事退掉 —— 消失过程中不该再挡路、也不该再拦着玩家按 E。
func _dry_up() -> void:
	if _drying:
		return
	_drying = true
	remove_from_group(GROUP_BLOCK_INTERACT)
	_set_body_active(false)
	if is_instance_valid(shadow):
		shadow.hide()
	if is_instance_valid(readout):
		readout.hide()
	if dry_shrink_time <= 0.0:
		queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, dry_shrink_time)
	tween.tween_callback(queue_free)


# —— 自己的小工具 ——


## 开关自己的碰撞：携带期间和消失过程中都关掉。
## 用 set_deferred：这个开关会在物理帧里被拨动，直接改会被引擎拒绝。
func _set_body_active(on: bool) -> void:
	if is_instance_valid(body):
		body.set_deferred("collision_layer", _body_layer if on else 0)


## 把投影圈自己那份材质抢出来：场景里的网格和材质是**所有炮台共用的**，
## 不复制的话「这一座投影变红」会把场上别的炮台一起染红
## （水块.gd 复制一份碰撞形状，是同一个道理）。
func _prepare_shadow() -> void:
	if not is_instance_valid(shadow) or not (shadow.mesh is PrimitiveMesh):
		return
	# duplicate() 的静态类型是 Resource，赋回 Mesh / Material 这些属性要显式转一下
	var ring: PrimitiveMesh = (shadow.mesh as PrimitiveMesh).duplicate() as PrimitiveMesh
	var look: Material = ring.material
	if look == null:
		return
	ring.material = look.duplicate() as Material
	shadow.mesh = ring
	_ring_material = ring.material as StandardMaterial3D


## 携带时给模型套一层半透明材质（「还没放下」的预览），放下时还回原样。
## 记下原来的 material_override 再还回去，而不是一律清成 null —— 万一以后有人在场景里
## 给模型配过材质覆盖，这里不会把它抹掉。
func _apply_preview(on: bool) -> void:
	if not is_instance_valid(model):
		return
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var piece: MeshInstance3D = node as MeshInstance3D
		if piece == null:
			continue
		if on:
			if not _overrides.has(piece):
				_overrides[piece] = piece.material_override
			piece.material_override = _make_preview_material()
		elif _overrides.has(piece):
			piece.material_override = _overrides[piece] as Material


## 预览材质只造一次，所有零件共用同一份（它们是同一座炮台，颜色永远一样）。
## 想改观感就改上面那个 preview_color；「不受光、纯色」是故意的 —— 一眼能看出这不是实体。
## **函数名不能叫 _preview_material** —— 上面那个变量就叫这个名字，同一个类里变量和函数重名
## GDScript 会直接报错（整个脚本编译不过，表现是别的脚本说「找不到 WaterTurret 这个类」）。
func _make_preview_material() -> StandardMaterial3D:
	if _preview_material == null:
		_preview_material = StandardMaterial3D.new()
		_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview_material.albedo_color = preview_color
	return _preview_material
