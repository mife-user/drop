@tool
extends MultiMeshInstance3D

## 一片可以拖进场景的草。
##
## 这个脚本做三件事：
## 1. 用纯三角面生成「一丛草」的网格（不贴图，只有顶点和 UV）；
## 2. 把这丛草按格子撒满整片矩形区域，组装成 MultiMesh；
## 3. 在编辑器里把 MultiMesh 存成外部 .res（resources/草地/节点名.res），
##    场景里只留一条外部引用。这样保存 .tscn 时不会把二进制数据嵌进去，
##    也不会触发「场景含二进制数据、文件太大」的警告。
##
## 拖动节点位置不会重建；改下面这些 @export 参数才会重建并覆盖对应的 .res。
## 风摆由 resources/草风.gdshader 完成，本脚本不参与每帧计算。
##
## 用法：从文件系统把 scenes/草地.tscn 拖进 3D 场景即可，
## 复制多份拼满院子。每份的 .res 文件和分布由节点名字区分。

@export_group("一丛草的形状")

## 一丛草里有几片叶子；每片 2 个三角面
@export_range(1, 16, 1) var blades_per_tuft: int = 6:
	set(value):
		blades_per_tuft = maxi(1, value)
		_rebuild_if_ready()

## 草叶最高多少米
@export_range(0.02, 2.0, 0.01) var blade_height: float = 0.22:
	set(value):
		blade_height = maxf(0.02, value)
		_rebuild_if_ready()

## 草叶根部宽度（米）
@export_range(0.005, 0.2, 0.001) var blade_width: float = 0.035:
	set(value):
		blade_width = maxf(0.005, value)
		_rebuild_if_ready()

## 一丛草的根部散开半径（米）
@export_range(0.0, 0.5, 0.005) var tuft_radius: float = 0.05:
	set(value):
		tuft_radius = maxf(0.0, value)
		_rebuild_if_ready()

@export_group("这一片草的范围")

## 这一片草的长宽（米，顺序是 X、Z）；拖进场景后改这里可以变大变小
@export var patch_size: Vector2 = Vector2(3.0, 3.0):
	set(value):
		patch_size = Vector2(maxf(0.05, value.x), maxf(0.05, value.y))
		_rebuild_if_ready()

## 每平方米大约几丛草；越大越密
@export_range(0.1, 500.0, 0.1) var density: float = 18.0:
	set(value):
		density = maxf(0.1, value)
		_rebuild_if_ready()

## 随机种子；同一个种子分布固定，换个数字就换一种分布
@export var random_seed: int = 1:
	set(value):
		random_seed = value
		_rebuild_if_ready()

@export_group("每丛草的随机变化")

## 每丛草的最小缩放
@export_range(0.1, 5.0, 0.01) var scale_min: float = 0.8:
	set(value):
		scale_min = maxf(0.1, value)
		_rebuild_if_ready()

## 每丛草的最大缩放
@export_range(0.1, 5.0, 0.01) var scale_max: float = 1.25:
	set(value):
		scale_max = maxf(0.1, value)
		_rebuild_if_ready()

## 每丛草额外的随机高度幅度；0 = 全部一样高
@export_range(0.0, 1.0, 0.01) var height_variation: float = 0.2:
	set(value):
		height_variation = clampf(value, 0.0, 1.0)
		_rebuild_if_ready()


## MultiMesh 的实例数硬上限
const MAX_INSTANCES: int = 65536
## 生成单丛草时使用的固定种子；改它可以让整片草的叶形换一种
const TUFT_SHAPE_SEED: int = 97
## 外部 .res 存放目录
const RESOURCE_DIR: String = "res://resources/草地"
## 参数版本；改网格算法时加一，让旧 .res 自动失效重建
const SIGNATURE_VERSION: int = 2
## 存在 MultiMesh 上的参数签名，用来判断 .res 是否需要重建
const SIGNATURE_META: String = "grass_signature"


func _ready() -> void:
	# 编辑器里优先加载已经存好的 .res；没有或参数变了才重建
	_ensure_resource()


## 参数变化时重建，并覆盖对应的 .res
func _rebuild_if_ready() -> void:
	if not is_node_ready():
		return
	_rebuild_and_store()


