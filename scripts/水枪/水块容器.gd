extends Node3D
class_name WaterField

## 所有水团的出生点与登记处：水枪射出、两团水合并，都叫这里生成。
##
## 「水长什么样」只在这一个地方定义 —— 以后整体换成水球、水花、喷雾造型，
## 只要把下面的 blob_scene 换成新场景（根脚本继承 WaterBlob）就行，水枪和吸水区都不用动。
## 新场景里把视觉模型放在 Visual 子节点下、并把它的原始边长填进 WaterBlob.model_size，
## 尺寸就会自动对上，不用改任何代码。
##
## 水团的规则和手感全在这里：合并阶梯（grow_factor / max_size / merge_gap / merge_size_tolerance）、
## 存活时长（lifetime）、弹道（muzzle_speed / gravity）。放在一起是因为它们互相牵制，
## 分成两个文件调很容易调出对不上的组合。
## 只有起始大小不在这里 —— 它属于发射器，见 scripts/水枪.gd 的 blob_size。
##
## 水团是运行时才知道会出几个的，所以它们由代码挂在「水块容器」这个节点下面，
## 而不是写进场景文件 —— 在编辑器的远程场景树（Remote Scene Tree）里能直接看到它们，
## 名字是「水 0.35m」这样带边长的，方便调试时数数。
##
## 水种（哪些水能互相合并）不用配置：直接取 blob_scene 的场景路径，
## 换一个水模型就是换了一个水种，地上旧的水不会跟新射出来的混在一起。


## 水团的场景文件；换水模型就换这个。
## 它同时决定水种：射出来的水会带上这个场景的路径作为标识，只有标识相同的水才会互相合并，
## 所以换模型之后新旧两种水各过各的，不用额外配置。
@export var blob_scene: PackedScene
## 每次合并的边长倍率。1.26 约等于「体积翻倍」，2.0 就是边长直接翻倍。
## 阶梯是这样长出来的：0.35 → 0.44 → 0.56 → 0.70 → 0.88 → …（取决于水枪射出的初始大小）
@export_range(1.01, 3.0, 0.01) var grow_factor: float = 1.26
## 边长上限（米）。边长一旦达到这个值，这团水就冻结、不再合并。
## 注意是「达到就冻」而不是「超过才不许合」：填 0.9 时最大的水可能是 1.11 米那一档，
## 因为它是由 0.88 米的两团合出来的，合完才发现过线了。
@export_range(0.01, 20.0, 0.01) var max_size: float = 1.5
## 两团水的表面间距小于这个值（米）就合并，不必真的贴上。
@export_range(0.0, 3.0, 0.01) var merge_gap: float = 0.35
## 判定两团水「一样大」的相对容差。0.05 = 边长相差 5% 以内就算一样大。
## 合并倍率是 26%，所以容差要明显小于 13%，否则会把相邻两档误判成同一档。
@export_range(0.0, 0.13, 0.005) var merge_size_tolerance: float = 0.05
## 一团水落地后活多久（秒），到点收缩消失。合并出来的大水团也按这个重新计时。
@export_range(0.1, 120.0, 0.1) var lifetime: float = 8.0
## 出膛初速（米/秒）。这个值同时决定射程和抛物线有多弯：
## 越快射得越远、弧线越平（像直线），越慢越像「倒水」。
## 15 m/s 平视大约打 8 米、抬到 45° 最远约 23 米 —— 这是「不归零」时的老参考。
## **水枪的归零距离是按这个值和下面的 gravity 现算的**，所以改这两项不用回去重调水枪：
## 水照样穿过同一个距离上的准星，只是弧线整体变平（变快）或变拱（变慢）。
@export_range(1.0, 80.0, 0.5) var muzzle_speed: float = 15.0
## 重力加速度（米/秒²）。调大则水坠得更快、弧更明显、射程更短。
@export_range(0.5, 40.0, 0.1) var gravity: float = 9.8
## 水团飞行途中打射线用哪些层，用来判断它撞到了什么。默认第 1 层（世界）。
@export_flags_3d_physics var ground_mask: int = 1
## 水团不该撞到的碰撞体，通常就是主人公自己 —— 免得朝脚下开枪时水一出膛就撞在自己身上消失。
@export var ignore_body: CollisionObject3D


## 射出一团会飞的水。from 是出膛位置，direction 是抛出方向（会归一化）。
## 出膛速度 = direction × muzzle_speed，之后全靠重力，走一条真的抛物线。
func spawn_flying(from: Vector3, direction: Vector3, size: float) -> WaterBlob:
	var blob: WaterBlob = _make(size)
	if blob == null:
		return null
	blob.launch(from, direction.normalized() * muzzle_speed)
	return blob


## 直接在某处生成一团已经落地的水（两团水合并时用）。
## 参数不能叫 position —— 那是 Node3D 自带的属性，重名会让 Godot 刷 SHADOWED_VARIABLE_BASE_CLASS。
func spawn_landed(target: Vector3, size: float) -> WaterBlob:
	var blob: WaterBlob = _make(size)
	if blob == null:
		return null
	blob.settle_at(target)
	return blob


## 实例化并登记一团水；节点名带边长，方便在远程场景树里一眼看出哪团多大。
## size 是这团水的边长，体积由 WaterBlob 自己按 size³ 算，这里不用管。
func _make(size: float) -> WaterBlob:
	if blob_scene == null:
		push_error("水块容器：blob_scene 未指定，射不出水")
		return null
	var blob: WaterBlob = blob_scene.instantiate() as WaterBlob
	if blob == null:
		push_error("水块容器：blob_scene 的根节点没有继承 WaterBlob，射不出水")
		return null
	# 先填好参数再入树，_ready() 里才能按正确的尺寸初始化
	blob.name = "水 %.2fm" % size
	blob.field = self
	blob.size = size
	blob.water_type = blob_scene.resource_path
	blob.grow_factor = grow_factor
	blob.max_size = max_size
	blob.merge_gap = merge_gap
	blob.merge_size_tolerance = merge_size_tolerance
	blob.lifetime = lifetime
	blob.fall_gravity = gravity
	blob.collide_mask = ground_mask
	if is_instance_valid(ignore_body):
		blob.ray_exclude.append(ignore_body.get_rid())
	add_child(blob)
	return blob
