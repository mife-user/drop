extends CharacterBody3D

## 蓝色小肥鱼：会自己在出生点附近散步、发呆、隔几秒看一眼玩家、挥手、
## 害羞时双手挡在嘴/脸颊前、走累了坐在地上抱膝；她还是一个饮水区：
## 水团飞进「饮水区」会被她喝掉；每团水只播放约 1 秒的闭眼/吞咽动画，
## 之后立刻恢复原本状态，剩下的水在后台安静消耗；喝满时才开心地跳两下。
##
## 模型（蓝色小肥鱼.glb）有 146 根骨骼，但**没有任何动画片段**，绑定姿势还是 T-pose。
## 所以这里不用 AnimationPlayer，而是每帧直接摆 Skeleton3D 的骨骼姿态：
##   1. 每帧先算一个基础姿态（手臂从 T-pose 放下来）；
##   2. 所有动作（呼吸、摇尾、抖耳朵、眨眼、走路、挥手、捂脸、坐下……）都是在它之上叠加的增量。
##
## 她**没有下颌骨，也没有表情变形**：脸是画在贴图上的，所以「张嘴」是一个
## 跟随 head 骨骼的嘴部 + 闭眼睫毛 overlay（「嘴巴挂点/嘴巴」「嘴巴挂点/眼睫」），
## 嘴片只在吞咽时显示，睫毛片在喂水、害羞和普通眨眼闭眼时显示。
##
## 走路是在出生点附近随机选点（roam_radius），玩家靠近会停下来看你。
## 所有数值都在检查器里，按「基础姿态 / 待机 / 漫步 / 互动 / 喝水 / 装满庆祝 / 坐下」分组。
##
## 场景脚下没有地面时（比如直接打开本场景预览）会自动进入「原地待机」模式：
## 不移动、不往下掉，但呼吸 / 眨眼 / 摇尾照常，方便单独看动作。
##
## 注意：**编辑器里的模型仍然是 T-pose** —— 骨骼动作是运行时摆的。
## 想直接看效果，运行 scenes/蓝色小肥鱼_预览.tscn（带相机和地板）。


## 玩家组名。player.gd 在 _enter_tree 里把自己加进这个组，
## 这里只按组找玩家，不依赖主场景里节点的具体名字。
const GROUP_PLAYER: StringName = &"player"
## 水团组名。水块.gd 用 add_to_group("water") 声明自己的身份。
const GROUP_WATER: StringName = &"water"

## 模型的正面朝 +Z（不是 Godot 默认的 -Z），所以下面统一用这个常量表示「向前」。
## 注意 Vector3.FORWARD 在 Godot 里是 (0, 0, -1)，不要拿它当这里的「前」。
const AXIS_FORWARD := Vector3(0.0, 0.0, 1.0)
const AXIS_RIGHT := Vector3(1.0, 0.0, 0.0)
const AXIS_UP := Vector3(0.0, 1.0, 0.0)

## 尾巴 5 节、两只耳朵各 4 节、后发/侧发各 4 节、刘海 3 节、裙摆左右各 2 节。
## 这些骨骼都是独立的，可以做出很生动的二次运动。
const TAIL_BONES: Array[StringName] = [&"WeiBa", &"WeiBa.001", &"WeiBa.002", &"WeiBa.003", &"WeiBa.004"]
const EAR_L_BONES: Array[StringName] = [&"ErDuo.L", &"ErDuo.L.001", &"ErDuo.L.002", &"ErDuo.L.003"]
const EAR_R_BONES: Array[StringName] = [&"ErDuo.R", &"ErDuo.R.001", &"ErDuo.R.002", &"ErDuo.R.003"]
const HAIR_BACK_BONES: Array[StringName] = [&"Hou_hair", &"Hou_hair.001", &"Hou_hair.002", &"Hou_hair.003"]
const HAIR_L_BONES: Array[StringName] = [&"Hou_hair.L", &"Hou_hair.L.001", &"Hou_hair.L.002", &"Hou_hair.L.003"]
const HAIR_R_BONES: Array[StringName] = [&"Hou_hair.R", &"Hou_hair.R.001", &"Hou_hair.R.002", &"Hou_hair.R.003"]
const BANGS_BONES: Array[StringName] = [&"LiuHai", &"LiuHai.001", &"LiuHai.002"]
const SKIRT_L_BONES: Array[StringName] = [&"Q_QunZi.L", &"Q_QunZi.L.001"]
const SKIRT_R_BONES: Array[StringName] = [&"Q_QunZi.R", &"Q_QunZi.R.001"]
## 耳朵每节的分担系数，越往耳尖摆得越少，整条耳朵才不会甩成一根鞭子。
const EAR_FALLOFF: Array[float] = [1.0, 0.6, 0.35, 0.2]

@export_group("基础姿态")

## 手臂从 T-pose 往两侧垂下多少度。
## 模型绑定姿势是双臂平举，运行时必须放下来，否则一直像晾衣架。
## **她的裙子很宽**：实测裙摆半径在腰部约 0.16~0.22 米，手完全垂下会插进裙子里。
## 32° 正好让手停在大裙摆外侧，看起来像双臂自然放松；想更贴身可以调大，但要留意穿模。
@export_range(0.0, 100.0, 1.0) var arm_down_degrees: float = 32.0

@export_group("待机")

## 呼吸幅度（度）：胸口每秒轻轻起伏的幅度。
@export_range(0.0, 10.0, 0.1) var breathe_degrees: float = 1.2
## 呼吸一个来回要多少秒。
@export_range(0.5, 20.0, 0.1) var breathe_period: float = 3.4
## 重心左右摇摆幅度（度）。
@export_range(0.0, 10.0, 0.1) var sway_degrees: float = 1.4
## 重心摇摆速度（弧度/秒）。
@export_range(0.0, 10.0, 0.1) var sway_speed: float = 1.1
## 待机时整个人上下起伏的高度（米），只动模型、不动碰撞。
@export_range(0.0, 0.1, 0.001) var idle_bob_height: float = 0.006

## 眨眼间隔最短（秒）。
@export_range(0.1, 30.0, 0.1) var blink_interval_min: float = 2.5
## 眨眼间隔最长（秒）。
@export_range(0.1, 60.0, 0.1) var blink_interval_max: float = 6.0
## 一次眨眼从闭到睁要多少秒。眨眼现在由「闭眼贴片」完成，不再压扁眼球。
@export_range(0.05, 1.0, 0.01) var blink_duration: float = 0.15
## 眨完一下后，有多大几率紧接着补眨第二下。
@export_range(0.0, 1.0, 0.01) var double_blink_chance: float = 0.25
## 连眨时两下之间的间隔（秒）。
@export_range(0.0, 1.0, 0.01) var double_blink_gap: float = 0.12

## 抖耳朵间隔最短（秒）。
@export_range(0.5, 60.0, 0.1) var ear_twitch_interval_min: float = 2.5
## 抖耳朵间隔最长（秒）。
@export_range(0.5, 120.0, 0.1) var ear_twitch_interval_max: float = 7.0
## 抖耳朵的幅度（度）。
@export_range(0.0, 45.0, 1.0) var ear_twitch_degrees: float = 16.0
## 一次抖耳朵持续多久（秒）。
@export_range(0.1, 2.0, 0.01) var ear_twitch_duration: float = 0.45
## 开心时两只耳朵竖起的角度（度）。
@export_range(0.0, 45.0, 1.0) var ear_perk_degrees: float = 8.0
## 害羞时两只耳朵垂下的角度（度）。
@export_range(0.0, 45.0, 1.0) var ear_droop_degrees: float = 10.0

## 尾巴**每一节**的摆幅（度）。5 节叠起来实际摆幅会更大，别一上来就调太大。
@export_range(0.0, 30.0, 0.5) var tail_wag_degrees: float = 7.0
## 尾巴摆动速度（弧度/秒）。
@export_range(0.0, 15.0, 0.1) var tail_wag_speed: float = 2.1

## 头发摆动幅度（度）。
@export_range(0.0, 15.0, 0.1) var hair_sway_degrees: float = 2.0
## 裙摆摆动幅度（度）。
@export_range(0.0, 15.0, 0.1) var skirt_sway_degrees: float = 2.0

## 原地小跳的高度（米）。
@export_range(0.0, 0.3, 0.005) var idle_hop_height: float = 0.10
## 两次原地小跳之间的最短间隔（秒）。
@export_range(1.0, 120.0, 0.5) var idle_hop_interval_min: float = 7.0
## 两次原地小跳之间的最长间隔（秒）。
@export_range(1.0, 300.0, 0.5) var idle_hop_interval_max: float = 15.0
## 一次小跳（起跳→落地）持续多久（秒）。
@export_range(0.15, 1.5, 0.01) var hop_duration: float = 0.42
## 起跳拉伸 / 落地压扁的幅度，0 = 关闭。
@export_range(0.0, 0.5, 0.01) var hop_squash: float = 0.10

@export_group("漫步")