## 先找外部 .res：路径和参数签名都对得上就直接用，避免每次打开都重建
func _ensure_resource() -> void:
	var path := _resource_path()
	var signature := _signature()
	if multimesh != null:
		if multimesh.resource_path == path \
				and String(multimesh.get_meta(SIGNATURE_META, "")) == signature:
			return

	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is MultiMesh \
				and String(loaded.get_meta(SIGNATURE_META, "")) == signature:
			multimesh = loaded
			return

	# 没有外部文件，或者文件是旧参数生成的：重建并写盘
	_rebuild_and_store()


## 生成 MultiMesh，编辑器里立刻存到外部 .res，然后挂到节点上
func _rebuild_and_store() -> void:
	var mm := _build_multimesh()
	if mm == null:
		multimesh = null
		return

	mm.resource_name = "草地 %s" % String(name)
	mm.set_meta(SIGNATURE_META, _signature())

	if Engine.is_editor_hint():
		_ensure_resource_dir()
		var path := _resource_path()
		var err := ResourceSaver.save(mm, path, ResourceSaver.FLAG_CHANGE_PATH)
		if err != OK:
			push_error("草皮保存 .res 失败：%s（%s）" % [path, error_string(err)])
	multimesh = mm


## 组装 MultiMesh：网格、位置、随机朝向/缩放、风摆用的自定义数据
func _build_multimesh() -> MultiMesh:
	var mesh := _build_tuft_mesh()
	var positions := _make_positions(MAX_INSTANCES)
	var count := positions.size()
	if count <= 0:
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# 风摆的相位、方向和颜色变化通过实例自定义数据传给着色器
	# 这一项必须在 instance_count 之前设置
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = _make_custom_aabb()

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value() + 10007
	var low_scale := minf(scale_min, scale_max)
	var high_scale := maxf(scale_min, scale_max)

	for i in count:
		var instance_position := positions[i]
		# 每丛随机绕 Y 轴转一圈，避免看出是同一丛复制出来的
		var yaw := rng.randf() * TAU
		var uniform_scale := rng.randf_range(low_scale, high_scale)
		# 高度再单独抖一下，让草尖高低不齐
		var height_scale := uniform_scale * rng.randf_range(
			1.0 - height_variation, 1.0 + height_variation
		)
		var basis := Basis(Vector3.UP, yaw).scaled(
			Vector3(uniform_scale, height_scale, uniform_scale)
		)
		mm.set_instance_transform(i, Transform3D(basis, instance_position))
		# r = 摆动相位, g = 摆动方向, b = 颜色变化
		mm.set_instance_custom_data(
			i, Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		)

	return mm


## 生成「一丛草」的单 surface 网格：每片叶 2 个三角面
func _build_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	rng.seed = TUFT_SHAPE_SEED
	var blade_count := maxi(1, blades_per_tuft)

	for i in blade_count:
		# 每片叶朝不同方向，形成一丛
		var yaw := TAU * float(i) / float(blade_count) + rng.randf_range(-0.35, 0.35)
		var tip_height := blade_height * rng.randf_range(0.7, 1.05)
		var base := Vector3(
			rng.randf_range(-tuft_radius, tuft_radius),
			0.0,
			rng.randf_range(-tuft_radius, tuft_radius)
		)
		var outward := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-outward.z, 0.0, outward.x)
		# 草尖向外倾一点，不要全部笔直立着
		var tip := base + outward * tip_height * rng.randf_range(0.05, 0.25)
		tip.y = tip_height

		var base_half := blade_width * 0.5 * rng.randf_range(0.8, 1.1)
		var tip_half := base_half * 0.12
		var v0 := base - side * base_half
		var v1 := base + side * base_half
		var v2 := tip - side * tip_half
		var v3 := tip + side * tip_half

		# 两个三角面；材质是双面的，绕序不影响正反面
		_add_vertex(st, v0, Vector2(0.0, 0.0))
		_add_vertex(st, v1, Vector2(1.0, 0.0))
		_add_vertex(st, v2, Vector2(0.0, 1.0))
		_add_vertex(st, v2, Vector2(0.0, 1.0))
		_add_vertex(st, v1, Vector2(1.0, 0.0))
		_add_vertex(st, v3, Vector2(1.0, 1.0))

	return st.commit()


