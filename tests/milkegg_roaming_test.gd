extends SceneTree

## 无界面集成测试：活动30秒、实际走出镜头、隐藏10秒、随机重生且始终只有一只。
## 可选参数依次为窗口宽度、高度、随机种子；按固定60帧运行12分钟模拟。
var legs: int = 0
var blocked: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	root.size = Vector2i(int(args[0]), int(args[1])) if args.size() >= 2 else Vector2i(1152, 648)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var manager: Node = scene.get_node("MilkeggEncounter")
	var actor: CharacterBody3D = manager.get_node("奶蛋")
	manager.get("_rng").seed = int(args[2]) if args.size() >= 3 else 81234
	actor.crossing_finished.connect(func(reached: bool) -> void:
		if reached: legs += 1
		else: blocked += 1)
	var was_active: bool = false
	var was_exiting: bool = false
	var spawns: int = 0
	var departures: int = 0
	var violations: int = 0
	var invisible_removals: int = 0
	var first_frame: int = 0
	var leg_start: int = 0
	var previous_position := Vector3.ZERO
	var distance_traveled: float = 0.0
	var lifetime_min: float = INF
	var lifetime_max: float = 0.0
	var last_departure_frame: int = -1
	var gap_min: float = INF
	var gap_max: float = 0.0
	for frame in 43200:
		await physics_frame
		var active: bool = actor.active
		var exiting: bool = manager.exiting
		if active and not was_active:
			spawns += 1
			if last_departure_frame >= 0:
				var gap: float = (frame - last_departure_frame) / 60.0
				gap_min = minf(gap_min, gap)
				gap_max = maxf(gap_max, gap)
				if absf(gap - manager.respawn_delay) > 0.1:
					violations += 1
					print("退场后等待时间不符：", gap)
			first_frame = frame
			leg_start = legs
			distance_traveled = 0.0
			was_exiting = false
		if active:
			if not manager.get_node("AppearanceTimer").is_stopped(): violations += 1
			if manager.is_in_pool(actor.global_position): violations += 1
			if not exiting and not manager.is_position_allowed(actor.global_position): violations += 1
			if not actor.visible or actor.get_node("CollisionShape3D").disabled: violations += 1
			if was_active:
				var step: Vector3 = actor.global_position - previous_position
				if step.length() > 0.2: violations += 1
				distance_traveled += Vector2(step.x, step.z).length()
			if exiting and not was_exiting:
				var elapsed: float = (frame - first_frame) / 60.0
				print("开始退场 t=", elapsed, " 已完成路段=", legs - leg_start, " 移动距离=", snappedf(distance_traveled, 0.01))
				if elapsed < 29.9 or elapsed > 30.1 or legs - leg_start < 3 or distance_traveled < 12.0:
					violations += 1
			if (frame - first_frame) / 60.0 > 65.0:
				print("退场卡住：", actor.global_position, " 目的地=", actor.get("_destination"), " 等待路线=", actor.waiting_for_route)
				violations += 1
				break
		if was_active and not active:
			departures += 1
			last_departure_frame = frame
			var lifetime: float = (frame - first_frame) / 60.0
			lifetime_min = minf(lifetime_min, lifetime)
			lifetime_max = maxf(lifetime_max, lifetime)
			if not manager._fully_offscreen(actor.global_position): invisible_removals += 1
			if lifetime < 30.0: violations += 1
			print("完全离屏后退场，总时长=", snappedf(lifetime, 0.01), " 位置=", actor.global_position)
		if not active and (actor.visible or not actor.get_node("CollisionShape3D").disabled): violations += 1
		if scene.find_children("奶蛋", "CharacterBody3D", true, false).size() != 1: violations += 1
		previous_position = actor.global_position
		was_active = active
		was_exiting = exiting
	var passed: bool = spawns >= 12 and departures >= spawns - 1 and violations == 0 and invisible_removals == 0
	print("离屏后等待范围=", Vector2(gap_min, gap_max), " 秒")
	print("统计：出场=", spawns, " 离屏退场=", departures, " 路段=", legs, " 阻挡重选=", blocked, " 总时长范围=", Vector2(lifetime_min, lifetime_max), " 安全违规=", violations, " 镜头内删除=", invisible_removals)
	print("PASS" if passed else "FAIL")
	scene.free()
	quit(0 if passed else 1)
