extends Node

## 手臂跟随视角：摄像机抬头 / 低头时，让一根骨骼（默认前臂「骨骼.009」）跟着上下摆，
## 并让水枪跟着手骨骼走 —— 否则手臂一动，枪就留在原地从手心里滑开。
##
## **这是纯表现，一点玩法都不影响**：水的出膛方向和落点仍然由 水枪.gd 按准星现算，
## 所以这里的比例、限位哪怕调歪了，也只是"看起来不对"，打水照样准。
##
## 机制是「开机记三样基准，之后每帧只往上叠增量、从不写绝对值」：
## 1. **骨骼当前姿态** —— 就是你在编辑器里摆好、存进 人物.tscn 的 bones/N/rotation 的那个旋转。
##    所以初始状态和你手调的一模一样，不会一开跑就被代码掰直。
## 2. **基准俯仰** —— 开机那一刻摄像机的俯仰角。手臂的零点 = 开机视角：
##    主场景摄像机开局就低着约 7°，拿"水平 0°"当零点会一开局手臂就偏。
## 3. **水枪相对手骨骼的变换** —— 开机时枪在哪儿，以后就一直在手里的那个位置，
##    你在编辑器里摆好的枪位一个像素都不用重调。
##
## 为什么不能"绕骨骼自己的 X 轴转"：骨骼的 XYZ 和人物的左右轴通常不重合
## （「骨骼.009」的静止朝向本身就扭着，编辑器里摆的姿态更是离静止姿态很远），
## 隔着姿态去转骨骼自己的轴，手臂会甩到奇怪的方向。所以开机时先用骨骼的**静止朝向**
## 把「摄像机上下转的那根轴」反解到骨骼局部空间里存下来，之后只绕那一根轴转。


## 骨架（挂 Skeleton3D 的那个节点）。留空时自动在本节点的父节点下面找第一个。
@export var skeleton: Skeleton3D
## 要摆的骨骼名，直接填 Skeleton3D 里看到的那个名字。
## 「人物.fbx」里端着水枪那只手（−X 侧）是：骨骼.008 上臂 / 骨骼.009 前臂 / 骨骼.009_end 手。
## **骨骼.008 和 骨骼.009 是两根不同的骨头**，改这里之前先在编辑器里对着骨列表看清名字。
@export var arm_bone_name: StringName = &"骨骼.009"
## 手持物跟着哪根骨骼走。默认 骨骼.009_end（手）；手部网格其实是刚性绑在 骨骼.009 上的，
## 所以这一根换成 骨骼.009 效果一样。
@export var hand_bone_name: StringName = &"骨骼.009_end"
## 手持物（水枪）。留空 = 不让它跟手，只摆手臂（手就会从枪把上滑开，只在你不在乎时才这么用）。
@export var held_item: Node3D
## 摄像机，手臂读它的 rotation.x 当俯仰角。留空时自动取当前视口的摄像机。
@export var camera: Camera3D
## 手臂摆多少：1.0 = 和视角一比一，0.5 = 只摆一半。
## **实测发现抬头时手臂反而往下走，就把这里填成负数** —— 改一个数就行，不用动代码。
@export_range(-2.0, 2.0, 0.05) var pitch_ratio: float = 0.5
## 最大摆角（度）：无论视角抬多高，手臂最多偏离基准这么多，防止抬头到 89° 时手臂翻过头。
@export_range(0.0, 89.0, 1.0) var max_angle_degrees: float = 40.0
## 平滑速度（度/秒）：0 = 完全不平滑，手臂和视角严格同步；
## 填几百就是手臂跟得慢一点、显得更"重"。
@export_range(0.0, 3000.0, 10.0) var smoothing: float = 0.0

var _arm_index: int = -1                             # 要摆的骨骼索引，-1 = 没找到
var _hand_index: int = -1                            # 手骨骼索引，-1 = 不跟手
var _base_pose: Quaternion = Quaternion.IDENTITY     # 基准姿态：编辑器里摆的那个旋转
var _swing_axis: Vector3 = Vector3.RIGHT             # 摄像机的俯仰轴，已换算到骨骼局部空间
var _base_pitch: float = 0.0                         # 基准俯仰（开机视角），弧度
var _item_offset: Transform3D = Transform3D.IDENTITY # 水枪相对手骨骼的变换
var _angle: float = 0.0                              # 当前实际摆角（度），平滑用


