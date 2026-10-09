extends Node3D

## 奶蛋在镜头内随机活动约30秒，再沿安全路线走出镜头，完全离屏才隐藏。
## 泳池禁区可通过 PoolExclusion/CollisionShape3D 在编辑器中调整。

## 用于判定可见范围的摄像机。
@export var camera: Camera3D
## 完全走出镜头并消失后，等待多少秒再次随机出现。
@export_range(0.1, 120.0, 0.1) var respawn_delay: float = 10.0
## 首次出现的最短等待时间（秒）。
@export_range(0.1, 60.0, 0.1) var first_delay_min: float = 2.0
## 首次出现的最长等待时间（秒）。
@export_range(0.1, 60.0, 0.1) var first_delay_max: float = 5.0
## 找不到安全路线时，稍后重新尝试（秒）。
@export_range(0.5, 10.0, 0.5) var retry_delay: float = 3.0
## 镜头内随机活动时间（秒）；到时开始寻找出口，不会直接消失。
@export_range(5.0, 120.0, 1.0) var roam_duration: float = 30.0
## 单段随机路线的最大长度（米），到达后继续随机选择下一段。
@export_range(2.0, 15.0, 0.5) var max_leg_distance: float = 6.0
## 地面参考高度；不在屋顶、家具或泳池底部生成。
@export var ground_height: float = 0.03
## 可接受的地面高度误差（米）。
@export_range(0.02, 1.0, 0.01) var ground_tolerance: float = 0.18
## 奶蛋中心到泳池边缘的最小距离，包含身体半径（米）。
@export_range(0.35, 2.0, 0.05) var pool_margin: float = 0.45
## 路线基础跨度；每次会随机浮动，不再强制穿过画面中心。
@export_range(0.08, 0.7, 0.01) var min_screen_crossing: float = 0.18
## 出场点到摄像机的最远距离（米），避免远景中的奶蛋过小。
@export_range(5.0, 80.0, 1.0) var max_sample_distance: float = 18.0
## 每次出场正面持续朝向摄像机的概率；其余时候面向行进方向。
@export_range(0.0, 1.0, 0.05) var face_camera_probability: float = 0.8
## 避免连续重复最近几条路线，零表示完全独立随机。
@export_range(0, 10, 1) var route_memory: int = 5

@onready var _actor: CharacterBody3D = $奶蛋
@onready var _timer: Timer = $AppearanceTimer
@onready var _pool: CollisionShape3D = $PoolExclusion/CollisionShape3D

var _rng := RandomNumberGenerator.new()
var _spawn_due: bool = false
var _active_time: float = 0.0
var _space: PhysicsDirectSpaceState3D
var _clearance := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _recent_routes: Array[PackedVector3Array] = []
var exiting: bool = false
var _need_route: bool = false
var _route_retry_left: float = 0.0
var _exit_path := PackedVector3Array()


## 随机定时器只提出出场请求；物理帧中检查场景后才真正出场。
func _ready() -> void:
	_rng.randomize()
	_actor.movement_guard = _movement_allowed
	_actor.crossing_finished.connect(_on_leg_finished)
	_query.shape = _clearance
	_query.exclude = [_actor.get_rid()]
	_query.collision_mask = _actor.collision_mask
	_timer.timeout.connect(func() -> void: _spawn_due = true)
	_timer.start(_random_delay(first_delay_min, first_delay_max))


