extends Area3D
class_name WaterBlob

## 一团水：按下开火时沿视线抛出，之后只受重力，走一条真的抛物线，落地后静止不动。
##
## 落地的判定写死在这里：每帧从上一帧位置到当前位置打一条射线，
## 命中面法线够竖直（>= ground_normal_y）才算「地面」，水就贴上去落地；
## 撞在墙面、屋顶、围栏这类斜面上则直接消失 —— 抛物线会拱起来，这是「拱进屋顶」的归宿。
##
## 落地后的归宿只有两种：
##   1) 与「水种相同、大小差不多、且表面间距小于 merge_gap」的另一团水合并 —— 边长乘 grow_factor；
##   2) 到 lifetime 秒后自己收缩消失。
## 合并只在「落地」和「刚被合并生成」这两个时刻各扫一次邻居：水落地后就不再移动，
## 「谁在谁旁边」那一刻就定死了。所以不需要每帧检测，也不会出现两团水互相追着合并的抖动。
##
## 这团水没有「等级」，身份就是它的边长 size：判等看 size 的相对差、到顶看 size >= max_size。
## 这样多把不同大小的水枪射出的水，也能正确地按「谁跟谁一样大」来合。
## 水种 water_type 默认是射出它的预制件场景路径 —— 换了水模型，新旧两种水不会混在一起。
##
## 水量（volume）是 size 的立方，**绝对体积、不跟着水枪走**：
## 水枪升级后射出的水更大，一发灌进水池的水量就真的更多，填满同样容积需要的发数自动变少。
##
## 所有合并规则（grow_factor / max_size / merge_gap / merge_size_tolerance）
## 都由「水块容器」在生成时写进来，要调参去那边调，不用改这个文件。
##
## 本脚本完全不认识水池、消防栓、水带。「谁想吸收这团水」由对方的 Area3D 按
## 「水」碰撞层来找（见 scripts/吸水区.gd），所以以后在哪儿摆吸水区、
## 把水换成什么样式，都不用回来改这里。


## 消失前的收缩时长（秒）；填 0 就是到点直接消失。
@export_range(0.0, 2.0, 0.05) var shrink_time: float = 0.25
## 合并生成的新水团从多少倍大小涨到满尺寸，做一点「融进去」的观感；填 1 关闭。
@export_range(0.3, 1.0, 0.01) var spawn_growth: float = 0.72
## 落地后是否随机绕竖直轴转一下，让水洼看起来不那么整齐。
@export var random_yaw: bool = true
## 命中面法线的竖直分量要大于这个值才算「地面」，水才会落地；
## 否则算撞在墙面 / 屋顶 / 围栏上，水花散掉、直接消失。
## 1.0 = 只有完全水平的面算地面；调小则斜坡、缓屋顶也算落地。
@export_range(0.0, 1.0, 0.01) var ground_normal_y: float = 0.9
## 空中飞行的最长时间（秒），到点直接消失，防止有水飞到天边外再也不回来。
@export_range(0.5, 30.0, 0.5) var flight_timeout: float = 6.0
## 视觉子节点；尺寸变化时按 size / model_size 缩放它。
@export var visual: Node3D
## 视觉模型自身的原始边长（米）。当前是 1 米的立方体所以填 1；
## 换成别的模型（比如直径 2 米的水球）就填 2，运行时的 size 会自动缩放到正确大小。
## **填 0 表示自动量取** —— 按视觉子树里所有网格的合并包围盒取最长边，换新模型时不用手算。
@export_range(0.0, 100.0, 0.001) var model_size: float = 1.0

## 当前边长（米）。刚射出来时等于水枪的 blob_size，之后每合并一次乘 grow_factor。
## 它就是这团水的身份：能不能跟别人合、有没有到顶、值多少水，全看它。
var size: float = 0.35
## 这团水的体积（立方米），就是 size 的立方；吸水区按这个累加水量。
## 是**绝对体积**，不带任何「相当于几发基础水」的换算 —— 所以水枪升级之后，
## 每发的体积真的变大，填满同样容积的水池需要的发数会自动变少。
var volume: float = 0.0
## 水种标识，由「水块容器」在生成时写入，默认是射出它的预制件场景路径。
## 只有标识相同的两团水才会合并 —— 以后换了水模型，新旧两种水不会混在一起。
var water_type: String = ""
## 落地后存活多少秒，到点收缩消失，由「水块容器」写入。
var lifetime: float = 8.0
## 每次合并的边长倍率，由「水块容器」写入。
var grow_factor: float = 1.26
## 边长达到这个值（米）就不再合并，由「水块容器」写入。
var max_size: float = 1.5
## 两团水的表面间距小于这个值（米）就合并，由「水块容器」写入。
var merge_gap: float = 0.35
## 判定两团水「一样大」的相对容差，由「水块容器」写入。
var merge_size_tolerance: float = 0.05
## 是否已经落地静止。
var landed: bool = false
## 出膛速度向量（米/秒），由「水块容器」按视线方向和初速算好后写入。
## 出膛之后只剩 gravity 在改它，所以这条轨迹是货真价实的抛物线。
var velocity: Vector3 = Vector3.ZERO
## 下落用的重力加速度（米/秒²），由「水块容器」写入。
## 水团是自己积分运动方程的，用的是这个值，和项目的物理重力无关。
## 名字不能叫 gravity —— Area3D 自带一个同名的属性（区域重力覆盖），撞名会让这个成员整个解析不到。
var fall_gravity: float = 9.8
## 飞行途中打射线用的碰撞层掩码，由「水块容器」写入。
var collide_mask: int = 1
## 飞行途中打射线要忽略的碰撞体 RID（通常就是主人公自己），由「水块容器」写入。
var ray_exclude: Array[RID] = []
## 生出这团水的「水块容器」，合并时用它造更大的水团。
var field: WaterField

