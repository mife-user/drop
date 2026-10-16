extends Area3D
class_name WaterSink

## 吸水区：任何「水」碰撞层的东西飘进来就被吸收掉，水量按水团的**体积（立方米）**累加。
##
## 这是通用件 —— 判定靠碰撞层，不靠「这是不是水池」。水池、消防栓、水带、花盆旁边
## 都摆一个就能用，水团本身完全不知道它存在，所以以后在哪儿加、加几个都不用改水团的代码。
##
## 吸收之后要发生什么，默认是这里的水面往上涨；以后要接别的反应（音效、计数、开水闸……），
## 连下面的 water_received / filled 信号即可，不用改这个脚本。
##
## 水面高度按「本节点的局部坐标」算，所以整块吸水区（连同碰撞盒）拖到哪儿，水位都跟着走。
##
## **水面的位置和大小全部由碰撞盒和水量算出来**（见 _resize_surface / _update_surface）：
## 水平方向 = 碰撞盒的尺寸（含 CollisionShape3D 节点自己的缩放），水体盒的高度 = 水位。
## 网格自身多大都无所谓，会被缩放到正好贴合 —— 水池那种方容器用方网格，
## 木碗那种圆容器用圆柱网格，只是换网格 + 把 surface_fit 改成 ROUND 的事。
## 碰撞盒的形状：BoxShape3D / CylinderShape3D / SphereShape3D / CapsuleShape3D 都认
##（见 _shape_extents），换别的形状要回来加一条分支，否则会打印警告并退回手填高度。
## 所以「水面」节点在编辑器里的 transform 只是「满水长什么样」的预览，运行时会被覆盖 ——
## 要让水铺得更开或收窄，去改 CollisionShape3D，改水面节点本身没用。

## 每吸收一团水发出一次；参数是这团水的体积（立方米）。
signal water_received(amount: float)
## 水量第一次到顶时发出一次；之后继续吸水不会再发。
signal filled()

## 吸水区自己登记的组名 —— 谁要「全场的容器」，就 get_nodes_in_group(WaterSink.GROUP_WATER_SINK) 捞。
##
## 「我是个吸水区」是容器自己的**身份**，由它自己声明，所以这一行写在吸水区里；
## 和 水块.gd 的 add_to_group("water")、player.gd 的 "player" 是同一个写法。
## 别的玩法（装满之后弹字幕、给邮币）仍然是去连下面的信号，**不要往这个脚本里塞**。
const GROUP_WATER_SINK: StringName = &"water_sink"

## 装水量上限（立方米）。水团的水量按边长³ 算：一团边长 0.05 米的水是 0.000125 m³，
## 想「射 200 发刚好填满」就填 0.025。
## 这是**绝对容积**，不跟着水枪走 —— 水枪升级（射出的水更大）后，
## 每发灌进来的水量真的变多，填满同样的容量需要的发数会自动变少。
## 吸满之后继续吸水：水团照样消失，只是水面不再上涨。
@export_range(0.0001, 1000.0, 0.0001) var capacity: float = 0.025
## 表现水面的网格；水量为 0 时自动隐藏，第一次接到水才出现。
@export var surface: MeshInstance3D
## 决定水面大小和升降范围的碰撞盒；留空时自动取本节点下第一个 CollisionShape3D。
@export var shape_node: CollisionShape3D
## 勾选后水面自动贴合碰撞盒的顶面和底面，改碰撞盒尺寸就行，不用手填高度。
@export var auto_fit_shape: bool = true
## 池底高度（本节点局部 Y）——水体盒模式下就是盒子底面的位置；取消上面勾选后才生效。
@export var bottom_y: float = 0.0
## 水面加满时的高度（本节点局部 Y）；取消上面勾选后才生效。
@export var top_y: float = 1.0
## 水面网格的形态。换水面样式时记得跟着改。
enum SurfaceKind {
	PLANE,   ## 一张平面：网格铺在碰撞盒的池口上，position.y 就是水位本身
	VOLUME,  ## 一个水体盒：底面钉在池底、顶面跟着水位长，水少时是薄薄一层、水多才涨高
}
@export var surface_kind: SurfaceKind = SurfaceKind.PLANE
## 水面俯视轮廓的形状。容器是方的（水池）用 BOX，是圆的（碗、盆）用 ROUND。
enum SurfaceFit {
	BOX,    ## 方形：水面的 X/Z 分别适配碰撞盒的 X/Z，正好铺满
	ROUND,  ## 圆形：X/Z 用同一个系数、按碰撞盒的内切圆铺，这样圆才不会被压成椭圆
}
@export var surface_fit: SurfaceFit = SurfaceFit.BOX