## 未退场时不启用第二只；每次出场都按摄像机当前视野重新选路线。
func _physics_process(delta: float) -> void:
	_space = get_world_3d().direct_space_state
	if _actor.active:
		_active_time += delta
		_route_retry_left = maxf(0.0, _route_retry_left - delta)
		if not exiting and _active_time >= roam_duration:
			exiting = true
			_need_route = true
			_exit_path.clear()
		if exiting and _fully_offscreen(_actor.global_position):
			_actor.deactivate()
			# 冷却从真正离屏时开始，移动和寻找出口期间不累计等待时间。
			_spawn_due = false
			_timer.start(maxf(0.1, respawn_delay))
			return
		if _need_route and _route_retry_left <= 0.0:
			_assign_next_leg()
		return
	if not _spawn_due:
		return
	_spawn_due = false
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		_timer.start(retry_delay)
		return
	_space = get_world_3d().direct_space_state
	# 检测完整弹跳所占的空间，不只检查起点和终点。
	_clearance.radius = 0.33
	_clearance.height = 0.66 + _actor.jump_height + 0.06
	var route: PackedVector3Array = _choose_route()
	if route.size() != 2:
		_timer.start(retry_delay)
		return
	_active_time = 0.0
	exiting = false
	_need_route = false
	_route_retry_left = 0.0
	_exit_path.clear()
	var look_camera: Camera3D = camera if _rng.randf() < face_camera_probability else null
	_actor.begin_crossing(route[0], route[1], look_camera)
	_recent_routes.append(route)
	while _recent_routes.size() > route_memory:
		_recent_routes.pop_front()
	_timer.stop()


func _random_delay(minimum: float, maximum: float) -> float:
	return _rng.randf_range(maxf(0.1, minf(minimum, maximum)), maxf(0.1, maxf(minimum, maximum)))


## 随机位置覆盖整个可见地面；在多条可行路线中按区域均衡抽取。
## 找不到安全穿行路线时推迟出场，绝不退回到不安全的位置。
func _choose_route() -> PackedVector3Array:
	var points: Array[Vector3] = []
	var screen_points: Array[Vector2] = []
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	# 分层随机采样覆盖整个屏幕，减少被泳池占据大部分画面时的空等。
	for attempt in 864:
		var uv := Vector2((attempt % 36 + _rng.randf()) / 36.0, (floori(attempt / 36.0) + _rng.randf()) / 24.0)
		uv = Vector2(0.06, 0.08) + uv * Vector2(0.88, 0.84)
		var pixel: Vector2 = uv * viewport_size
		var origin: Vector3 = camera.project_ray_origin(pixel)
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pixel) * 80.0, _actor.collision_mask, [_actor.get_rid()])
		var hit: Dictionary = _space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var point: Vector3 = hit.position
		if point.distance_to(camera.global_position) > max_sample_distance:
			continue
		if absf(point.y - ground_height) > ground_tolerance or (hit.normal as Vector3).y < 0.95:
			continue
		if not _point_safe(point):
			continue
		points.append(point)
		screen_points.append(uv)
	if points.size() < 2:
		return PackedVector3Array()
	var routes: Array[PackedVector3Array] = []
	var regions: Array[Vector2i] = []
	var region_counts: Dictionary = {}
	var tested_pairs: Dictionary = {}
	var required_span: float = min_screen_crossing * _rng.randf_range(0.8, 1.35)
	var airtime: float = 2.0 * sqrt(2.0 * _actor.jump_height / _actor.gravity)
	var average_speed: float = _actor.move_speed * airtime / (airtime + _actor.hop_pause + 0.05)
	for attempt in 3000:
		var start_index: int = _rng.randi_range(0, points.size() - 1)
		var end_index: int = _rng.randi_range(0, points.size() - 1)
		var pair := Vector2i(mini(start_index, end_index), maxi(start_index, end_index))
		if tested_pairs.has(pair):
			continue
		tested_pairs[pair] = true
		var start_uv: Vector2 = screen_points[start_index]
		var end_uv: Vector2 = screen_points[end_index]
		var screen_span: float = start_uv.distance_to(end_uv)
		if screen_span < minf(required_span, 0.12):
			continue
		var distance: float = points[start_index].distance_to(points[end_index])
		if distance < 1.5 or distance > minf(max_leg_distance, average_speed * 10.0):
			continue
		if _segment_safe(points[start_index], points[end_index]):
			var route := PackedVector3Array([points[start_index], points[end_index]])
			var middle_uv: Vector2 = (start_uv + end_uv) * 0.5
			var region := Vector2i(floori(middle_uv.x * 6.0), floori(middle_uv.y * 4.0))
			routes.append(route)
			regions.append(region)
			region_counts[region] = int(region_counts.get(region, 0)) + 1
			if routes.size() >= 80:
				break
	if routes.is_empty():
		return PackedVector3Array()
	# 按区域数量校正权重，防止面积大的安全区域垄断所有出场。
	# 最近走过的起终点及路线中部都会降权，反向走同一条也算重复。
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for index in routes.size():
		var route: PackedVector3Array = routes[index]
		var weight: float = 1.0 / int(region_counts[regions[index]])
		var uv_start: Vector2 = camera.unproject_position(route[0]) / viewport_size
		var uv_end: Vector2 = camera.unproject_position(route[1]) / viewport_size
		if uv_start.distance_to(uv_end) < required_span:
			weight *= 0.35
		for previous in _recent_routes:
			var middle_distance: float = ((route[0] + route[1]) * 0.5).distance_to((previous[0] + previous[1]) * 0.5)
			var start_distance: float = minf(route[0].distance_to(previous[0]), route[0].distance_to(previous[1]))
			weight *= lerpf(0.15, 1.0, clampf(minf(middle_distance, start_distance) / 2.5, 0.0, 1.0))
		weights.append(weight)
		total_weight += weight
	var choice: float = _rng.randf() * total_weight
	for index in routes.size():
		choice -= weights[index]
		if choice <= 0.0:
			return routes[index]
	return routes.back()