## 是否允许自己走动。关掉 = 只站在原地做待机动作。
@export var auto_wander: bool = true
## 漫步范围半径（米）：以出生点为圆心，不会走超出这个圈。
@export_range(0.0, 10.0, 0.1) var roam_radius: float = 2.2
## 单次漫步的最短距离（米），避免原地挪一小步就停。
@export_range(0.1, 5.0, 0.1) var min_step_distance: float = 0.5
## 走路速度（米/秒）。她只有约 1 米高、腿很短，0.4 已经是小碎步了。
@export_range(0.05, 3.0, 0.05) var walk_speed: float = 0.4
## 转身速度：越大转得越快，越小越有「慢慢扭头」的感觉。
@export_range(0.5, 20.0, 0.1) var turn_speed: float = 6.0
## 一次发呆最短持续多少秒。
@export_range(0.2, 60.0, 0.1) var idle_duration_min: float = 2.0
## 一次发呆最长持续多少秒。
@export_range(0.2, 120.0, 0.1) var idle_duration_max: float = 6.0
## 走路时上下颠的幅度（米）。
@export_range(0.0, 0.1, 0.001) var walk_bob_height: float = 0.025
## 走路时身体前倾的幅度（度）。
@export_range(0.0, 15.0, 0.1) var walk_lean_degrees: float = 2.5
## 腿前后摆的幅度（度）。她的腿只有十几厘米，摆动幅度大一点才看得出在迈步。
@export_range(0.0, 45.0, 1.0) var leg_swing_degrees: float = 26.0
## 膝盖弯曲的幅度（度）。
@export_range(0.0, 60.0, 1.0) var knee_bend_degrees: float = 18.0
## 手臂前后摆的幅度（度）。
@export_range(0.0, 45.0, 1.0) var arm_swing_degrees: float = 10.0
## 走路相位推进速度（弧度/秒，全速时），越大步频越快。
## 默认值是按「腿长 0.13 米、摆幅 26°、走速 0.4 米/秒」估的，让脚尽量不打滑；
## 改了 walk_speed 或 leg_swing_degrees 之后，这里也可以按比例跟着调。
@export_range(0.0, 30.0, 0.5) var walk_cycle_speed: float = 10.5
## 重力加速度（米/秒²）。NPC 不需要玩家那么重，默认比玩家轻一点。
@export_range(0.0, 60.0, 0.5) var gravity: float = 16.0
## 被挡住多久算卡住（秒），到点就放弃这个目标、重新发呆再选路。
@export_range(0.2, 5.0, 0.1) var stuck_timeout: float = 1.0
## 出生点下方没有地面时，是否自动进入「原地待机」预览模式。
## 在独立场景里直接运行本场景时很有用；正式摆进有地面的场景后不影响。
@export var preview_when_no_ground: bool = true

@export_group("互动")

## 玩家靠近时是否在「看一眼」的窗口里转头 / 转身看玩家。
## 不是一直盯着：看一眼后会把视线移开，过几秒才可能再看。
@export var look_at_player: bool = true
## 看一眼持续的最短时间（秒）。
@export_range(0.5, 20.0, 0.1) var glance_hold_min: float = 1.8
## 看一眼持续的最长时间（秒）。
@export_range(0.5, 30.0, 0.1) var glance_hold_max: float = 3.2
## 移开视线的最短时间（秒）。
@export_range(0.5, 60.0, 0.1) var glance_away_min: float = 3.0
## 移开视线的最长时间（秒）。
@export_range(0.5, 120.0, 0.1) var glance_away_max: float = 7.0
## 移开一段时间后，如果玩家还在附近，有多大几率再看一眼。
@export_range(0.0, 1.0, 0.05) var glance_repeat_chance: float = 0.6
## 玩家进入这个距离（米）就会被注意到。
@export_range(0.5, 20.0, 0.1) var notice_radius: float = 3.2
## 玩家靠得比这个距离（米）更近时，会害羞地捂住脸退一小步。
@export_range(0.1, 10.0, 0.05) var shy_radius: float = 1.0
## 是否启用「第一次看到玩家时挥手」。
@export var wave_enabled: bool = true
## 两次挥手之间至少隔多少秒。
@export_range(0.0, 120.0, 0.5) var wave_cooldown: float = 20.0
## 一次挥手持续多久（秒）。
@export_range(0.5, 5.0, 0.05) var wave_duration: float = 1.5
## 挥手时手臂比平时抬高多少度（相对 T-pose 的平举位置）。
## **她的头很大**：抬太高、再弯肘，手会插进脸/头发里。默认抬到略高于肩膀，整条手臂一起摆。
@export_range(0.0, 90.0, 1.0) var wave_arm_raise_degrees: float = 55.0
## 挥手时小臂向上弯多少度。默认 0 = 整条手臂伸直地摆；调大要留意手会不会碰到大头。
@export_range(0.0, 120.0, 1.0) var wave_forearm_degrees: float = 0.0
## 挥手时整条手臂上下摆动的幅度（度）。
@export_range(0.0, 45.0, 1.0) var wave_swing_degrees: float = 14.0
## 挥手摆动的速度（弧度/秒）。
@export_range(1.0, 20.0, 0.5) var wave_speed: float = 8.0
## 是否启用「靠太近会害羞捂脸后退」。
@export var shy_enabled: bool = true
## 两次害羞之间至少隔多少秒。
@export_range(0.0, 60.0, 0.5) var shy_cooldown: float = 6.0
## 害羞后退持续多久（秒）。
@export_range(0.3, 5.0, 0.05) var shy_duration: float = 1.1
## 害羞时后退多远（米）。
@export_range(0.05, 3.0, 0.05) var shy_step_distance: float = 0.45
## 害羞时低头多少度。默认 0 = **不低头**；想让她低头就调大。
@export_range(0.0, 90.0, 1.0) var shy_head_down_degrees: float = 0.0
## 害羞时上身前倾 / 含胸多少度。默认 0 = 不带动头部前倾。
@export_range(0.0, 45.0, 1.0) var shy_hunch_degrees: float = 0.0
## 害羞时双臂向前、向中间摆多少度。和下面的 lift 一起用：
## 45° / -60° 会让双手抬到嘴巴和脸颊两侧，眼睛闭着露在上方。
@export_range(0.0, 180.0, 1.0) var shy_arm_yaw_degrees: float = 45.0
## 害羞时双臂向上抬多少度；负数 = 向上抬（默认 -60°）。
@export_range(-90.0, 90.0, 1.0) var shy_arm_lift_degrees: float = -60.0
## 害羞时小臂再向嘴中线合拢多少度（0 = 手停在脸颊两侧；
## 调大可以让双手更靠近嘴巴，但要注意别穿进脸里，需要跑起来试）。
@export_range(0.0, 90.0, 1.0) var shy_elbow_degrees: float = 0.0
## 害羞时整个人往下缩多少米。默认 0 = 不缩。
@export_range(0.0, 0.2, 0.005) var shy_crouch_height: float = 0.0
## 害羞时是否强制闭眼。
@export var shy_close_eyes: bool = true
## 是否检查视线：隔着墙 / 围栏时不看玩家、也不挥手。
@export var check_line_of_sight: bool = true
## 头部左右转动的限位（度）。
@export_range(0.0, 90.0, 1.0) var look_yaw_limit_degrees: float = 55.0
## 头部向上仰的限位（度）。玩家通常比她高，所以留得比低头多一些。
@export_range(0.0, 90.0, 1.0) var look_up_limit_degrees: float = 35.0
## 头部向下低的限位（度）。
@export_range(0.0, 90.0, 1.0) var look_down_limit_degrees: float = 25.0
## 眼珠在头转不到位时，额外跟着看多少度。
@export_range(0.0, 45.0, 1.0) var eye_look_degrees: float = 12.0

# 喝饱容量（立方米）的私有存储；对外的可调入口是下面的 drink_capacity。
# 放在属性前面，保证检查器初始化时读到的默认值已经是 0.006。
var _drink_capacity: float = 0.006

@export_group("喝水")

## 喝饱容量（立方米）。一发基础水（水枪 blob_size = 0.1）是 0.001 m³，
## 默认 0.006 ≈ 6 发基础水；水枪升级后每发更大，灌满需要的发数会变少。
## 这个值会自动同步到场景里的「饮水区」（WaterSink.capacity）。
@export_range(0.0001, 0.2, 0.0001) var drink_capacity: float:
	get:
		return _drink_capacity
	set(value):
		_drink_capacity = maxf(value, 0.0001)
		if _drink != null:
			_drink.capacity = _drink_capacity
			if _drink.amount > _drink_capacity:
				_drink.amount = _drink_capacity

## 是否把吸进「饮水区」的水喝掉（持续消耗）。关掉 = 只吸水不消耗，也不播喝水动画。
@export var drink_enabled: bool = true
## 每秒喝掉多少立方米。
## 0.00015 的意思是：一发基础水（0.001 m³）够她喝约 6.7 秒；
## 玩家按默认 1 秒一发射，大约 8 发能把 0.006 m³ 的肚子灌满、触发庆祝。
@export_range(0.00001, 0.01, 0.00001) var drink_speed: float = 0.00015
## 每收到一团水，喝水的闭眼/张嘴动画保持多久（秒）。每团水都会刷新这个计时。
## 计时结束后**立刻恢复原本的走路/发呆/坐下**，不管肚子里还剩多少水；
## 剩下的水继续在后台安静消耗（消化期间没有动画）。
@export_range(0.2, 3.0, 0.05) var feed_hold_time: float = 1.0
## 两次吞咽之间隔多久（秒）；这段时间嘴是闭着的，恢复原本的脸。
@export_range(0.2, 3.0, 0.05) var gulp_interval: float = 1.2
## 一次张嘴吞咽持续多久（秒）；其余时间嘴部 overlay 隐藏。
@export_range(0.05, 0.6, 0.01) var mouth_open_time: float = 0.2
## 吞咽时嘴最多张开到多少倍（纵向缩放）。
@export_range(0.5, 1.5, 0.01) var drink_mouth_scale: float = 1.0
## 喝水时是否闭眼享受（和眨眼相同的闭合幅度，不是眯眼缩放）。
@export var drink_close_eyes: bool = true
## 喝水时头部向后仰多少度（像在接水）。
@export_range(-30.0, 45.0, 1.0) var drink_head_up_degrees: float = 8.0
## 吞咽那一下头部轻轻点一下的角度（度）。
@export_range(0.0, 15.0, 0.5) var gulp_nod_degrees: float = 2.0
## 吞咽那一下整个人随之上浮的高度（米）。
@export_range(0.0, 0.1, 0.001) var drink_bob_height: float = 0.012
## 喝水时尾巴额外加快多少倍率。
@export_range(0.0, 3.0, 0.05) var drink_tail_boost: float = 0.5