## 当前水量（立方米），和 capacity 同单位。
var amount: float = 0.0

var _shape: Shape3D
var _mesh_size: Vector3 = Vector3.ONE     # 水面网格自身的尺寸（米），用来把「想要的米数」换算成 scale
var _mesh_center: Vector3 = Vector3.ZERO  # 网格原点相对自身包围盒中心的偏移（米），贴池底时要减掉


## 进树就把自己登记进「吸水区」组，别人按这个组来找容器。
##
## **写在 _enter_tree 而不是 _ready**：所有节点的 _enter_tree 都跑完，才会有第一个 _ready
##（交互台.gd 找玩家/准星用的也是这条），所以按组捞的脚本（水量换币）不管挂在场景树哪一层、
## 谁的 _ready 先跑，都一定捞得到。写进 _ready 就变成依赖兄弟顺序 —— 现在能跑纯属巧合，节点一挪就悄悄失效。
func _enter_tree() -> void:
	add_to_group(GROUP_WATER_SINK)


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	if not is_instance_valid(shape_node):
		shape_node = _find_shape()
	if is_instance_valid(shape_node):
		_shape = shape_node.shape
		if _shape == null:
			push_warning("吸水区：碰撞盒没挂 shape，水面大小和高度范围只能自己调")
		elif _shape_extents(_shape) == Vector3.ZERO:
			push_warning("吸水区：认不出 %s 这种碰撞形状，水面大小和高度范围只能自己调（手填 bottom_y / top_y）" % _shape.get_class())
	# 量一次水面网格自身的包围盒：脚本是按「米」摆水面的，换算成 scale 得先知道网格本来多大。
	# 1×1 的平面和 6×5.5 的盒子都能量，以后换成别的模型也不用改代码。
	if is_instance_valid(surface) and surface.mesh != null:
		var bounds: AABB = surface.mesh.get_aabb()
		_mesh_size = Vector3(maxf(bounds.size.x, 0.0001), maxf(bounds.size.y, 0.0001), maxf(bounds.size.z, 0.0001))
		_mesh_center = bounds.get_center()
	_update_surface()   # 里面会先按碰撞盒贴合一次，再按当前水量摆水位


## 有一团水进来了：收下它的体积。已经被别的吸水区收走的水团会返回 0，不会重复计。
func _on_area_entered(area: Area3D) -> void:
	var blob: WaterBlob = area as WaterBlob
	if blob == null:
		return
	var cubic: float = blob.absorb()
	if cubic <= 0.0:
		return
	var full_before: bool = amount >= capacity
	amount = minf(amount + cubic, capacity)
	water_received.emit(cubic)
	if not full_before and amount >= capacity:
		filled.emit()
	_update_surface()


## 没手动指定碰撞盒时，取本节点下第一个 CollisionShape3D。
func _find_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


## 把碰撞形状翻译成「形状自己坐标系里的外接尺寸」，也就是一个方盒该多大。
##
## 物理引擎只认形状本身，而水面要的是一个方盒范围，所以得按类型各算各的：
## 池子用方盒，木碗 / 花盆用圆柱 —— 换成圆柱网格只是换网格 + 把 surface_fit 改成 ROUND 的事，
## 碰撞盒用什么形状都行。返回 Vector3.ZERO 表示这种形状还不认识（水面退回手填的 bottom_y / top_y）。
##
## 圆柱取的是外接方盒（直径 × 高）：横向正好把圆柱框住，配上 surface_fit = ROUND 再取内切圆，
## 得到的就是半径本身，水面对得上碗口。
func _shape_extents(s: Shape3D) -> Vector3:
	if s is BoxShape3D:
		return (s as BoxShape3D).size
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0)
	if s is SphereShape3D:
		var d: float = (s as SphereShape3D).radius * 2.0
		return Vector3(d, d, d)
	if s is CapsuleShape3D:
		var cap := s as CapsuleShape3D
		# Godot 4 的 CapsuleShape3D.height 已经把两头的半球算进去了，别再各加一个半径
		return Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0)
	return Vector3.ZERO