## 泳池按水平投影禁入：跳到水面上方也视为进入禁区。
func is_in_pool(point: Vector3) -> bool:
	var local: Vector3 = _pool.to_local(point)
	var box := _pool.shape as BoxShape3D
	return absf(local.x) <= box.size.x * 0.5 + pool_margin and absf(local.z) <= box.size.z * 0.5 + pool_margin


## 按实际身体和跳跃高度留出画面边距，避免从屏幕中间突然越界。
func is_position_allowed(point: Vector3) -> bool:
	if not is_instance_valid(camera) or is_in_pool(point):
		return false
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var frame := Rect2(viewport_size * 0.025, viewport_size * 0.95)
	var right: Vector3 = camera.global_basis.x * 0.34
	for sample: Vector3 in [point - right, point + right, point + Vector3.UP * 0.72]:
		if not camera.is_position_in_frustum(sample) or not frame.has_point(camera.unproject_position(sample)):
			return false
	return true


func _point_safe(point: Vector3) -> bool:
	if not is_position_allowed(point) or not is_position_allowed(point + Vector3.UP * (_actor.jump_height + 0.1)):
		return false
	return _clear_at(point)


func _clear_at(point: Vector3) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (_clearance.height * 0.5 + 0.035))
	_query.motion = Vector3.ZERO
	return _space.intersect_shape(_query, 1).is_empty()


## 连续扫掠防穿障碍，分段探测地面及泳池，保证整条线路都能走。
func _segment_safe(start: Vector3, destination: Vector3, keep_visible: bool = true) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * (_clearance.height * 0.5 + 0.035))
	_query.motion = destination - start
	var sweep: PackedFloat32Array = _space.cast_motion(_query)
	if sweep[0] < 1.0:
		return false
	var steps: int = maxi(1, ceili(start.distance_to(destination) / 0.15))
	for index in range(steps + 1):
		var point: Vector3 = start.lerp(destination, float(index) / steps)
		if is_in_pool(point):
			return false
		if keep_visible:
			if not is_position_allowed(point) or not is_position_allowed(point + Vector3.UP * (_actor.jump_height + 0.1)):
				return false
			# 镜头内路线需要可见；出口路线可以穿过屏幕边缘。
			var sight := PhysicsRayQueryParameters3D.create(camera.global_position, point + Vector3.UP * 0.4, _actor.collision_mask, [_actor.get_rid()])
			if not _space.intersect_ray(sight).is_empty():
				return false
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.25, point - Vector3.UP * 0.25, _actor.collision_mask, [_actor.get_rid()])
		var hit: Dictionary = _space.intersect_ray(ray)
		if hit.is_empty() or absf((hit.position as Vector3).y - point.y) > 0.08:
			return false
	return true