## 合并生成后的「长大」动画所用时长（秒）；不值得单独做成参数。
const _GROW_TIME: float = 0.18
## 被吸水区吸收时的收缩时长（秒）。
const _ABSORB_FADE: float = 0.12

var _flight_left: float = 0.0         # 空中飞行的剩余时间上限
var _life_left: float = 0.0           # 落地后的剩余存活时间
var _shrink: float = 0.25             # 实际生效的收缩时长，_ready 时按 lifetime 夹一次
var _fade_left: float = 0.0           # 收缩消失剩余时间
var _visual_boost: float = 1.0        # 合并生成时的额外缩放，会自己涨回 1
var _spent: bool = false              # 已被合并或吸收，等销毁
var _fading: bool = false             # 正在收缩消失，期间不参与合并
var _shape: CollisionShape3D
var _probe: SphereShape3D


func _ready() -> void:
	add_to_group("water")
	# 除了落地那一刻主动扫，也接住物理引擎报上来的重叠。两者互补：
	# 主动扫能立刻发现「已经在旁边但物理还没登记」的邻居，
	# 信号能发现「同一帧里生成、彼此还没互相扫过」的两团水（连成一片时会出现）。
	area_entered.connect(_check_neighbors)
	_resolve_visual()
	_shape = $CollisionShape3D
	# 复制一份形状：多个水团共用同一个子资源的话，改半径会互相带偏
	var shape: Shape3D = _shape.shape
	if shape != null:
		_probe = shape.duplicate() as SphereShape3D
		_shape.shape = _probe
	_life_left = lifetime
	_flight_left = flight_timeout
	_shrink = clampf(shrink_time, 0.0, lifetime * 0.9)
	_apply_size()


## 确认视觉子节点可用，并在需要时自动量取模型大小。
## 新样式如果删掉或改名了 Visual 节点，visual 引用会断掉，表现是「水块合并明明变大了、
## 视觉却纹丝不动」，查起来很费劲 —— 所以这里兜底找一次，找不到就明确警告而不是静默失效。
func _resolve_visual() -> void:
	if not is_instance_valid(visual):
		visual = get_node_or_null("Visual")
	if not is_instance_valid(visual):
		push_warning("水块：visual 没指定、也找不到名为 Visual 的子节点，尺寸变化不会反映到视觉上")
		return
	if model_size <= 0.0:
		model_size = _measure_visual()


## 量出视觉子树里所有网格的合并包围盒，取最长边当模型基准边长。
## 换算到 visual 自己的坐标系里再量，这样嵌在 glb 内部的层级和自带变换都算得对。
func _measure_visual() -> float:
	var bounds := AABB()
	var measured: bool = false
	var to_visual: Transform3D = visual.global_transform.affine_inverse()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local: Transform3D = to_visual * mesh_node.global_transform
		var box: AABB = local * mesh_node.mesh.get_aabb()
		bounds = box if not measured else bounds.merge(box)
		measured = true
	if not measured:
		push_warning("水块：visual 下面没有带网格的节点，model_size 自动量取失败，先按 1 米算")
		return 1.0
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	return longest if longest > 0.0001 else 1.0


## 由「水块容器」调用：以 muzzle_velocity 的初速从 from 抛出，之后就只剩重力说话了。
func launch(from: Vector3, muzzle_velocity: Vector3) -> void:
	global_position = from
	velocity = muzzle_velocity
	_flight_left = flight_timeout
	_update_visual()


## 由「水块容器」调用：直接出现在指定位置并当场落地（合并生成时用，不经过飞行）。
## 参数不能叫 position —— 那是 Node3D 自带的属性，重名会让 Godot 刷 SHADOWED_VARIABLE_BASE_CLASS。
func settle_at(target: Vector3) -> void:
	global_position = target
	_visual_boost = spawn_growth
	_settle()