## 碰撞盒在「本节点坐标系」里的实际大小 —— 也就是水面该铺多大。
##
## 关键是**乘上 CollisionShape3D 节点自己的缩放**：物理引擎算碰撞时就是这么算的，
## 而 shape 的 size / radius 只是形状资源自己的尺寸，不含这一层。
## 把碰撞盒节点缩小来适配小容器（木碗、花盆）时，漏掉它水面就会整整大出 1/缩放 倍 ——
## 缩到 0.13 就是大 7.7 倍，几米宽的水面糊在小碗上。
##
## 返回 Vector3.ZERO 表示「没用」—— 没挂碰撞盒，或形状不认识，调用方要退回手填高度。
func _container_size() -> Vector3:
	if _shape == null or not is_instance_valid(shape_node):
		return Vector3.ZERO
	var ext: Vector3 = _shape_extents(_shape)
	if ext == Vector3.ZERO:
		return Vector3.ZERO
	return Vector3(
			ext.x * absf(shape_node.scale.x),
			ext.y * absf(shape_node.scale.y),
			ext.z * absf(shape_node.scale.z))


## 水面网格的水平位置和大小跟随碰撞盒；改碰撞盒尺寸，水面自动跟着变。
## 网格自身多大都行：这里按「想要的米数 ÷ 网格原始尺寸」算出 scale。
func _resize_surface() -> void:
	if not is_instance_valid(surface):
		return
	var box: Vector3 = _container_size()
	if box == Vector3.ZERO:
		return
	surface.position.x = shape_node.position.x
	surface.position.z = shape_node.position.z
	# 除以网格自身的尺寸，是为了「网格本来多大都行」—— 1×1 的平面、6 米的盒子、
	# 碗用的圆柱，都会被缩放到正好贴合。
	# scale.y 归 _update_surface 管（水体盒的高度），这里别动。
	if surface_fit == SurfaceFit.ROUND:
		# 圆形：X/Z 必须用同一个系数，分别适配的话圆会被压成椭圆。
		# 直径取碰撞盒 X/Z 里小的那个 —— 内切圆，水面永远不超出判定范围。
		var diameter: float = minf(box.x, box.z)
		surface.scale = Vector3(diameter / _mesh_size.x, surface.scale.y, diameter / _mesh_size.z)
	else:
		surface.scale = Vector3(box.x / _mesh_size.x, surface.scale.y, box.z / _mesh_size.z)


## 按水量比例把水面从池底推到池口；一滴水都没有时整个隐藏。
## 平面模式：水位就是平面本身的位置；水体盒模式：底面钉在池底、顶面长到水位。
func _update_surface() -> void:
	if not is_instance_valid(surface):
		return
	# 每次都重新贴合一遍碰撞盒：这样运行中在检查器里改碰撞盒尺寸（远程场景树），
	# 下一团水进来时水面就跟着变了，不用重启。改尺寸的开销就是几次乘法。
	_resize_surface()
	var ratio: float = clampf(amount / maxf(capacity, 0.0001), 0.0, 1.0)
	surface.visible = ratio > 0.0
	if not surface.visible:
		return
	var bottom: float = bottom_y
	var top: float = top_y
	if auto_fit_shape:
		var box: Vector3 = _container_size()
		if box != Vector3.ZERO:
			bottom = shape_node.position.y - box.y * 0.5
			top = shape_node.position.y + box.y * 0.5
	var level: float = lerpf(bottom, top, ratio)
	# 网格原点不一定落在包围盒中心（BoxMesh / PlaneMesh 默认在，换成 glb 就可能不在），贴池底时要减掉
	var center_y: float = _mesh_center.y * surface.scale.y
	if surface_kind == SurfaceKind.VOLUME:
		var height: float = maxf(level - bottom, 0.001)
		surface.scale.y = height / _mesh_size.y
		surface.position.y = bottom + height * 0.5 - center_y
	else:
		surface.position.y = level - center_y