@export_group("装满庆祝")

## 一次装满庆祝持续多久（秒）。
@export_range(0.0, 10.0, 0.05) var happy_duration: float = 1.8
## 庆祝时尾巴摆速 / 摆幅的额外倍率。
@export_range(0.0, 3.0, 0.05) var happy_wag_boost: float = 0.9
## 装满时蹦多高（米）。
@export_range(0.0, 0.5, 0.005) var happy_hop_height: float = 0.16

@export_group("坐下")

## 是否允许她在闲逛之后自己坐下。
@export var sit_enabled: bool = true
## 走完一段路后，有多大概率坐下。
@export_range(0.0, 1.0, 0.05) var sit_chance_after_walk: float = 0.25
## 一次坐下持续的最短时间（秒）。
@export_range(0.5, 60.0, 0.1) var sit_duration_min: float = 5.0
## 一次坐下持续的最长时间（秒）。
@export_range(0.5, 120.0, 0.1) var sit_duration_max: float = 10.0
## 站 ↔ 坐的过渡时间（秒）。
@export_range(0.1, 2.0, 0.01) var sit_transition_time: float = 0.5
## 坐下时整个人往下沉多少米（让屁股贴地）。
@export_range(0.0, 0.3, 0.005) var sit_drop_height: float = 0.10
## 大腿向前抬多少度（抱膝坐：约 95°）。
@export_range(0.0, 150.0, 1.0) var sit_thigh_degrees: float = 95.0
## 膝盖弯多少度（抱膝坐：约 110°）。
@export_range(0.0, 150.0, 1.0) var sit_knee_degrees: float = 110.0
## 坐下时手臂向下放多少度（85° 约等于自然垂下）。
@export_range(0.0, 100.0, 1.0) var sit_arm_down_degrees: float = 85.0
## 坐下时手臂向前倾多少度（把手搭到膝盖上）。
@export_range(0.0, 60.0, 1.0) var sit_arm_forward_degrees: float = 25.0
## 坐下时胶囊碰撞体的高度（米），站起来会自动恢复。
@export_range(0.55, 1.2, 0.01) var sit_collision_height: float = 0.85

@export_group("调试")

## 打开后会在状态变化、被水淋到等时刻打一行 print，方便排查。
@export var debug_log: bool = false

@export_group("被推动")

## 玩家能不能把她推着走。关掉 = 回到「只挡住、推不动」的表现。
@export var push_enabled: bool = true
## 玩家离她多近才算「贴着」（米）。她的胶囊半径约 0.27，加上玩家自己的半径留一点余量。
@export_range(0.3, 3.0, 0.05) var push_radius: float = 0.95
## 推动速度的倍率：1 = 大致跟着玩家的速度走，调大推得更快。
@export_range(0.2, 3.0, 0.05) var push_strength: float = 1.0


## 行为状态。SHY 会临时接管移动（捂脸后退）；SIT 是坐下休息；
## 喂水不占状态：只有收到水后的短暂窗口会停下来播动画，窗口一结束就恢复原本行为。
enum State { IDLE, WALK, SHY, SIT }

var _rng := RandomNumberGenerator.new()
var _anim_time: float = 0.0
var _state: int = State.IDLE

var _model: Node3D
var _skeleton: Skeleton3D
var _drink: WaterSink                  # 挂在「饮水区」上的通用吸水区
var _mouth_anchor: Marker3D            # 每帧跟到 head 骨骼上的挂点
var _mouth: MeshInstance3D             # 张嘴 overlay，平时隐藏
var _mouth_base_scale := Vector3.ONE
var _eye_patch_left: MeshInstance3D     # 左眼闭眼贴片（模型 +X 侧），各自可调位置
var _eye_patch_right: MeshInstance3D    # 右眼闭眼贴片（模型 -X 侧）
var _collision: CollisionShape3D
var _stand_capsule: CapsuleShape3D
var _sit_capsule: CapsuleShape3D
var _stand_collision_y: float = 0.0
var _sit_shape_applied: bool = false

var _i_hips: int = -1
var _i_spine: int = -1
var _i_chest: int = -1
var _i_neck: int = -1
var _i_head: int = -1
var _i_eye_l: int = -1
var _i_eye_r: int = -1
var _i_arm_ul: int = -1
var _i_arm_ll: int = -1
var _i_arm_ur: int = -1
var _i_arm_lr: int = -1
var _i_leg_ul: int = -1
var _i_leg_ll: int = -1
var _i_leg_ur: int = -1
var _i_leg_lr: int = -1
var _i_tail: Array[int] = []
var _i_ear_l: Array[int] = []
var _i_ear_r: Array[int] = []
var _i_hair_back: Array[int] = []
var _i_hair_l: Array[int] = []
var _i_hair_r: Array[int] = []
var _i_bangs: Array[int] = []
var _i_skirt_l: Array[int] = []
var _i_skirt_r: Array[int] = []

## 骨骼索引 → 导入时的静止姿态旋转。所有动作都是「增量 × 这个基准」，
## 不会把编辑器里可能摆过的姿态写坏。
var _base_pose: Dictionary = {}
## 骨骼索引 → 静止姿态下相对骨架根节点的基向量，用来把「向前 / 向上」这类世界轴
## 换算成骨骼自己的局部轴（做法和 scripts/人物/手臂俯仰.gd 一样）。
var _rest_global_cache: Dictionary = {}

var _model_yaw: float = 0.0
var _root_yaw: float = 0.0             # 场景根节点自己的朝向，转模型时要减掉
var _base_model_position := Vector3.ZERO
var _base_model_scale := Vector3.ONE

var _home := Vector3.ZERO             # 出生点（以脚下的地面为准），漫步范围以它为圆心
var _ground_checked: bool = false     # 第一帧物理还没准备好，延迟一点再检查脚下
var _ground_wait: float = 0.0
var _preview: bool = false            # 脚下没地面时进入原地待机预览

var _target := Vector3.ZERO
var _has_target: bool = false
var _idle_left: float = 0.0
var _stuck_time: float = 0.0
var _walk_phase: float = 0.0

var _player: Node3D
var _player_retry: float = 0.0
var _player_eye := Vector3.ZERO
## 玩家上一帧的位置：用它反推玩家速度，比直接读 velocity 可靠
## （玩家被人推、被斜坡弹开时 velocity 不一定反映真实位移）。
var _player_last_position := Vector3.ZERO
var _player_has_last := false
var _player_speed_now := Vector3.ZERO
## 当前这一帧被推的速度大小，供 _animate 判断要不要迈腿。
var _push_amount: float = 0.0
var _player_distance_now: float = INF
var _player_sensed: bool = false
var _player_was_near: bool = false
var _glance_active: bool = false      # 当前是否在「允许看她」的窗口里
var _glance_left: float = 0.0         # 当前窗口剩余时间（持有或移开）

var _look_yaw: float = 0.0            # 当前目标（限制后的）头部朝向
var _head_yaw: float = 0.0            # 平滑后的实际头部左右角
var _head_pitch: float = 0.0          # 平滑后的实际头部上下角
var _has_look_target: bool = false

var _wave_time: float = 0.0
var _wave_cd: float = 0.0
var _shy_time: float = 0.0
var _shy_cd: float = 0.0
var _shy_dir := Vector3.ZERO
var _happy_time: float = 0.0
var _water_focus_position := Vector3.ZERO
var _water_focus_left: float = 0.0   # 水花位置保留多久，用来让头转过去看
var _feed_time: float = 0.0          # > 0 = 正在「喂水」的动画窗口

# 吞咽节奏：每隔 gulp_interval 秒张嘴 mouth_open_time 秒，其余时间闭嘴。
var _gulp_left: float = 0.0
var _gulp_progress: float = -1.0     # < 0 = 闭嘴
var _gulp_open: float = 0.0          # 0~1，吞咽时嘴张开的包络

var _sit_target: int = 0              # 1 = 想坐着，0 = 想站着
var _sit_left: float = 0.0
var _sit_blend: float = 0.0

# 几个「渐变权重」：挥手 / 害羞 / 开心 / 喝水 / 坐下；动作不会啪地一下弹回去。
# 计时器只决定「想不想做」，真正摆多少看这些 0~1 的权重。
var _wave_blend: float = 0.0
var _shy_blend: float = 0.0
var _happy_blend: float = 0.0
var _feed_blend: float = 0.0

var _blink_wait: float = 0.0
var _blink_progress: float = -1.0
var _blink_double: bool = false
var _double_wait: float = 0.0
var _ear_wait: float = 0.0
var _ear_progress: float = -1.0
var _ear_side: int = 1
var _hop_progress: float = -1.0
var _hop_height_now: float = 0.0
var _hop_queue: Array[float] = []
var _idle_hop_wait: float = 0.0

var _probe_shape := CapsuleShape3D.new()
var _probe_query := PhysicsShapeQueryParameters3D.new()