## 开机只做一件事：把三样基准记下来。之后每帧都只是"基准 + 增量"。
## 放在 _ready 里是安全的：摄像机、骨架、水枪在同一帧里都已经就位，
## 而且开始界面只切 current、不会转摄像机，所以这里读到的俯仰就是开局视角。
func _ready() -> void:
	if not is_instance_valid(skeleton):
		skeleton = _find_skeleton()
	if not is_instance_valid(skeleton):
		push_warning("手臂俯仰：场景里没找到 Skeleton3D，本节点不工作")
		return
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	_arm_index = skeleton.find_bone(String(arm_bone_name))
	if _arm_index < 0:
		push_warning("手臂俯仰：骨架里没有叫「%s」的骨骼，本节点不工作" % arm_bone_name)
		return
	# 基准一：骨骼当前姿态（编辑器里摆好、存进 人物.tscn 的那个旋转）
	_base_pose = skeleton.get_bone_pose_rotation(_arm_index)
	# 摆动的转轴：把「摄像机上下转的那根轴」换算到骨骼自己的局部空间。
	# 用骨骼**没被本脚本动过时**的朝向做换算，所以编辑器里怎么摆都算得对。
	if is_instance_valid(camera):
		# 这里只要方向，所以**先剥掉缩放再乘**：骨架节点上带着 FBX 的单位缩放（约 ×100），
		# 直接用 inverse() 会把单位向量缩成 0.01 长，Quaternion(axis, angle) 会当场报
		# "The axis ... must be normalized" 并拒绝执行。
		var neutral: Basis = _bone_neutral_basis(_arm_index).orthonormalized()
		var axis_world: Vector3 = camera.global_transform.basis.x.normalized()
		_swing_axis = (neutral.inverse() * axis_world).normalized()
		# 基准二：开机视角
		_base_pitch = camera.rotation.x
	# 基准三：水枪相对手骨骼的变换（在编辑器里摆的枪位会被原样记下来）
	_hand_index = skeleton.find_bone(String(hand_bone_name))
	if is_instance_valid(held_item) and _hand_index >= 0:
		_item_offset = _hand_world().affine_inverse() * held_item.global_transform


## 每帧两件事：把骨骼摆到「基准 + 增量」，再把水枪摆回手上。
## 用 _process 不用 _physics_process：这是纯视觉，跟渲染帧走最顺。
func _process(delta: float) -> void:
	if _arm_index < 0:
		return
	var target: float = _target_angle()
	if smoothing > 0.0:
		_angle = move_toward(_angle, target, smoothing * delta)
	else:
		_angle = target
	# **左乘**增量 = 在父骨骼的坐标系里施加，等价于绕这根骨骼的根部（关节）转 ——
	# 整条手臂连着肘、手、枪一起摆，而不是把骨骼本身拧一下。
	# 姿态永远是「增量 × 基准」，不写绝对值，编辑器里摆的那个旋转一个字都不会丢。
	skeleton.set_bone_pose_rotation(_arm_index, Quaternion(_swing_axis, deg_to_rad(_angle)) * _base_pose)
	if is_instance_valid(held_item) and _hand_index >= 0:
		held_item.global_transform = _hand_world() * _item_offset


## 目标摆角（度）：视角相对开机时偏了多少 → 乘比例 → 卡上限。
## player.gd 里维护的是「抬头 = camera.rotation.x 变大」，所以这里直接用差值。
## 摄像机为了对上人物正面转了 180°，但它的 rotation.x 只表示俯仰、不含偏航，person 转身也不影响。
func _target_angle() -> float:
	if not is_instance_valid(camera):
		return 0.0
	var pitch_delta: float = rad_to_deg(camera.rotation.x - _base_pitch)
	return clampf(pitch_delta * pitch_ratio, -max_angle_degrees, max_angle_degrees)


## 这根骨骼「没被本脚本动过」时在世界里的朝向：
## 骨架自己的朝向 × 父骨骼的**当前姿态** × 本骨骼的静止姿态。
## 父骨骼用当前姿态而不是静止姿态，是因为编辑器里可能把上臂也摆过。
func _bone_neutral_basis(idx: int) -> Basis:
	var parent_basis: Basis = Basis()
	var parent: int = skeleton.get_bone_parent(idx)
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent).basis
	return skeleton.global_transform.basis * parent_basis * skeleton.get_bone_rest(idx).basis


## 手骨骼在世界里的变换 —— 水枪摆到这儿，再叠开机时记下的那个偏移。
func _hand_world() -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hand_index)


## 没在检查器里指定骨架时，顺着父节点往下找第一个 Skeleton3D。
## owned 传 false，这样连实例（FBX / 人物.tscn）内部的节点也找得到。
func _find_skeleton() -> Skeleton3D:
	var host: Node = get_parent()
	if host == null:
		return null
	var found: Array[Node] = host.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D
