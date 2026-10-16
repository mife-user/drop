extends Area3D
class_name HeavenDoor

## 天堂之门：门槛容器装满的那一刻，池边这根光柱亮起来；玩家走进去就进入最终场景。
##
## 只认一个 WaterSink 的水位和 filled 信号 —— 不认识水池、也不认识水是谁倒的，
## 和「水量灯」「水量字幕」是同一个写法。想把门槛换成别的容器（木碗、以后新摆的水缸），
## 在检查器里把 sink 拖过去就行，脚本一行不用改。
##
## **不能只等 filled 信号**：它只在「从不满到满」那一瞬间发一次，
## 场景一加载就已经是满的容器（编辑器里预填、以后读档）不会再发。所以 _ready 里先自己读一次水位。
##
## 光柱和补光灯都是本节点的子节点，亮不亮只是改它们的透明度和能量 —— **节点一直都在**，
## 所以位置、大小、材质全在编辑器里摆，脚本不碰它们的 transform。
##
## 它只管「门」：什么时候亮、谁走进来了。**切场景是别人的事**（见 scripts/结局/结局黑幕.gd）——
## 门只喊一声 entered，至于这一声之后是黑屏、是放音效、还是什么都不做，门不关心。

## 玩家走进来（光柱已经亮着）时发出一次。
signal entered()

## 门槛容器：把「场景/PoolExclusion/吸水区」拖过来。
## 留空 = 光柱永远不亮（可以先把节点摆着当占位）。
@export var sink: WaterSink
## 只有这个玩家走进来才算数 —— 水团是 Area3D 不会触发，但**炮台那种带碰撞体的会**，
## 所以别把门开在炮台旁边，也别指望「谁都算」。
@export var player: CharacterBody3D
## 调试开关：勾上就无视门槛，一开局光柱就是亮的。
## （水池容量填得大的时候，正常玩到满要很久，勾这个可以先看亮起来、切场景长什么样。）
@export var always_on: bool = false

@export_group("光柱")
## 那根柱子（本节点下的 MeshInstance3D）。它的 material_override 得是 StandardMaterial3D，
## 脚本靠改这份材质的透明度来亮暗；材质会在运行时复制一份，改的不会是场景里存的那份。
@export var beam: MeshInstance3D
## 柱子旁边的补光灯（本节点下的 OmniLight3D），跟着一起亮。
@export var beam_light: OmniLight3D
## 亮起来用几秒；填 0 = 直接亮。
@export_range(0.0, 10.0, 0.05) var light_up_time: float = 1.2
## 亮到顶时补光灯的能量。
@export_range(0.0, 32.0, 0.1) var lit_energy: float = 6.0
## 没亮的时候柱子还剩几成不透明度。填 0 = 完全看不见（光柱是「凭空烧起来」的）；
## 填 0.2 左右就是一根暗柱子一直杵在那儿，满了才亮。
@export_range(0.0, 1.0, 0.01) var dim_ratio: float = 0.0

var _lit: bool = false              # 光柱亮了吗（也是「走进去算不算数」的闸）
var _fired: bool = false            # entered 只喊一次
var _level: float = 0.0             # 当前亮到几成（0~1），tween 的插值对象
var _beam_mat: StandardMaterial3D   # 柱子材质的运行时副本
var _base_alpha: float = 0.0        # 场景里给材质配的那个透明度，亮到顶就是它
var _tween: Tween


func _ready() -> void:
	# 材质复制一份自己用：亮起来改的是副本，不会写回场景里那份资源
	#（否则以后同一次运行里摆第二个门，两个门会共享同一个透明度，一起亮一起暗）
	if is_instance_valid(beam) and beam.material_override is StandardMaterial3D:
		var source := beam.material_override as StandardMaterial3D
		_beam_mat = source.duplicate() as StandardMaterial3D
		beam.material_override = _beam_mat
		_base_alpha = _beam_mat.albedo_color.a
	elif is_instance_valid(beam):
		push_warning("天堂之门：光柱没挂 StandardMaterial3D 的 material_override，亮起来只会亮灯、柱子不变。")

	body_entered.connect(_on_body_entered)
	if not is_instance_valid(player):
		push_warning("天堂之门：没指定玩家，任何碰撞体走进来都会触发。")

	if always_on:
		set_lit(true)
		return
	if not is_instance_valid(sink):
		push_warning("天堂之门：没接门槛容器，光柱永远不会亮 —— 把水池的吸水区拖到 sink 上。")
		_apply_level(0.0)
		return
	sink.filled.connect(_on_sink_filled)
	# 场景一加载门槛就已经满了（编辑器里预填、以后读档）也要认，不能只等信号
	if sink.amount >= sink.capacity:
		_on_sink_filled()
	else:
		_apply_level(0.0)


## 门槛容器第一次装满：点亮光柱。
func _on_sink_filled() -> void:
	set_lit(true)


## 点亮 / 熄灭。重复调用无副作用；中途反过来调也不会跳一下（从当前进度接着走）。
func set_lit(lit: bool) -> void:
	if _lit == lit:
		return
	_lit = lit
	if is_instance_valid(_tween) and _tween.is_valid():
		_tween.kill()
	var target: float = 1.0 if lit else 0.0
	if light_up_time <= 0.0:
		_apply_level(target)
	else:
		_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_apply_level, _level, target, light_up_time)
	# 亮起来的那一刻玩家可能就站在这根柱子里面（他多半就在池边射水），
	# 那种情况 body_entered 不会再响 —— 所以补一次点名，不然门开了他得先走开再走回来。
	if lit:
		_enter_if_standing_inside()


## 把「亮到几成」落到柱子和灯上。tween 每帧调它；没有动画时也直接调。
func _apply_level(level: float) -> void:
	_level = level
	if is_instance_valid(beam):
		# 全暗的时候把节点藏起来：省一次绘制，也让全透明物体不参与排序。
		# dim_ratio 不为 0 时暗着也要看得见（那就是一根等着被点亮的暗柱子）。
		beam.visible = _lit or level > 0.001 or dim_ratio > 0.0
	if is_instance_valid(beam_light):
		beam_light.light_energy = lit_energy * level
	if _beam_mat != null:
		var color: Color = _beam_mat.albedo_color
		color.a = _base_alpha * lerpf(dim_ratio, 1.0, level)
		_beam_mat.albedo_color = color


## 补点名：等一个物理帧让重叠列表刷新，然后看看玩家是不是已经站在柱子里了。
func _enter_if_standing_inside() -> void:
	await get_tree().physics_frame
	if not _lit or _fired:
		return
	for body: Node3D in get_overlapping_bodies():
		if not is_instance_valid(player) or body == player:
			_on_body_entered(body)
			return


## 有人进了柱子：是玩家、光柱也亮着、而且还没喊过，就喊一声 entered。
func _on_body_entered(body: Node3D) -> void:
	if not _lit or _fired:
		return
	if is_instance_valid(player) and body != player:
		return
	_fired = true
	if entered.get_connections().is_empty():
		push_warning("天堂之门：光柱亮着，但 entered 没有人接 —— 走进去不会有任何反应。")
	entered.emit()