## 开机只做几件事：找骨架、缓存骨骼索引、把 T-pose 的手臂放下来、
## 接上「饮水区」的信号、把站/坐两套碰撞胶囊准备好。
## 注意这个脚本不创建任何节点 —— 骨架、饮水区、嘴部挂点全都在 scenes/蓝色小肥鱼.tscn 里摆好。
func _ready() -> void:
	_rng.randomize()
	_model = $模型
	_base_model_position = _model.position
	_base_model_scale = _model.scale
	_model_yaw = _model.rotation.y
	_root_yaw = global_rotation.y
	_home = global_position

	# 让角色贴着地面走；离地超过这个距离就自然下落。
	floor_snap_length = 0.2

	_probe_shape.radius = 0.22
	_probe_shape.height = 0.85
	_probe_query.shape = _probe_shape

	# 饮水区：吸收水团、记水量、满了发 filled。喝水/消耗由本脚本驱动。
	_drink = $饮水区 as WaterSink
	if _drink != null:
		# 容量以根节点上的 drink_capacity 为准（场景里的「饮水区」不再单独填容量）。
		_drink.capacity = drink_capacity
		_drink.water_received.connect(_on_water_received)
		_drink.filled.connect(_on_drink_filled)
		# 水团被吸收时记下它的位置，庆祝时头可以朝那个方向看。
		_drink.area_entered.connect(_on_drink_area_entered)
	else:
		push_error("小肥鱼：场景里没有挂吸水区脚本的「饮水区」，喝水和装满互动不会工作")

	# 嘴部 + 闭眼睫毛 overlay：挂点每帧跟到 head 骨骼，平时藏起来，喝水/闭眼时才显示。
	_mouth_anchor = $嘴巴挂点
	_mouth = $嘴巴挂点/嘴巴
	if _mouth != null:
		_mouth_base_scale = _mouth.scale
		_mouth.visible = false
	_eye_patch_left = $嘴巴挂点/眼睫_左
	_eye_patch_right = $嘴巴挂点/眼睫_右
	if _eye_patch_left != null:
		_eye_patch_left.visible = false
	if _eye_patch_right != null:
		_eye_patch_right.visible = false

	# 站姿胶囊复制一份，坐下时换成一个更矮的胶囊，避免玩家撞到看不见的站立身体。
	_collision = $CollisionShape3D
	_stand_collision_y = _collision.position.y
	_stand_capsule = _collision.shape.duplicate() as CapsuleShape3D
	_sit_capsule = _stand_capsule.duplicate() as CapsuleShape3D
	_sit_capsule.height = sit_collision_height

	_skeleton = _find_skeleton()
	if _skeleton == null:
		push_error("小肥鱼：模型里没找到 Skeleton3D，所有骨骼动画都不会工作")
	else:
		_build_bone_cache()
		# 先把基准姿态摆好，避免第一帧闪一下 T-pose
		_apply_base_pose()

	_blink_wait = _rand_range(blink_interval_min, blink_interval_max)
	_ear_wait = _rand_range(ear_twitch_interval_min, ear_twitch_interval_max)
	_idle_hop_wait = _rand_range(idle_hop_interval_min, idle_hop_interval_max)
	_idle_left = _rand_range(idle_duration_min, idle_duration_max)


## 物理帧负责「走不走、往哪走、什么时候害羞后退」。
## 骨骼动画放在 _process 里，跟渲染帧走，看起来更顺。
func _physics_process(delta: float) -> void:
	_tick_interaction(delta)
	_update_player_reference(delta)
	_update_glance(delta)

	if not _ground_checked:
		_check_ground(delta)
		if not _ground_checked:
			return
	if _preview:
		return

	_update_drink(delta)
	_update_state(delta)
	_update_sit(delta)
	_move(delta)


## 渲染帧负责所有骨骼动作与模型本身的上下浮动。
func _process(delta: float) -> void:
	_anim_time += delta
	_update_facing(delta)
	if _skeleton == null:
		return
	_tick_blink(delta)
	_tick_ear_twitch(delta)
	_tick_hop(delta)
	_tick_idle_hop(delta)
	_animate(delta)
	_update_mouth()


# ---------------------------------------------------------------------------
# 骨骼缓存与姿态工具
# ---------------------------------------------------------------------------

## 在模型实例内部找第一个 Skeleton3D。owned 传 false 才能找到 GLB 实例内部的节点。
func _find_skeleton() -> Skeleton3D:
	var found: Array[Node] = find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


func _build_bone_cache() -> void:
	_i_hips = _register(&"hips")
	_i_spine = _register(&"spine")
	_i_chest = _register(&"chest")
	_i_neck = _register(&"neck")
	_i_head = _register(&"head")
	_i_eye_l = _register(&"eye.L")
	_i_eye_r = _register(&"eye.R")
	_i_arm_ul = _register(&"upper_arm.L")
	_i_arm_ll = _register(&"lower_arm.L")
	_i_arm_ur = _register(&"upper_arm.R")
	_i_arm_lr = _register(&"lower_arm.R")
	_i_leg_ul = _register(&"upper_leg.L")
	_i_leg_ll = _register(&"lower_leg.L")
	_i_leg_ur = _register(&"upper_leg.R")
	_i_leg_lr = _register(&"lower_leg.R")

	_i_tail = _register_chain(TAIL_BONES)
	_i_ear_l = _register_chain(EAR_L_BONES)
	_i_ear_r = _register_chain(EAR_R_BONES)
	_i_hair_back = _register_chain(HAIR_BACK_BONES)
	_i_hair_l = _register_chain(HAIR_L_BONES)
	_i_hair_r = _register_chain(HAIR_R_BONES)
	_i_bangs = _register_chain(BANGS_BONES)
	_i_skirt_l = _register_chain(SKIRT_L_BONES)
	_i_skirt_r = _register_chain(SKIRT_R_BONES)


func _register(bone_name: StringName) -> int:
	var idx: int = _skeleton.find_bone(String(bone_name))
	if idx < 0:
		push_warning("小肥鱼：骨架里没有骨骼「%s」，相关动作会被跳过" % bone_name)
		return -1
	if not _base_pose.has(idx):
		_base_pose[idx] = _skeleton.get_bone_pose_rotation(idx)
	return idx


func _register_chain(names: Array[StringName]) -> Array[int]:
	var out: Array[int] = []
	for bone_name in names:
		var idx: int = _register(bone_name)
		if idx >= 0:
			out.append(idx)
	return out


## 把「骨架空间里的轴」换算成这根骨骼 pose 局部空间里的轴。
## 关键是绕开缩放：导入的骨架可能带着非 1 的缩放，必须先 orthonormalized()，
## 否则 Quaternion(axis, angle) 会因为轴长度不是 1 而报错。
func _q(idx: int, axis: Vector3, degrees: float) -> Quaternion:
	if idx < 0 or absf(degrees) < 0.0001:
		return Quaternion.IDENTITY
	var neutral: Basis = _rest_global_basis(idx).orthonormalized()
	var local_axis: Vector3 = (neutral.inverse() * axis).normalized()
	return Quaternion(local_axis, deg_to_rad(degrees))


## 骨骼静止时相对骨架根节点的基向量（只算朝向，不管位移）。
func _rest_global_basis(idx: int) -> Basis:
	if _rest_global_cache.has(idx):
		var cached: Basis = _rest_global_cache[idx]
		return cached
	var basis: Basis = _skeleton.get_bone_rest(idx).basis
	var parent: int = _skeleton.get_bone_parent(idx)
	if parent >= 0:
		basis = _rest_global_basis(parent) * basis
	_rest_global_cache[idx] = basis
	return basis


## 所有动作最终都走这里：增量 × 基准姿态。写绝对值会把导入姿态 / 编辑器姿态覆盖掉。
func _set_rot(idx: int, q: Quaternion) -> void:
	if idx < 0:
		return
	var base: Quaternion = _base_pose.get(idx, Quaternion.IDENTITY)
	_skeleton.set_bone_pose_rotation(idx, q * base)


## 眼睛骨骼只负责左右看（眼珠跟随玩家）。
## 「闭眼」不再压扁眼球，而是由场景里的「眼睫」肤色贴片盖住整只眼睛；
## 所以这里每帧把缩放重置回 1，保证眼珠保持原本形状。
func _set_eye(idx: int, yaw_degrees: float) -> void:
	if idx < 0:
		return
	_set_rot(idx, _q(idx, AXIS_UP, yaw_degrees))
	_skeleton.set_bone_pose_scale(idx, Vector3.ONE)


## 把手臂从 T-pose 放下来。只在 _ready 里调一次，之后每帧的动画都会重新叠加到基准上。
func _apply_base_pose() -> void:
	_set_rot(_i_arm_ul, _q(_i_arm_ul, AXIS_FORWARD, -arm_down_degrees))
	_set_rot(_i_arm_ur, _q(_i_arm_ur, AXIS_FORWARD, arm_down_degrees))


# ---------------------------------------------------------------------------
# 物理：地面、玩家感知、漫步
# ---------------------------------------------------------------------------

## 延迟一小会儿再检查脚下：场景刚加载时物理服务器可能还没把地面准备好。
func _check_ground(delta: float) -> void:
	_ground_wait += delta
	if _ground_wait < 0.25:
		return
	_ground_checked = true
	var hit := _ray_down(global_position + Vector3.UP * 0.4, 4.0)
	if hit.is_empty():
		if preview_when_no_ground:
			_preview = true
			print("小肥鱼：出生点下方没有地面，进入原地待机预览（放进有地面的场景后会自动散步）")
		return
	var ground: Vector3 = hit[&"position"]
	_home = Vector3(global_position.x, ground.y, global_position.z)