## 一段走完只请求下一段，整个30秒活动期间实体始终保持存在。
func _on_leg_finished(reached: bool) -> void:
	_need_route = true
	if not reached:
		_exit_path.clear()


func _movement_allowed(point: Vector3) -> bool:
	if exiting:
		return not is_in_pool(point)
	return is_position_allowed(point)


## 从当前位置连续衔接路线；出口被挡时重新找路，绝不在画面中直接删除。
func _assign_next_leg() -> void:
	var start: Vector3 = _ground_at(_actor.global_position)
	if not start.is_finite():
		_route_retry_left = 0.5
		return
	if exiting:
		if _exit_path.is_empty():
			_exit_path = _choose_exit(start)
		if not _exit_path.is_empty():
			var next: Vector3 = _exit_path[0]
			_exit_path.remove_at(0)
			_actor.travel_to(next)
			_need_route = false
			return
	var destination: Vector3 = _choose_roam_target(start)
	if destination.is_finite():
		_actor.travel_to(destination)
		_need_route = false
		_recent_routes.append(PackedVector3Array([start, destination]))
		while _recent_routes.size() > route_memory:
			_recent_routes.pop_front()
	else:
		_route_retry_left = 0.5


func _ground_at(point: Vector3) -> Vector3:
	var top := Vector3(point.x, ground_height + ground_tolerance + 0.15, point.z)
	var bottom := Vector3(point.x, ground_height - ground_tolerance - 0.15, point.z)
	var ray := PhysicsRayQueryParameters3D.create(top, bottom, _actor.collision_mask, [_actor.get_rid()])
	var hit: Dictionary = _space.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.95:
		return Vector3(INF, INF, INF)
	var ground: Vector3 = hit.position
	if absf(ground.y - ground_height) > ground_tolerance:
		return Vector3(INF, INF, INF)
	return ground


## 屏幕坐标投射到参考地面，再检查实际地面；也可用于屏幕外的出口点。
func _screen_ground(uv: Vector2) -> Vector3:
	var pixel: Vector2 = uv * camera.get_viewport().get_visible_rect().size
	var plane := Plane(Vector3.UP, ground_height)
	var intersection: Variant = plane.intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
	if intersection == null:
		return Vector3(INF, INF, INF)
	var point: Vector3 = intersection
	if point.distance_to(camera.global_position) > max_sample_distance * 1.5:
		return Vector3(INF, INF, INF)
	return _ground_at(point)


## 随机换方向和路程；最近走过的路点降权，避免只在两个点之间往返。
func _choose_roam_target(start: Vector3) -> Vector3:
	var candidates: Array[Vector3] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for attempt in 280:
		var point: Vector3 = _screen_ground(Vector2(_rng.randf_range(0.04, 0.96), _rng.randf_range(0.12, 0.94)))
		if not point.is_finite() or not _point_safe(point):
			continue
		var distance: float = start.distance_to(point)
		if distance < 1.0 or distance > max_leg_distance or not _segment_safe(start, point):
			continue
		var weight: float = 1.0
		for previous in _recent_routes:
			var separation: float = minf(point.distance_to(previous[0]), point.distance_to(previous[1]))
			weight *= lerpf(0.2, 1.0, clampf(separation / 2.0, 0.0, 1.0))
		candidates.append(point)
		weights.append(weight)
		total += weight
		if candidates.size() >= 20:
			break
	var choice: float = _rng.randf() * total
	for index in candidates.size():
		choice -= weights[index]
		if choice <= 0.0:
			return candidates[index]
	return Vector3(INF, INF, INF)