## 加一个顶点；法线统一朝上，草叶细所以不用逐面法线
func _add_vertex(st: SurfaceTool, vertex_position: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(vertex_position)


## 实际使用的随机种子。
## 把节点名字掺进来，于是复制出来的每片草布局自动不同；
## 同一个节点每次打开都保持一致（改名字会换一种布局）。
func _seed_value() -> int:
	return random_seed + String(name).hash()


## 把区域切成带随机抖动的格子，得到每一丛草的落点
func _make_positions(limit: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value()

	var width := maxf(0.05, patch_size.x)
	var depth := maxf(0.05, patch_size.y)
	var wanted := int(round(width * depth * density))
	wanted = clampi(wanted, 1, limit)

	# 按长宽比拆行列，格子大致是方的，分布比纯随机均匀
	var aspect := width / depth
	var cols := maxi(1, int(round(sqrt(float(wanted) * aspect))))
	# 格子数不能超过想要的丛数，否则细长区域会凭空多出一排
	cols = mini(cols, wanted)
	var rows := maxi(1, int(ceil(float(wanted) / float(cols))))
	# 超过 MultiMesh 上限时收缩，宁可格子变形也不超出硬上限
	while cols * rows > limit and cols > 1:
		cols -= 1
		rows = maxi(1, int(ceil(float(limit) / float(cols))))

	var positions := PackedVector3Array()
	positions.resize(cols * rows)
	var cell_width := width / float(cols)
	var cell_depth := depth / float(rows)
	for row in rows:
		for col in cols:
			var x := -width * 0.5 + (float(col) + rng.randf()) * cell_width
			var z := -depth * 0.5 + (float(row) + rng.randf()) * cell_depth
			positions[row * cols + col] = Vector3(x, 0.0, z)
	return positions


## 给 MultiMesh 一个留了余量的包围盒，风吹摆动时不会被提前裁掉
func _make_custom_aabb() -> AABB:
	var width := maxf(0.05, patch_size.x)
	var depth := maxf(0.05, patch_size.y)
	var max_scale := maxf(scale_min, scale_max)
	# 一丛草最远能伸出多少：根部散开 + 草尖外倾 + 风摆余量
	var spread := (tuft_radius + blade_height * 0.3 + blade_width) * max_scale + 0.6
	var top := blade_height * max_scale * (1.0 + height_variation) + 0.4
	return AABB(
		Vector3(-width * 0.5 - spread, -0.1, -depth * 0.5 - spread),
		Vector3(width + spread * 2.0, top, depth + spread * 2.0)
	)


## 每片草皮对应的外部 .res 路径。
## 用「父节点名 + 节点名」区分，复制出来的草地2、草地3 会自动各存一份。
func _resource_path() -> String:
	return "%s/%s.res" % [RESOURCE_DIR, _resource_key()]


## 文件名用的稳定标识；场景根节点（没有父节点时）用「根」
func _resource_key() -> String:
	var parent_name := "根"
	if Engine.is_editor_hint() and get_tree() != null \
			and get_tree().edited_scene_root == self:
		parent_name = "根"
	elif get_parent() != null:
		parent_name = String(get_parent().name)
	return "%s_%s" % [_sanitize_filename(parent_name), _sanitize_filename(String(name))]


## 把节点名里不能进文件名的字符换掉
func _sanitize_filename(text: String) -> String:
	var result := text
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ".", " "]:
		result = result.replace(ch, "_")
	if result.is_empty():
		result = "草地"
	return result


## 参数签名：这些值任何一个变了，.res 就要重建
func _signature() -> String:
	var parts := PackedStringArray([
		"v%d" % SIGNATURE_VERSION,
		_resource_key(),
		str(blades_per_tuft),
		str(blade_height),
		str(blade_width),
		str(tuft_radius),
		str(patch_size),
		str(density),
		str(random_seed),
		str(scale_min),
		str(scale_max),
		str(height_variation),
	])
	return "|".join(parts)


## 确保 resources/草地 目录存在（只在编辑器里写盘）
func _ensure_resource_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOURCE_DIR))