func _ray_down(from: Vector3, length: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * length, collision_mask, [get_rid()])
	return space.intersect_ray(query)


## 缓存玩家位置 / 距离 / 视线。物理帧只查一次，渲染帧直接读结果。
func _update_player_reference(delta: float) -> void:
	if not is_instance_valid(_player):
		_player_retry -= delta
		if _player_retry <= 0.0:
			_player_retry = 0.5
			_player = get_tree().get_first_node_in_group(GROUP_PLAYER) as Node3D
	if not is_instance_valid(_player):
		_player_sensed = false
		_player_distance_now = INF
		return

	# 用位置差反推玩家速度：不依赖玩家脚本怎么写，被推 / 被传送都能量到。
	var player_position: Vector3 = (_player as Node3D).global_position
	if _player_has_last:
		_player_speed_now = (player_position - _player_last_position) / maxf(delta, 0.0001)
		_player_speed_now.y = 0.0
		if _player_speed_now.length() > 20.0:
			_player_speed_now = _player_speed_now.normalized() * 20.0
	else:
		_player_speed_now = Vector3.ZERO
		_player_has_last = true
	_player_last_position = player_position

	_player_eye = _player_eye_position()
	_player_distance_now = global_position.distance_to(_player_eye)
	_player_sensed = _player_distance_now <= notice_radius
	if _player_sensed and check_line_of_sight:
		_player_sensed = _can_see(_player_eye)


## 玩家眼睛大概在哪：优先用当前摄像机的世界位置（第一人称），
## 找不到摄像机就按玩家身高估一个。她只有 1 米高，这个高度差就是「仰头看你」的来源。
func _player_eye_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	return _player.global_position + Vector3.UP * 1.5