## 被吸水区吸收：作废并收缩消失，返回这团水的体积（立方米）。
## 已经作废的水团返回 0，所以两个吸水区摆在一起也不会重复计水量。
func absorb() -> float:
	if _spent:
		return 0.0
	_spent = true
	if is_instance_valid(visual):
		var tween: Tween = create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, _ABSORB_FADE)
		tween.tween_callback(queue_free)
	else:
		queue_free()
	return volume


func _physics_process(delta: float) -> void:
	if _spent:
		return
	if not landed:
		_fly(delta)
		return
	if _visual_boost < 1.0:
		# 合并刚生成的水团从小长到满尺寸
		_visual_boost = minf(1.0, _visual_boost + delta / _GROW_TIME)
		_update_visual()
	if _fading:
		_fade_left = maxf(0.0, _fade_left - delta)
		_update_visual()
		if _fade_left <= 0.0:
			queue_free()
		return
	_life_left -= delta
	if _shrink > 0.0 and _life_left <= _shrink:
		_fading = true
		_fade_left = _shrink
		_update_visual()
	elif _life_left <= 0.0:
		queue_free()


## 自由飞行：水平匀速、竖直匀加速（这就是抛物线本体）。
## 每帧从上一帧位置到当前位置打一条射线，看这一段路上撞到了什么 ——
## 用线段而不是点来查，所以再快也不会穿过薄墙。
func _fly(delta: float) -> void:
	_flight_left -= delta
	if _flight_left <= 0.0:
		queue_free()
		return
	var previous: Vector3 = global_position
	velocity.y -= fall_gravity * delta
	global_position += velocity * delta
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(previous, global_position, collide_mask, ray_exclude)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if normal.y < ground_normal_y:
		# 撞在墙面 / 屋顶 / 围栏这类立不住的面上：水花散掉，这团水就没了
		queue_free()
		return
	# 落在能站住的面上：沿法线抬半个身位贴上去，转入落地流程
	var point: Vector3 = hit.position
	global_position = point + normal * size * 0.5
	_settle()


## 落地：转一下朝向，然后扫一遍邻居看能不能合并。
func _settle() -> void:
	landed = true
	_life_left = lifetime
	if random_yaw:
		rotate_y(randf_range(-PI, PI))
	_update_visual()
	# 延后一帧再扫，让物理引擎先把刚落地这团水登记进重叠列表
	_check_neighbors.call_deferred()


## 扫一遍探测球里的邻居，找到第一个够格的就地合并。
## 探测球半径 = 半个自身边长 + 半个 merge_gap，所以两团水表面间距小于 merge_gap 时就能互相找到。
## 参数是接 area_entered 信号用的，本函数每次都会重扫全部重叠，用不上具体是哪一个。
func _check_neighbors(_other: Area3D = null) -> void:
	if _spent or _fading or not landed or size >= max_size:
		return
	for area: Area3D in get_overlapping_areas():
		var other: WaterBlob = area as WaterBlob
		if other == null or other == self:
			continue
		if other._spent or other._fading or not other.landed:
			continue
		# 水种不同不认（换了水模型，新旧两种水各过各的）
		if other.water_type != water_type or other.size >= other.max_size:
			continue
		# 大小要差不多：相对差在容差以内才算「一样大」。
		# 用相对差而不是绝对差，大团水才不会因为浮点误差或容差尺度不同而合不上。
		if absf(other.size - size) > maxf(size, other.size) * merge_size_tolerance:
			continue
		_merge_with(other)
		return


## 两团一样大的水合成一团更大的：双方立即作废，在正中间生成边长 × grow_factor 的新水团。
## 新水团的底面仍然贴着地面，所以中心要按新边长抬高半个身位。
func _merge_with(other: WaterBlob) -> void:
	if _spent or other._spent:
		return
	_spent = true
	other._spent = true
	# 容差内的两团水边长可能差几个百分点，取大的那个当基准，免得越合越小
	var merged_size: float = maxf(size, other.size) * grow_factor
	var ground_y: float = global_position.y - size * 0.5
	var middle: Vector3 = (global_position + other.global_position) * 0.5
	var spawn := Vector3(middle.x, ground_y + merged_size * 0.5, middle.z)
	if is_instance_valid(field):
		field.spawn_landed(spawn, merged_size)
	queue_free()
	other.queue_free()


## 把「当前边长」同步到探测球半径和视觉缩放。
func _apply_size() -> void:
	if _probe != null:
		_probe.radius = size * 0.5 + merge_gap * 0.5
	volume = size * size * size
	_update_visual()


## 边长 → 视觉缩放。收缩消失和合并长大都乘在这里，所以改 size 只有这一处出口。
func _update_visual() -> void:
	if not is_instance_valid(visual):
		return
	var scale_factor: float = size / maxf(model_size, 0.0001) * _visual_boost
	if _fading:
		scale_factor *= _fade_left / maxf(_shrink, 0.0001)
	visual.scale = Vector3(scale_factor, scale_factor, scale_factor)
