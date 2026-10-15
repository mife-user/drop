extends MeshInstance3D
class_name WaterSurface

## 水面流动：按「每秒推进多少个贴图 tile」推动材质的 uv1_offset，让噪声在世界空间里平移。
##
## 水面材质开了 Triplanar，UV 是由世界坐标算出来的：
##     uv1_triplanar_pos = 世界坐标 × uv1_scale + uv1_offset
## 所以改 uv1_offset 就等价于让噪声整体在世界空间里滑动 —— 正是想要的「水在流」，
## 不必为了流动去关掉 triplanar。折射贴图用的是同一套坐标，法线扰动和折射扭曲会一起动。
##
## 单位换算：uv1_scale 是「每米重复几个 tile」，于是
##     实际流速（米/秒）= flow_speed ÷ 材质的 uv1_scale
## 例：uv1_scale = 0.25、flow_speed = 0.06 时，噪声每秒走 0.24 米。
##
## 方向：triplanar 下顶面按世界 (X,Z) 投影、南北两面按 (X,Y)、东西两面按 (Z,−Y)，
## 所以 X 分量能让所有面都动起来，Z 分量只影响顶面和东西两面 —— 想「整池水一起流」就以 X 为主。
##
## 注意：uv1_offset 是材质上的属性，在编辑器里手调的值会从这里重新算起，不会累积。

## 流动方向与速度，单位是「tile/秒」；X 对应世界 X 方向，Y 对应世界 Z 方向。填 0 就是不流。
@export var flow_speed: Vector2 = Vector2(0.06, 0.02)
## 要推动的材质；留空时自动取本网格第一个表面用到的材质。
@export var material: StandardMaterial3D
## 关掉后水面静止（做结冰、暂停之类的效果时用）。
@export var flow_enabled: bool = true

var _offset: Vector2 = Vector2.ZERO   # 累计推进量（tile）；不直接读材质，免得编辑器里手调的值被当成累计值


func _ready() -> void:
	if not is_instance_valid(material):
		material = get_active_material(0) as StandardMaterial3D
	if not is_instance_valid(material):
		push_warning("水面：找不到 StandardMaterial3D，UV 流动关掉了")
		return
	# 材质是 .tscn 里的子资源，同一个场景里摆第二个吸水区时会跟这里共用同一个材质，
	# 两边就会互相盖 offset。复制一份挂到自己身上，各流各的
	#（贴图等子资源仍然共用，不会多占显存）。
	material = material.duplicate() as StandardMaterial3D
	set_surface_override_material(0, material)


func _process(delta: float) -> void:
	if not flow_enabled or not is_instance_valid(material):
		return
	_offset += flow_speed * delta
	material.uv1_offset = Vector3(_offset.x, 0.0, _offset.y)