## 优先直接走到屏幕外；有障碍时用局部网格寻找连续绕行路线。
func _choose_exit(start: Vector3) -> PackedVector3Array:
	var exits: Array[Vector3] = []
	for side in 4:
		for sample in 36:
			var along: float = (sample + _rng.randf()) / 36.0
			# 同时检查贴近边缘与更远的出口，避免远出口落在围栏另一侧。
			var margin: float = [0.06, 0.12, 0.2][sample % 3]
			var uv: Vector2
			match side:
				0: uv = Vector2(-margin, along)
				1: uv = Vector2(1.0 + margin, along)
				2: uv = Vector2(along, 1.1 + margin)
				_: uv = Vector2(along, -margin)
			var point: Vector3 = _screen_ground(uv)
			if not point.is_finite() or is_in_pool(point) or not _clear_at(point):
				continue
			if _fully_offscreen(point) and _fully_offscreen(point + Vector3.UP * (_actor.jump_height + 0.1)):
				exits.append(point)
	var best := PackedVector3Array()
	var best_length: float = INF
	for destination in exits:
		var distance: float = start.distance_to(destination)
		if distance < best_length and _segment_safe(start, destination, false):
			best = PackedVector3Array([destination])
			best_length = distance
	if not best.is_empty():
		return best
	return _find_exit_detour(start, exits)


## 网格只用于退场规划，不生成场景节点；每条连接仍经过泳池和碰撞验证。
func _find_exit_detour(start: Vector3, exits: Array[Vector3]) -> PackedVector3Array:
	var graph := AStar3D.new()
	var cells: Dictionary = {}
	graph.add_point(0, start)
	cells[Vector2i.ZERO] = 0
	for x in range(-16, 17):
		for z in range(-16, 17):
			if x == 0 and z == 0:
				continue
			var point: Vector3 = _ground_at(start + Vector3(x * 0.5, 0, z * 0.5))
			if not point.is_finite() or not _point_safe(point):
				continue
			var id: int = graph.get_available_point_id()
			graph.add_point(id, point)
			cells[Vector2i(x, z)] = id
	for cell: Vector2i in cells:
		var id: int = cells[cell]
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			if not cells.has(cell + offset):
				continue
			var neighbor: int = cells[cell + offset]
			if _segment_safe(graph.get_point_position(id), graph.get_point_position(neighbor)):
				graph.connect_points(id, neighbor)
	var inside_ids: PackedInt64Array = graph.get_point_ids()
	var best := PackedVector3Array()
	var best_length: float = INF
	for destination in exits:
		var exit_id: int = graph.get_available_point_id()
		graph.add_point(exit_id, destination)
		for id in inside_ids:
			var point: Vector3 = graph.get_point_position(id)
			if point.distance_to(destination) < 4.0 and _segment_safe(point, destination, false):
				graph.connect_points(id, exit_id)
		var path: PackedVector3Array = graph.get_point_path(0, exit_id)
		var length: float = 0.0
		for index in range(1, path.size()):
			length += path[index - 1].distance_to(path[index])
		if path.size() >= 2 and length < best_length:
			best = path
			best_length = length
		graph.remove_point(exit_id)
	# 合并能直达的连续网格路点，避免每半米都停下来重新起跳。
	var simplified := PackedVector3Array()
	var anchor: Vector3 = start
	var index: int = 1
	while index < best.size():
		var next_index: int = index
		for candidate in range(best.size() - 1, index, -1):
			if _segment_safe(anchor, best[candidate], false):
				next_index = candidate
				break
		simplified.append(best[next_index])
		anchor = best[next_index]
		index = next_index + 1
	return simplified


## 检查整个模型包围盒，而非仅中心点，防止走到边缘时还有半个身体就消失。
func _fully_offscreen(point: Vector3) -> bool:
	if not is_instance_valid(camera):
		return false
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var in_front: int = 0
	for x in [-0.4, 0.4]:
		for y in [0.0, 0.8]:
			for z in [-0.4, 0.4]:
				var corner: Vector3 = point + Vector3(x, y, z)
				if camera.is_position_behind(corner):
					continue
				in_front += 1
				var pixel: Vector2 = camera.unproject_position(corner)
				minimum = minimum.min(pixel)
				maximum = maximum.max(pixel)
	if in_front == 0:
		return true
	var body_rect := Rect2(minimum, maximum - minimum)
	return not camera.get_viewport().get_visible_rect().intersects(body_rect)