## 从她胸口到玩家眼睛打一条射线。打到玩家自己算「看得见」，先打到墙/围栏就不算。
func _can_see(target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.6,
		target,
		collision_mask,
		[get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get(&"collider") == _player


## 「看一眼 → 移开 → 过几秒再看一眼」的节奏。
## 只有 _glance_active 为 true 时，头和身体才会转向玩家；其余时间她只是站在那儿。
func _update_glance(delta: float) -> void:
	if not look_at_player or not _player_sensed:
		_glance_active = false
		_glance_left = 0.0
		return
	if _glance_active:
		_glance_left -= delta
		if _glance_left <= 0.0:
			_glance_active = false
			_glance_left = _rand_range(glance_away_min, glance_away_max)
	else:
		_glance_left -= delta
		if _glance_left <= 0.0:
			if _rng.randf() < glance_repeat_chance:
				_glance_active = true
				_glance_left = _rand_range(glance_hold_min, glance_hold_max)
			else:
				_glance_left = _rand_range(glance_away_min, glance_away_max)


func _update_state(delta: float) -> void:
	# 玩家靠近时，如果她正坐着，先站起来（坐下选项里说好的）。
	if _state == State.SIT and _player_sensed:
		_end_sit()

	# 害羞期间不接受新决定，等计时结束自己回到 IDLE
	if _shy_time > 0.0:
		_state = State.SHY
		return

	var near := _player_sensed
	if near != _player_was_near:
		if near:
			_on_player_approached()
		else:
			_glance_active = false
		_player_was_near = near

	# 靠得太近：害羞捂脸 + 后退（比挥手优先，免得一边退一边挥手）
	if shy_enabled and near and _player_distance_now < shy_radius and _shy_cd <= 0.0:
		_start_shy()
		return

	# 装满庆祝期间：停下来把这两下跳完，不接新的走 / 坐决定。
	if _happy_time > 0.0:
		if _state == State.WALK:
			_enter_idle()
		_has_target = false
		return

	# 饮水区里还有水：停下来喝。坐着就坐着喝，站着就站着喝。
	if _is_feeding():
		if _state == State.WALK:
			_enter_idle()
		_has_target = false
		return

	# 挥手期间原地不动，等她把这一支曲子跳完
	if _wave_time > 0.0:
		_state = State.IDLE
		_has_target = false
		return

	if near:
		if _state != State.IDLE:
			_enter_idle()
		# 玩家还在旁边时别急着重启漫步；至少再看 0.4 秒
		_idle_left = maxf(_idle_left, 0.4)
		return

	match _state:
		State.WALK:
			if not _has_target:
				_enter_idle()
		State.IDLE:
			_idle_left -= delta
			if _idle_left <= 0.0:
				_begin_walk()
		State.SIT:
			_sit_left -= delta
			if _sit_left <= 0.0:
				_end_sit()
		_:
			pass


func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _happy_time > 0.0 or _is_feeding() or _state == State.SIT:
		# 庆祝 / 喂水窗口 / 坐着：原地不动，交给动画层。
		desired = Vector3.ZERO
	elif _state == State.WALK and _has_target:
		var offset := _target - global_position
		offset.y = 0.0
		if offset.length() <= 0.12:
			_enter_idle(true)
		else:
			desired = offset.normalized() * walk_speed
	elif _state == State.SHY and _shy_time > 0.0:
		# 边捂脸边小步后退；速度按「距离 / 时长」反推，保证正好退完 shy_step_distance
		desired = _shy_dir * (shy_step_distance / maxf(shy_duration, 0.01))

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	# 玩家贴着并朝她走来时，把玩家方向上的推力叠到目标速度上。
	# 只影响速度，不改 _state、不改漫步逻辑；玩家一松手推力就归零。
	desired += _player_push()

	var smoothing: float = 1.0 - exp(-10.0 * delta)
	velocity.x = lerpf(velocity.x, desired.x, smoothing)
	velocity.z = lerpf(velocity.z, desired.z, smoothing)

	var before := global_position
	move_and_slide()

	# 一直走不动 = 撞墙 / 被玩家堵住，放弃这个目标重新选。
	if _state == State.WALK and _has_target:
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		if moved < 0.002:
			_stuck_time += delta
			if _stuck_time >= stuck_timeout:
				_enter_idle()
		else:
			_stuck_time = 0.0


## 玩家推她：玩家贴得够近、并且正在朝她这边移动时，返回一个「离开玩家」的速度。
## 走路 / 害羞 / 坐下的原有逻辑一律不动 —— 这里只多给一个速度分量，
## 由 _move 叠到 desired 上，再由原来的平滑和 move_and_slide 统一处理。
## 玩家停下或走开，返回值立刻变回零，她自然减速停在原地。
func _player_push() -> Vector3:
	_push_amount = 0.0
	if not push_enabled or not is_instance_valid(_player):
		return Vector3.ZERO
	var speed: float = _player_speed_now.length()
	if speed < 0.05:
		return Vector3.ZERO
	var offset: Vector3 = global_position - (_player as Node3D).global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance < 0.0001 or distance > push_radius:
		return Vector3.ZERO
	var away: Vector3 = offset / distance                 # 玩家 → 她，就是推动方向
	if _player_speed_now.normalized().dot(away) < 0.2:    # 玩家得是「朝她走来」才算推
		return Vector3.ZERO
	# 越贴近推得越明显，边缘处平滑归零，不会过了阈值突然弹一下
	var closeness: float = 1.0 - distance / push_radius
	_push_amount = clampf(speed * closeness * push_strength, 0.0, 4.0)
	return away * _push_amount


## after_walk = true 表示「刚走到一个路点」，这时才有几率触发坐下休息。
func _enter_idle(after_walk: bool = false) -> void:
	_state = State.IDLE
	_has_target = false
	_idle_left = _rand_range(idle_duration_min, idle_duration_max)
	velocity.x = 0.0
	velocity.z = 0.0
	# 闲逛后随机坐：不在喂水窗口、玩家不在旁边才有资格。
	if (after_walk and sit_enabled and not _preview and not _player_sensed
			and not _is_feeding() and _happy_time <= 0.0
			and _rng.randf() < sit_chance_after_walk):
		_begin_sit()


func _begin_sit() -> void:
	if not sit_enabled or _preview or _player_sensed or _is_feeding() or _happy_time > 0.0:
		return
	_state = State.SIT
	_sit_target = 1
	_sit_left = _rand_range(sit_duration_min, sit_duration_max)
	_has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	if debug_log:
		print("小肥鱼：坐下休息 %.1f 秒" % _sit_left)


func _end_sit() -> void:
	var was_sitting: bool = _state == State.SIT
	if was_sitting:
		_state = State.IDLE
		_idle_left = _rand_range(idle_duration_min, idle_duration_max)
	_sit_target = 0
	if was_sitting and debug_log:
		print("小肥鱼：站起来")


## 站/坐过渡与碰撞胶囊切换。姿势本身在 _animate 里按 _sit_blend 混合。
func _update_sit(delta: float) -> void:
	_sit_blend = move_toward(_sit_blend, float(_sit_target), delta / maxf(sit_transition_time, 0.01))
	var sitting: bool = _sit_blend > 0.5
	if sitting != _sit_shape_applied:
		_apply_sit_shape(sitting)


## 坐下时换一颗更矮的胶囊，免得玩家撞到「站着时那团看不见的空气」。
func _apply_sit_shape(sitting: bool) -> void:
	if _collision == null:
		return
	_sit_shape_applied = sitting
	if sitting:
		_sit_capsule.height = sit_collision_height
		_collision.shape = _sit_capsule
		_collision.position = Vector3(_collision.position.x, _sit_capsule.height * 0.5, _collision.position.z)
	else:
		_collision.shape = _stand_capsule
		_collision.position = Vector3(_collision.position.x, _stand_collision_y, _collision.position.z)


func _begin_walk() -> void:
	if not auto_wander or _preview or roam_radius <= 0.01:
		_enter_idle()
		return
	var target := _choose_wander_target()
	if not target.is_finite():
		_enter_idle()
		return
	_target = target
	_has_target = true
	_state = State.WALK
	_stuck_time = 0.0
	if debug_log:
		print("小肥鱼：去 %s 走走" % target)


## 在出生点周围随机挑一个能站住的地面点。
## 只检查地面高度和落点净空；中途撞到东西交给 _move 的卡住检测。
func _choose_wander_target() -> Vector3:
	var space := get_world_3d().direct_space_state
	# 最短距离不能超过漫游半径，否则会一步跨出自己画的那个圈
	var near_distance: float = minf(min_step_distance, roam_radius)
	for _attempt in 20:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(near_distance, roam_radius)
		var candidate := Vector3(
			_home.x + cos(angle) * distance,
			_home.y,
			_home.z + sin(angle) * distance
		)
		var hit := _ray_down(candidate + Vector3.UP * 2.0, 4.0)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit[&"position"]
		var normal: Vector3 = hit[&"normal"]
		if normal.y < 0.85:
			continue
		if absf(ground.y - _home.y) > 0.5:
			continue

		# 落点上方要留出身体空间，别选到墙角 / 家具里面
		_probe_query.shape = _probe_shape
		_probe_query.transform = Transform3D(
			Basis.IDENTITY,
			ground + Vector3.UP * (_probe_shape.height * 0.5 + 0.02)
		)
		_probe_query.collision_mask = collision_mask
		_probe_query.exclude = [get_rid()]
		if not space.intersect_shape(_probe_query, 1).is_empty():
			continue

		return ground + Vector3.UP * 0.01

	return Vector3(INF, INF, INF)


func _on_player_approached() -> void:
	# 先进入「看一眼」的窗口；之后她自己会移开视线，不是一直盯着。
	if look_at_player:
		_glance_active = true
		_glance_left = _rand_range(glance_hold_min, glance_hold_max)
	# 正在喂水 / 庆祝时不挥手，免得两套动作打架。
	if _is_feeding() or _happy_time > 0.0:
		return
	if not wave_enabled or _wave_cd > 0.0 or _shy_time > 0.0:
		return
	_wave_time = wave_duration
	_wave_cd = wave_cooldown
	_state = State.IDLE
	_has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	if debug_log:
		print("小肥鱼：看见玩家，挥手")


func _start_shy() -> void:
	_shy_time = shy_duration
	_shy_cd = shy_cooldown
	_wave_time = 0.0
	_state = State.SHY
	_has_target = false
	_shy_dir = global_position - _player.global_position
	_shy_dir.y = 0.0
	_shy_dir = _shy_dir.normalized() if _shy_dir.length() > 0.01 else -AXIS_FORWARD
	velocity.x = 0.0
	velocity.z = 0.0
	if debug_log:
		print("小肥鱼：靠太近了，害羞")


func _tick_interaction(delta: float) -> void:
	_wave_cd = maxf(0.0, _wave_cd - delta)
	_shy_cd = maxf(0.0, _shy_cd - delta)
	_wave_time = maxf(0.0, _wave_time - delta)
	_happy_time = maxf(0.0, _happy_time - delta)
	_feed_time = maxf(0.0, _feed_time - delta)
	if _shy_time > 0.0:
		_shy_time = maxf(0.0, _shy_time - delta)
		if _shy_time <= 0.0:
			_enter_idle()


## 「正在喂水」= 刚有水流进来、动画窗口还没结束，且不在害羞 / 装满庆祝。
## 注意：和饮水区里还剩多少水无关。窗口结束后就会恢复正常，剩下的水在后台消耗。
func _is_feeding() -> bool:
	return (drink_enabled and _feed_time > 0.0
			and _shy_time <= 0.0 and _happy_time <= 0.0)


## 每帧把饮水区里的水喝掉一点（这是背后的「消化」，没有动画）。
## 庆祝和害羞时暂停，让「装满」那一刻多停一会儿。
func _update_drink(delta: float) -> void:
	_water_focus_left = maxf(0.0, _water_focus_left - delta)
	if not drink_enabled or _drink == null:
		return
	if _happy_time > 0.0 or _shy_time > 0.0:
		return
	if _drink.amount > 0.0:
		_drink.remove_water(drink_speed * delta)


## 每收到一团水：刷新「喂水」动画窗口，并立刻触发一次吞咽。
## 剩下的水之后会安静消耗，不再影响动画。
func _on_water_received(volume: float) -> void:
	# 喂水优先于挥手：水都到嘴边了就别甩胳膊了。
	_wave_time = 0.0
	_feed_time = feed_hold_time
	_gulp_progress = 0.0
	_gulp_left = gulp_interval
	if debug_log:
		print("小肥鱼：喝到 %.5f m³" % volume)


## 水团被饮水区吸收时记下它的位置；喂水和装满庆祝时头可以朝那个方向看。
func _on_drink_area_entered(area: Area3D) -> void:
	if not area.is_in_group(GROUP_WATER):
		return
	var node := area as Node3D
	if node != null:
		_water_focus_position = node.global_position
		_water_focus_left = feed_hold_time


## 饮水区第一次/再次装满：这里才播「当前与水的跳跃互动」。
func _on_drink_filled() -> void:
	_happy_time = happy_duration
	_queue_hop(happy_hop_height)
	_queue_hop(happy_hop_height * 0.75)
	if _state == State.WALK:
		_enter_idle()
	_has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	if debug_log:
		print("小肥鱼：喝饱了，开心地跳两下")


# ---------------------------------------------------------------------------
# 渲染：朝向、头部跟随与整套骨骼动作
# ---------------------------------------------------------------------------

## 身体朝向：喂水时朝水花；走路时朝行进方向；害羞时面向玩家（让她看到我捂脸）；
## 玩家靠近时也只在「看一眼」的窗口里转身，不会一直盯着。
## 只旋转「模型」子节点，胶囊碰撞体始终竖直，不跟着转。
func _update_facing(delta: float) -> void:
	if _model == null:
		return
	var target_yaw: float = _model_yaw
	var has_target: bool = false

	if _shy_time > 0.0:
		target_yaw = atan2(_player_eye.x - global_position.x, _player_eye.z - global_position.z)
		has_target = true
	elif _water_focus_left > 0.0:
		target_yaw = atan2(_water_focus_position.x - global_position.x, _water_focus_position.z - global_position.z)
		has_target = true
	elif _state == State.WALK and Vector2(velocity.x, velocity.z).length() > 0.08:
		target_yaw = atan2(velocity.x, velocity.z)
		has_target = true
	elif _glance_active and look_at_player and not _is_feeding():
		target_yaw = atan2(_player_eye.x - global_position.x, _player_eye.z - global_position.z)
		has_target = true

	# atan2 算出来的是「世界朝向」；模型子节点要的是相对根的局部朝向，减掉根的 yaw。
	if has_target:
		_model_yaw = lerp_angle(_model_yaw, target_yaw - _root_yaw, 1.0 - exp(-turn_speed * delta))
	_model.rotation.y = _model_yaw


## 头 / 眼珠看向目标：先算「玩家眼睛或水花」在她的骨架空间里的方向，
## 再限位、平滑。头转不到的剩余角度交给眼珠补一点。
## 玩家只在 glance 窗口里被看；喂水时优先看水花；害羞时头保持不动，靠双手挡在脸前。
func _update_head_look(delta: float) -> void:
	var target := Vector3.ZERO
	var has_target: bool = false

	if _shy_time > 0.0:
		has_target = false
	elif _water_focus_left > 0.0:
		target = _water_focus_position
		has_target = true
	elif _glance_active and look_at_player and not _is_feeding():
		target = _player_eye
		has_target = true

	var desired_yaw: float = 0.0
	var desired_pitch: float = 0.0
	if has_target and _i_head >= 0:
		var head_pos: Vector3 = _skeleton.get_bone_global_pose(_i_head).origin
		var target_skel: Vector3 = _skeleton.global_transform.affine_inverse() * target
		var dir: Vector3 = target_skel - head_pos
		var flat := Vector2(dir.x, dir.z)
		if flat.length() > 0.001:
			desired_yaw = clampf(rad_to_deg(atan2(dir.x, dir.z)), -look_yaw_limit_degrees, look_yaw_limit_degrees)
			desired_pitch = clampf(rad_to_deg(atan2(dir.y, flat.length())), -look_down_limit_degrees, look_up_limit_degrees)

	_has_look_target = has_target
	_look_yaw = desired_yaw
	var weight: float = 1.0 - exp(-8.0 * delta)
	_head_yaw = lerpf(_head_yaw, desired_yaw if has_target else 0.0, weight)
	_head_pitch = lerpf(_head_pitch, desired_pitch if has_target else 0.0, weight)


func _animate(delta: float) -> void:
	var t := _anim_time
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clampf(horizontal_speed / maxf(walk_speed, 0.001), 0.0, 1.0)
	var walking: bool = _state == State.WALK and horizontal_speed > 0.05
	# 害羞后退时也要迈腿，否则看起来像在冰面上滑行。
	# 被玩家推着走时也迈腿，否则会像在冰面上滑行
	var stepping: bool = horizontal_speed > 0.05 and (_state == State.WALK or _state == State.SHY or _push_amount > 0.05)
	var feeding: bool = _is_feeding()
	# 几个动作权重都做指数平滑：开始时一两帧内抬起来，结束时也不会突然弹回。
	var blend_weight: float = 1.0 - exp(-10.0 * delta)
	_wave_blend = lerpf(_wave_blend, 1.0 if _wave_time > 0.0 else 0.0, blend_weight)
	_shy_blend = lerpf(_shy_blend, 1.0 if _shy_time > 0.0 else 0.0, blend_weight)
	_happy_blend = lerpf(_happy_blend, 1.0 if _happy_time > 0.0 else 0.0, blend_weight)
	_feed_blend = lerpf(_feed_blend, 1.0 if feeding else 0.0, blend_weight)
	var wave_amount: float = _wave_blend
	var feed_amount: float = _feed_blend
	var sit_amount: float = _sit_blend

	# 吞咽节奏：喂水窗口内大部分时间嘴是闭着的，每隔 gulp_interval 秒张嘴一小会儿。
	if feeding:
		if _gulp_progress >= 0.0:
			_gulp_progress += delta
			if _gulp_progress >= mouth_open_time:
				_gulp_progress = -1.0
				_gulp_left = gulp_interval
		else:
			_gulp_left -= delta
			if _gulp_left <= 0.0:
				_gulp_progress = 0.0
	else:
		_gulp_progress = -1.0
		_gulp_left = 0.0
	_gulp_open = 0.0
	if _gulp_progress >= 0.0:
		_gulp_open = sin(clampf(_gulp_progress / maxf(mouth_open_time, 0.01), 0.0, 1.0) * PI)
	var gulp: float = _gulp_open

	# 走路相位只在真的移动时推进；速度越低步频越慢，脚不容易打滑。
	if stepping:
		_walk_phase = fmod(_walk_phase + delta * walk_cycle_speed * speed_ratio, TAU)
	var walk_wave: float = sin(_walk_phase)

	# --- 呼吸与重心 ---
	var breathe: float = sin(t * TAU / maxf(breathe_period, 0.1)) * breathe_degrees
	var sway: float = sin(t * sway_speed) * sway_degrees
	var lean: float = walk_lean_degrees * speed_ratio
	# 害羞默认不低头、不含胸；想加一点前倾再调 shy_hunch_degrees。
	lean += shy_hunch_degrees * _shy_blend
	_set_rot(_i_hips, _q(_i_hips, AXIS_FORWARD, sway + walk_wave * 1.2 * speed_ratio))
	_set_rot(_i_spine, _q(_i_spine, AXIS_FORWARD, -sway * 0.6) * _q(_i_spine, AXIS_RIGHT, breathe * 0.5 + lean))
	_set_rot(_i_chest, _q(_i_chest, AXIS_RIGHT, breathe))
	_set_rot(_i_neck, _q(_i_neck, AXIS_RIGHT, -breathe * 0.3))

	# --- 头：看向目标 + 待机小动作 ---
	_update_head_look(delta)
	var idle_yaw := sin(t * 0.7 + 1.3) * 1.2
	var idle_pitch := sin(t * 0.9) * 0.8
	var idle_tilt := sin(t * 0.55 + 0.4) * 1.0
	var head_q := Quaternion.IDENTITY
	if _has_look_target:
		head_q = _q(_i_head, AXIS_UP, _head_yaw) * _q(_i_head, AXIS_RIGHT, -_head_pitch)
	head_q = head_q * _q(_i_head, AXIS_UP, idle_yaw)
	head_q = head_q * _q(_i_head, AXIS_RIGHT,
			idle_pitch + shy_head_down_degrees * _shy_blend
			- drink_head_up_degrees * feed_amount
			+ gulp * gulp_nod_degrees * feed_amount)
	head_q = head_q * _q(_i_head, AXIS_FORWARD, idle_tilt)
	_set_rot(_i_head, head_q)

	# --- 眼睛：眼珠只负责左右看；闭眼由肤色贴片盖住整只眼睛 ---
	var blink_amount: float = _blink_amount()
	var eye_yaw: float = 0.0
	if _has_look_target:
		eye_yaw = clampf(_look_yaw - _head_yaw, -eye_look_degrees, eye_look_degrees)
	_set_eye(_i_eye_l, eye_yaw)
	_set_eye(_i_eye_r, eye_yaw)
	# 普通眨眼、喂水、害羞共用同一张贴片。眼球不缩放，所以不会「眼睛没了」。
	var eyes_closed: bool = blink_amount > 0.5
	if drink_close_eyes and feed_amount > 0.5:
		eyes_closed = true
	if shy_close_eyes and _shy_blend > 0.5:
		eyes_closed = true
	if _eye_patch_left != null:
		_eye_patch_left.visible = eyes_closed
	if _eye_patch_right != null:
		_eye_patch_right.visible = eyes_closed

	# --- 手臂：平时垂下 + 走路摆动；挥手抬左臂；坐下搭膝盖；害羞双手挡脸 ---
	var arm_swing_l: float = walk_wave * arm_swing_degrees * speed_ratio
	var arm_swing_r: float = -walk_wave * arm_swing_degrees * speed_ratio
	var arm_down_l: float = -arm_down_degrees
	var arm_down_r: float = arm_down_degrees
	if wave_amount > 0.001:
		# 按权重把左臂从「自然下垂」过渡到「举起来」，再整条手臂上下摆。
		# 用伸直的手臂挥，而不是弯肘，免得手戳进她的大脑袋。
		var wave_rock: float = sin(t * wave_speed) * wave_swing_degrees * wave_amount
		arm_down_l = -(arm_down_degrees - wave_arm_raise_degrees * wave_amount) + wave_rock
		arm_swing_l *= 1.0 - wave_amount
	var idle_arm := sin(t * 1.3) * 1.2
	var arm_q_l := _q(_i_arm_ul, AXIS_RIGHT, arm_swing_l + idle_arm) * _q(_i_arm_ul, AXIS_FORWARD, arm_down_l)
	var arm_q_r := _q(_i_arm_ur, AXIS_RIGHT, arm_swing_r - idle_arm) * _q(_i_arm_ur, AXIS_FORWARD, arm_down_r)

	# 坐下：手臂从自然下垂过渡到「向前伸、手搭膝盖」。
	if sit_amount > 0.001:
		var sit_q_l := _q(_i_arm_ul, AXIS_RIGHT, -sit_arm_forward_degrees) * _q(_i_arm_ul, AXIS_FORWARD, -sit_arm_down_degrees)
		var sit_q_r := _q(_i_arm_ur, AXIS_RIGHT, -sit_arm_forward_degrees) * _q(_i_arm_ur, AXIS_FORWARD, sit_arm_down_degrees)
		arm_q_l = arm_q_l.slerp(sit_q_l, sit_amount)
		arm_q_r = arm_q_r.slerp(sit_q_r, sit_amount)

	# 害羞：双臂抬到嘴和脸颊两侧；默认不低头，眼睛闭着露在手上方。
	if _shy_blend > 0.001:
		var cover_l := _q(_i_arm_ul, AXIS_FORWARD, -shy_arm_lift_degrees) * _q(_i_arm_ul, AXIS_UP, -shy_arm_yaw_degrees)
		var cover_r := _q(_i_arm_ur, AXIS_FORWARD, shy_arm_lift_degrees) * _q(_i_arm_ur, AXIS_UP, shy_arm_yaw_degrees)
		arm_q_l = arm_q_l.slerp(cover_l, _shy_blend)
		arm_q_r = arm_q_r.slerp(cover_r, _shy_blend)
	_set_rot(_i_arm_ul, arm_q_l)
	_set_rot(_i_arm_ur, arm_q_r)

	# 小臂：挥手时抬左前臂；害羞时（默认 0）绕竖直轴把双手再往嘴中线收。
	# 绕 UP 而不是绕 FORWARD：手是「向脸中间合拢」，不是上下摆。
	var wave_forearm_l: float = wave_amount * wave_forearm_degrees
	var shy_elbow: float = shy_elbow_degrees * _shy_blend
	_set_rot(_i_arm_ll, _q(_i_arm_ll, AXIS_FORWARD, wave_forearm_l) * _q(_i_arm_ll, AXIS_UP, -shy_elbow))
	_set_rot(_i_arm_lr, _q(_i_arm_lr, AXIS_UP, shy_elbow))

	# --- 腿：小碎步；坐下时过渡到抱膝坐 ---
	var leg_l: float = -walk_wave * leg_swing_degrees * speed_ratio
	var leg_r: float = walk_wave * leg_swing_degrees * speed_ratio
	var knee_l: float = maxf(0.0, -walk_wave) * knee_bend_degrees * speed_ratio
	var knee_r: float = maxf(0.0, walk_wave) * knee_bend_degrees * speed_ratio
	if sit_amount > 0.001:
		# 大腿向前抬（负角 = 抬起），膝盖向后折 —— 抱膝坐。
		leg_l = lerpf(leg_l, -sit_thigh_degrees, sit_amount)
		leg_r = lerpf(leg_r, -sit_thigh_degrees, sit_amount)
		knee_l = lerpf(knee_l, sit_knee_degrees, sit_amount)
		knee_r = lerpf(knee_r, sit_knee_degrees, sit_amount)
	_set_rot(_i_leg_ul, _q(_i_leg_ul, AXIS_RIGHT, leg_l))
	_set_rot(_i_leg_ur, _q(_i_leg_ur, AXIS_RIGHT, leg_r))
	_set_rot(_i_leg_ll, _q(_i_leg_ll, AXIS_RIGHT, knee_l))
	_set_rot(_i_leg_lr, _q(_i_leg_lr, AXIS_RIGHT, knee_r))

	# --- 尾巴：一直慢慢摆；走路加快，开心时摆得更欢 ---
	var wag_boost: float = 1.0
	if walking:
		wag_boost += 0.35
	wag_boost += happy_wag_boost * _happy_blend
	wag_boost += drink_tail_boost * feed_amount
	var wag_speed_now: float = tail_wag_speed * wag_boost
	var wag_amp: float = tail_wag_degrees * wag_boost
	for i in _i_tail.size():
		var idx: int = _i_tail[i]
		var phase: float = t * wag_speed_now - float(i) * 0.55
		var side: float = sin(phase) * wag_amp * (0.7 + float(i) * 0.12)
		var updown: float = sin(phase * 0.8 - 0.5) * wag_amp * 0.2
		_set_rot(idx, _q(idx, AXIS_UP, side) * _q(idx, AXIS_RIGHT, updown))

	# --- 耳朵：随机抖 + 开心竖起 / 害羞垂下 ---
	var ear_lift: float = 0.0
	ear_lift += ear_perk_degrees * _happy_blend
	ear_lift -= ear_droop_degrees * _shy_blend
	ear_lift += 2.0 * feed_amount   # 喝得舒服时耳朵微微支棱
	if walking:
		ear_lift += 1.5 * speed_ratio
	var twitch: float = _ear_twitch_amount()
	var ear_l_deg: float = ear_lift
	var ear_r_deg: float = -ear_lift
	if _ear_side > 0:
		ear_l_deg += twitch * ear_twitch_degrees
	else:
		ear_r_deg -= twitch * ear_twitch_degrees
	for i in _i_ear_l.size():
		var idx: int = _i_ear_l[i]
		_set_rot(idx, _q(idx, AXIS_FORWARD, ear_l_deg * EAR_FALLOFF[i]))
	for i in _i_ear_r.size():
		var idx: int = _i_ear_r[i]
		_set_rot(idx, _q(idx, AXIS_FORWARD, ear_r_deg * EAR_FALLOFF[i]))

	# --- 头发：轻微滞后摆动；走路时向后飘一点 ---
	for i in _i_hair_back.size():
		var idx: int = _i_hair_back[i]
		var side: float = sin(t * 2.0 - float(i) * 0.5) * hair_sway_degrees
		var fwd: float = sin(t * 1.6 - float(i) * 0.4) * hair_sway_degrees * 0.35 + speed_ratio * 2.0
		_set_rot(idx, _q(idx, AXIS_FORWARD, side) * _q(idx, AXIS_RIGHT, fwd))
	for i in _i_hair_l.size():
		var idx: int = _i_hair_l[i]
		var side: float = sin(t * 2.0 - float(i) * 0.5 + 0.9) * hair_sway_degrees
		var fwd: float = sin(t * 1.7 - float(i) * 0.4) * hair_sway_degrees * 0.3 + speed_ratio * 1.5
		_set_rot(idx, _q(idx, AXIS_FORWARD, side) * _q(idx, AXIS_RIGHT, fwd))
	for i in _i_hair_r.size():
		var idx: int = _i_hair_r[i]
		var side: float = sin(t * 2.0 - float(i) * 0.5 - 0.9) * hair_sway_degrees
		var fwd: float = sin(t * 1.7 - float(i) * 0.4) * hair_sway_degrees * 0.3 + speed_ratio * 1.5
		_set_rot(idx, _q(idx, AXIS_FORWARD, side) * _q(idx, AXIS_RIGHT, fwd))
	for i in _i_bangs.size():
		var idx: int = _i_bangs[i]
		var fwd: float = -_head_pitch * 0.06 + sin(t * 2.2 - float(i) * 0.4) * hair_sway_degrees * 0.3
		_set_rot(idx, _q(idx, AXIS_RIGHT, fwd))

	# --- 裙摆：跟着步子轻轻甩 ---
	var skirt_walk: float = walk_wave * skirt_sway_degrees * speed_ratio
	for i in _i_skirt_l.size():
		var idx: int = _i_skirt_l[i]
		_set_rot(idx, _q(idx, AXIS_RIGHT, -skirt_walk * (1.0 - float(i) * 0.25)))
	for i in _i_skirt_r.size():
		var idx: int = _i_skirt_r[i]
		_set_rot(idx, _q(idx, AXIS_RIGHT, skirt_walk * (1.0 - float(i) * 0.25)))

	# --- 模型本身的上下浮动 / 起跳 / 坐下下沉 / 拉伸压扁 ---
	var hop_y: float = _hop_offset()

	var idle_bob: float = sin(t * 2.0) * idle_bob_height
	var walk_bob: float = absf(sin(_walk_phase)) * walk_bob_height * speed_ratio
	var drink_bob: float = gulp * drink_bob_height * feed_amount
	_model.position = _base_model_position + Vector3(
		0.0,
		idle_bob + walk_bob + hop_y + drink_bob
			- sit_drop_height * sit_amount
			- shy_crouch_height * _shy_blend,
		0.0
	)
	var squash: float = _hop_squash()
	_model.scale = _base_model_scale * Vector3(1.0 - squash * 0.5, 1.0 + squash, 1.0 - squash * 0.5)


## 嘴部 overlay：挂点每帧贴到 head 骨骼上。
## 只在「吞咽那一下」显示约 mouth_open_time 秒，其余时间隐藏，恢复原本的脸。
## 嘴片相对挂点的位置/大小在场景里直接拖「嘴巴」节点调，不用改代码。
func _update_mouth() -> void:
	if _mouth == null or _mouth_anchor == null or _i_head < 0:
		return
	_mouth_anchor.global_transform = _skeleton.global_transform * _skeleton.get_bone_global_pose(_i_head)
	var show: bool = _gulp_progress >= 0.0 and _feed_blend > 0.02 and _happy_time <= 0.0
	_mouth.visible = show
	if not show:
		return
	# 嘴片本身画的是「张开」的形状，纵向缩放就是开合程度。
	var open_scale: float = lerpf(0.25, drink_mouth_scale, _gulp_open)
	_mouth.scale = _mouth_base_scale * Vector3(1.0, open_scale, 1.0)


# ---------------------------------------------------------------------------
# 各种小计时器
# ---------------------------------------------------------------------------

func _tick_blink(delta: float) -> void:
	if _blink_progress >= 0.0:
		_blink_progress += delta
		if _blink_progress >= blink_duration:
			_blink_progress = -1.0
			if _blink_double:
				_blink_double = false
				_double_wait = double_blink_gap
		return
	if _double_wait > 0.0:
		_double_wait -= delta
		if _double_wait <= 0.0:
			_blink_progress = 0.0
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_progress = 0.0
		_blink_double = _rng.randf() < double_blink_chance
		_blink_wait = _rand_range(blink_interval_min, blink_interval_max)


## 0 = 睁眼，1 = 完全闭眼。只用来决定闭眼贴片什么时候盖上去。
func _blink_amount() -> float:
	if _blink_progress < 0.0:
		return 0.0
	var t := clampf(_blink_progress / maxf(blink_duration, 0.01), 0.0, 1.0)
	return sin(t * PI)


func _tick_ear_twitch(delta: float) -> void:
	if _ear_progress >= 0.0:
		_ear_progress += delta
		if _ear_progress >= ear_twitch_duration:
			_ear_progress = -1.0
		return
	_ear_wait -= delta
	if _ear_wait <= 0.0:
		_ear_wait = _rand_range(ear_twitch_interval_min, ear_twitch_interval_max)
		_ear_progress = 0.0
		_ear_side = 1 if _rng.randf() < 0.5 else -1


func _ear_twitch_amount() -> float:
	if _ear_progress < 0.0:
		return 0.0
	var t := clampf(_ear_progress / maxf(ear_twitch_duration, 0.01), 0.0, 1.0)
	return sin(t * PI)


func _queue_hop(height: float) -> void:
	_hop_queue.append(maxf(0.0, height))
	if _hop_progress < 0.0:
		_start_next_hop()


func _start_next_hop() -> void:
	if _hop_queue.is_empty():
		return
	_hop_height_now = _hop_queue.pop_front()
	_hop_progress = 0.0


func _tick_hop(delta: float) -> void:
	if _hop_progress < 0.0:
		return
	_hop_progress += delta
	if _hop_progress >= hop_duration:
		_hop_progress = -1.0
		_start_next_hop()


func _hop_offset() -> float:
	if _hop_progress < 0.0:
		return 0.0
	var t := clampf(_hop_progress / maxf(hop_duration, 0.01), 0.0, 1.0)
	return 4.0 * _hop_height_now * t * (1.0 - t)


## 起跳时拉长、落地时压扁。正数 = 拉长，负数 = 压扁。
## 乘一个 sin 包络，让 t=0 / t=1 时都回到 0 —— 连续两下小跳之间不会「啪」地弹一下。
func _hop_squash() -> float:
	if _hop_progress < 0.0:
		return 0.0
	var t := clampf(_hop_progress / maxf(hop_duration, 0.01), 0.0, 1.0)
	return (1.0 - 2.0 * t) * hop_squash * 0.5 * sin(t * PI)


func _tick_idle_hop(delta: float) -> void:
	# 喂水 / 装满庆祝时只做吞咽或跳跃，不再叠一个待机小跳。
	if (_state != State.IDLE or _shy_time > 0.0 or _wave_time > 0.0
			or _hop_progress >= 0.0 or _is_feeding() or _happy_time > 0.0):
		return
	_idle_hop_wait -= delta
	if _idle_hop_wait <= 0.0:
		_idle_hop_wait = _rand_range(idle_hop_interval_min, idle_hop_interval_max)
		_queue_hop(idle_hop_height)


func _rand_range(a: float, b: float) -> float:
	return _rng.randf_range(minf(a, b), maxf(a, b))
