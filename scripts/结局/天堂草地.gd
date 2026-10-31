extends Node3D

## 奶蛋天堂里的草地与小花：全部在 _ready 里用基本几何体拼出来，不依赖任何外部资源。
##
## 为什么放在代码里而不是摆进场景：草块和花都是一样的几块几何体，
## 摆 40 朵花会在场景文件里堆出几百行节点，改一个颜色还得全改。
## 这里只要调参数，重新跑就是一片新的。
##
## 三套颜色都刻意压低饱和度：奶蛋是很饱和的黄色，草地太艳会抢戏，
## 反而看不清主角 —— 和改材质时「拉开明度、不拉色相」是同一个思路。

## 地板顶面的高度。奶蛋天堂的底盘是一个 y 方向 1 米厚的盒子、中心在 y = 0，
## 所以顶面在 +0.5，草块就贴在它上面。
@export var ground_y: float = 0.5
## 随机种子。同一个种子长出来的草地和小花位置完全一样，方便对比改动。
@export var random_seed: int = 20261018

@export_group("草块")
## 每块草地的圆心（x, z），以及半径。用显式坐标是为了避开场景里那 8 只奶蛋——
## 它们摆在 x = -8.6 / -0.8 / 5.3、z = -8.1 / 0.9 / 7.8 这个网格上，
## 草块落在格子之间就不会和奶蛋重叠。
@export var patches: Array[Vector3] = [
	Vector3(-4.7, 2.4, -4.2),
	Vector3(2.3, 2.0, -4.6),
	Vector3(-4.9, 2.2, 3.9),
	Vector3(2.5, 2.6, 3.6),
	Vector3(-1.5, 1.6, -0.3),
]
## 草块厚度（米）。很薄，看起来像贴在地上的色块。
@export_range(0.005, 0.1, 0.005) var patch_thickness: float = 0.02
@export var grass_color: Color = Color(0.42, 0.70, 0.36)

@export_group("小花")
## 每块草地上撒几朵。
@export_range(0, 40, 1) var flowers_per_patch: int = 11
## 花茎高度（米）。奶蛋约 0.9 米高，花要长到它的三分之一左右才看得出是花，
## 太矮就只剩几个白点，等于没装饰。
@export_range(0.05, 0.6, 0.01) var flower_height: float = 0.30
## 花瓣颜色，随机取。
@export var petal_colors: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.74, 0.84),
	Color(0.76, 0.87, 1.0),
	Color(1.0, 0.93, 0.72),
]
@export var stem_color: Color = Color(0.30, 0.56, 0.26)
@export var core_color: Color = Color(1.0, 0.84, 0.35)

var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}


func _ready() -> void:
	_rng.seed = random_seed
	for p in patches:
		_build_patch(p.x, p.z, p.y)


func _material(color: Color) -> StandardMaterial3D:
	# 同一个颜色只建一份材质，几十朵花共用，省得在资源里刷出一堆重复项。
	var key: int = color.to_rgba32()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic = 0.0
	_mats[key] = m
	return m


func _mesh_node(mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.rotation = rot
	node.scale = scl
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 一块草地：一个压扁的圆柱，加一圈稍微深一点的边，看起来有点体积。
func _build_patch(cx: float, cz: float, radius: float) -> void:
	var base := CylinderMesh.new()
	base.top_radius = radius
	base.bottom_radius = radius
	base.height = patch_thickness
	base.radial_segments = 18
	base.rings = 1
	_mesh_node(base, grass_color, Vector3(cx, ground_y + patch_thickness * 0.5, cz))

	var rim := CylinderMesh.new()
	rim.top_radius = radius
	rim.bottom_radius = radius * 1.02
	rim.height = patch_thickness * 3.0
	rim.radial_segments = 18
	rim.rings = 1
	var darker: Color = grass_color.darkened(0.16)
	_mesh_node(rim, darker, Vector3(cx, ground_y - patch_thickness * 0.6, cz))

	for i in flowers_per_patch:
		# 撒在圆内：半径取平方根，点才不会往圆心堆
		var angle: float = _rng.randf() * TAU
		var distance: float = sqrt(_rng.randf()) * radius * 0.86
		var fx: float = cx + cos(angle) * distance
		var fz: float = cz + sin(angle) * distance
		_build_flower(fx, fz)


## 一朵小花：一根细茎 + 一个花心球 + 五片花瓣。
func _build_flower(x: float, z: float) -> void:
	var height: float = flower_height * _rng.randf_range(0.75, 1.25)
	var lean: float = _rng.randf_range(-0.09, 0.09)

	var stem := CylinderMesh.new()
	stem.top_radius = 0.006
	stem.bottom_radius = 0.008
	stem.height = height
	stem.radial_segments = 5
	stem.rings = 1
	_mesh_node(stem, stem_color, Vector3(x, ground_y + height * 0.5, z), Vector3(lean, 0.0, lean * 0.7))

	var top := Vector3(x + lean * height, ground_y + height, z + lean * 0.7 * height)
	var color: Color = petal_colors[_rng.randi() % petal_colors.size()]
	var petal_size: float = height * 0.38

	# 五片花瓣：绕 Y 轴均分，每片稍微向外翻一点
	var petal := BoxMesh.new()
	petal.size = Vector3(petal_size * 0.55, petal_size * 0.18, petal_size)
	for i in 5:
		var a: float = TAU * float(i) / 5.0 + _rng.randf_range(-0.1, 0.1)
		var offset := Vector3(cos(a), 0.0, sin(a)) * petal_size * 0.45
		_mesh_node(petal, color, top + offset, Vector3(0.0, -a, 0.32))

	var core := SphereMesh.new()
	core.radius = petal_size * 0.30
	core.height = petal_size * 0.60
	core.radial_segments = 8
	core.rings = 4
	_mesh_node(core, core_color, top + Vector3(0.0, petal_size * 0.06, 0.0))
