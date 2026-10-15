extends Node3D
class_name InteractStation

## 可交互台座：**「看着它 → 提示按 E → 弹出菜单 → 瞄准选 → 左键确认」这整套显示与流程都在这儿**。
## 具体某个物体卖什么、点了之后发生什么，由子类覆盖下面几个函数来定。
##
## 子类至少写这 4 个：
##   row_count()              菜单有几行
##   row_text(index)          第 index 行左边那句
##   row_price_text(index)    第 index 行右边那个价格
##   on_row_activated(index)  左键点了这一行之后干什么
## 想更细还可以覆盖：
##   row_state(index)         能不能选（选不了标红、做完了变灰）
##   panel_footer()           菜单底部那行（比如「邮币 x 3」），默认不显示
##   panel_title()            想让标题跟着状态变时才覆盖；不覆盖就用场景里「标题」上写的字
##   on_menu_opened() / on_menu_closed()   菜单开关时要做什么（比如把自己的武器关掉）
##   on_hold(delta) / on_hold_started() / on_hold_stopped()
##                                         长按期间每帧干什么（勾了 hold_enabled 才有用）
##
## **长按是可选的第二套动作，同一个 E 键分两种按法**（勾 hold_enabled 才开）：
##   点一下（松手时还没超过 hold_delay）→ 照旧开菜单；
##   按住不放（超过 hold_delay）        → 走 on_hold()，松手才结束。
## 消防栓就是这么做的：点按 E 升级装水速度，长按 E 接水。
## **不勾的机器（水枪升级台）行为一点没变** —— 按 E 仍然是「按下就开菜单」，没有延迟。
##
## **行就是菜单面板下的「交互选项行」子节点**，从上到下 = 第 0、1、2 行。
## 想加一行：在面板里再实例一个「交互选项行」，子类里多返回一行字，这里一行代码都不用改。
##
## 按 E 打开菜单时会同时做三件事：锁住玩家走动和跳跃、把视角限制在朝面板 ±look_range 度的
## 锥形里（免得一转开就找不到菜单）、把准星下面那行提示清掉（免得挡着选项）。
## **菜单里左键确认**，点右上角的 × 或再按一次 E 关闭 —— 特意不用 Esc：
## 那个键在 player.gd 里是「放开鼠标」，会把光标放出来打断操作。
##
## 「看着它」的判定：从摄像机中心朝前打一条射线，射线同时挂「可交互」层和「世界」层，
## 世界层是用来挡视线的 —— 隔着墙就不弹提示。物体自己要落在「可交互」层上（见 body）。
##
## 想做一个新物体：**新建继承场景** from `scenes/交互模板/交互台.tscn`
## （是继承不是复制 —— 继承出来的台座以后能跟着模板一起变），把模型拖进「模型」节点、
## 根节点换成你的子类脚本就行。面板、碰撞体、主人公、准星都是它自己找的，
## **一根线都不用接**（见 _resolve_refs）。

## —— 通用话术。每个字都能在检查器里改，代码里不存第二份 ——
@export_group("话术")
## 菜单最上面那行标题，每台机器填自己那句。**面板是全场共用一个场景的**，
## 所以标题只能由这里给（不然所有台子都会显示同一句）。
@export var title_text: String = ""
## 菜单**没开**、准星对着它时，准星下面那行字。
## 菜单开着时准星下面不写任何字（避免挡着选项），只剩下高亮和 × 作反馈。
@export var prompt_text: String = "按 E 交互"
## 选不了（钱不够 / 条件不满足）时那行字，也是子类弹提示时的默认文案。
@export var text_blocked: String = "条件不满足"
## 已经做完了时那行字。
@export var text_done: String = "已经完成"
## 成功时的默认文案。
@export var text_success: String = "操作成功"

## —— 下面四个引用**都是自动找的，检查器里没有对应格子，也不用接线**（见 _resolve_refs）——
## 结构跟模板不一样、自动找会找错时，在子类里重写 _resolve_refs()，
## 先把要指定的填上再调 super() 就行（已经填了的不会被覆盖）。
var panel: InteractPanel            # 菜单面板：自己下面第一个
var body: CollisionObject3D         # 自己的碰撞体：自己下面第一个挂在「可交互」层上的
var player: Player                  # 主人公：场景里「玩家」组（player.gd 自己登记）
var crosshair: InteractCrosshair    # 准星：场景里「准星」组（交互准星.gd 自己登记）

@export_group("交互")
## 隔多远还能交互（米）。射程之外不弹提示。
@export_range(0.5, 10.0, 0.1) var interact_distance: float = 3.0
## 交互射线查哪些层。默认「世界(1) + 可交互(5)」。
@export_flags_3d_physics var ray_mask: int = 17
## 走开多远自动收起菜单（米）。
@export_range(1.0, 20.0, 0.5) var close_distance: float = 4.5
## 菜单开着时把玩家锁住（不许走、不许跳）。
@export var lock_player: bool = true
## 菜单开着时视角能偏离面板方向多少度（上下左右同一个值）。填 0 = 完全锁死。
@export_range(0.0, 90.0, 1.0) var look_range: float = 35.0

@export_group("长按（可选）")
## 勾上后这一台**同时**支持两种按法：点按 E 开菜单 / 长按 E 走 on_hold()。
## 消防栓用它接水（点按升级、长按接水）；升级台这类纯菜单的机器保持不勾。
## 不勾时按 E 是「按下就开菜单」，跟以前一模一样，一点延迟都没有。
@export var hold_enabled: bool = false
## 按住多久才算「长按」（秒）。**这个值是留给「点按」的窗口**：
## 太短会把点按误判成长按（想开菜单却接起了水），太长则点一下要等很久菜单才弹。
@export_range(0.05, 1.5, 0.05) var hold_delay: float = 0.3
## 长按生效期间准星下面那行字（子类可以覆盖 hold_hint_text() 让它带进度）。
@export var hold_text: String = "按住中…"

## 「可交互」层（第 5 层）的值：碰撞体挂在这一层上，准星才打得到它。
const INTERACT_LAYER: int = 1 << 4

## 场景里唯一的玩家、准星会自己登记进这两个组（见 player.gd / 交互准星.gd 的 _enter_tree），
## 台座按组把它们捞出来 —— 所以**新物体拖进主场景，一根线都不用接**。
## 名字要和那两个脚本里的 GROUP 常量一致。
const GROUP_PLAYER: StringName = &"player"
const GROUP_CROSSHAIR: StringName = &"interact_crosshair"

## 「这会儿先别开菜单」组：**树里挂着这个组的节点存在时，全场台座按 E 都不弹菜单**。
## 炮台被拿在手上时就会把自己挂进去 —— 那会儿左键是「放置炮台」，
## 弹出菜单就成了两边抢同一个键（点选项 = 买了别的东西，而不是把炮台放下）。
## 名字要和 scripts/水枪/炮台发射器.gd 里的 GROUP_BLOCK_INTERACT 一致。
const GROUP_BLOCK_INTERACT: StringName = &"interact_blocked"

## 按哪个键开菜单。
const INTERACT_ACTION: StringName = &"interact"
## 用哪个动作确认。默认是鼠标左键 —— 和开火绑同一个键是正常的：
## 菜单开着时子类会把武器关掉，不会两边同时触发。
const SELECT_ACTION: StringName = &"select"

var _targeting: bool = false              # 准星这会儿是不是正对着自己
var _hit: int = InteractPanel.HIT_NONE    # 菜单里准星扫到的东西
var _pressing: bool = false               # E 按着还没松，也还没判定（等松手时才决定是点按还是长按）
var _press_time: float = 0.0              # 这一按已经按了多久；准星一移开就归零
var _holding: bool = false                # 长按已经生效，正在每帧调 on_hold()
var _body_layer: int = 0                  # 实体在场景里配的碰撞层，菜单开关时借出去、再还回来


func _ready() -> void:
	_resolve_refs()
	if is_instance_valid(body):
		_body_layer = body.collision_layer   # 记下它本来的层，菜单开关时借出去再还
	if is_instance_valid(panel):
		panel.close()   # 开机先把菜单收起来（场景里是亮着的，方便你在编辑器里摆）
	refresh_rows()
	if not InputMap.has_action(INTERACT_ACTION):
		push_warning("交互台：项目设置里没有「%s」这个输入动作，按 E 不会有反应" % INTERACT_ACTION)
	if not InputMap.has_action(SELECT_ACTION):
		push_warning("交互台：项目设置里没有「%s」这个输入动作，左键选不了" % SELECT_ACTION)


func _physics_process(delta: float) -> void:
	var collider: Object = _aimed_object()
	_targeting = is_instance_valid(body) and collider == body
	if hold_enabled:
		_update_hold(delta)
	if is_instance_valid(panel) and panel.is_open():
		_update_menu(collider)
	else:
		_update_prompt()


## E 开关菜单，左键确认。用事件（_unhandled_input）而不是每帧问 Input，是为了「按一下只算一次」。
##
## **这下 E 只在「菜单是我开的」或者「准星正对着我」的时候才吃掉**，其余一律放行给别的台座。
## 场景里可以摆好几台，而 Godot 是按场景树反序派发 _unhandled_input 的（树里靠后的节点先收到）——
## 要是谁都拦一下，最后进树的那台就会把 E 全吞掉，排在它前面的台座按 E 永远没反应。
## 放行是安全的：射线只返回一个碰撞体，各台座拿它跟自己的 body 比，所以同一时刻
## 最多只有一台是真的「被瞄着」的，不会出现两台抢着开菜单。
##
## **勾了 hold_enabled 的机器例外一处**：按下 E 时它先把这一下"收下"（吃掉事件）、但不马上开菜单，
## 等到**松手**那一刻才看按了多久 —— 够久就是长按（接水），不够久才算点按（开菜单）。
## 所以长按台座的菜单是「松手时」弹的，这是分辨点按和长按必须付的代价；hold_delay 调小就更快。
##
## **还有一条例外**：有人正拿着东西（炮台，见 GROUP_BLOCK_INTERACT）时全场一律不开菜单 ——
## 那会儿左键另有用途（放置），开了菜单就成了两边抢同一个键。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(INTERACT_ACTION):
		if is_instance_valid(panel) and panel.is_open():
			get_viewport().set_input_as_handled()
			close_menu()
			return
		if not _targeting:
			return   # 没瞄着我：这一下 E 归别人，别拦（理由见上面那段）
		if _interact_blocked():
			return   # 有人正拿着东西（炮台）：先让他放下，这一下 E 谁都不开菜单
		get_viewport().set_input_as_handled()
		if hold_enabled:
			# 开着长按的机器：**按下先不开菜单**，等松手时才定夺 ——
			# 按下那一瞬间没法知道玩家打算按多久，见 _update_hold()。
			_pressing = true
			_press_time = 0.0
			return
		open_menu()
		return
	if event.is_action_released(INTERACT_ACTION) and _pressing:
		# 这一按是我们收下的，松手也归我们处理：
		# 已经长按生效了 → 收工；没到门槛就松手 → 那一下算点按，开菜单。
		_pressing = false
		if _holding:
			_end_hold()
		elif _targeting:
			open_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(SELECT_ACTION) and is_instance_valid(panel) and panel.is_open():
		get_viewport().set_input_as_handled()
		_activate(_hit)


## 展开菜单：先把行算好，再开面板、锁玩家。
func open_menu() -> void:
	if not is_instance_valid(panel) or panel.is_open():
		return
	refresh_rows()
	panel.open()
	_hit = InteractPanel.HIT_NONE
	_set_body_rayable(false)
	_lock_player()
	on_menu_opened()


## 收起菜单：解锁玩家、还原现场。
func close_menu() -> void:
	if not is_instance_valid(panel) or not panel.is_open():
		return
	panel.close()
	_hit = InteractPanel.HIT_NONE
	_set_body_rayable(true)
	_unlock_player()
	on_menu_closed()


## 把所有行重算一遍塞进面板（开菜单、买完、钱变了都要调）。
## 子类只要实现 row_text / row_price_text / row_state，这里自动按行数铺开。
func refresh_rows() -> void:
	if not is_instance_valid(panel):
		return
	var count: int = row_count()
	panel.set_row_count(count)
	var title: String = panel_title()
	if not title.is_empty():
		panel.set_title(title)
	panel.set_footer(panel_footer())
	for index: int in count:
		panel.update_row(index, row_text(index), row_price_text(index), row_state(index))


## 在菜单中间弹一句提示（子类里买完东西时调）。
func show_message(text: String, ok: bool) -> void:
	if is_instance_valid(panel):
		panel.show_message(text, ok)


# —— 下面这些是给子类覆盖的 ——


## 菜单有几行。默认 0 行（等于没东西可卖）。
func row_count() -> int:
	return 0


## 第 index 行左边那句说明。
func row_text(_index: int) -> String:
	return ""


## 第 index 行右边的价格。
func row_price_text(_index: int) -> String:
	return ""


## 第 index 行现在能不能选。
func row_state(_index: int) -> InteractOptionRow.State:
	return InteractOptionRow.State.OK


## 左键点了第 index 行之后干什么（扣钱、改数值、弹提示，都在这儿）。
func on_row_activated(_index: int) -> void:
	pass


## 菜单底部那行字（比如「邮币 x 3」）；返回空字符串就不显示。
func panel_footer() -> String:
	return ""


## 菜单标题。默认就用上面那个 `title_text`（在检查器里填）；
## 想让标题跟着状态变（比如「升级水枪 Lv.3」）就覆盖这个函数。
## 返回空字符串 = 用面板场景自己写的那句，一般不会走到这儿。
func panel_title() -> String:
	return title_text


## 菜单刚打开时调一次。
func on_menu_opened() -> void:
	pass


## 菜单收起时调一次。
func on_menu_closed() -> void:
	pass


## 长按正在生效，每物理帧调一次（delta 是秒）。消防栓在这儿往水枪里灌水。
func on_hold(_delta: float) -> void:
	pass


## 长按刚开始（按住够 hold_delay 的那一下）。
func on_hold_started() -> void:
	pass


## 长按结束（松手 / 准星移开）。**和 on_hold_started() 一定成对**，还原现场写这儿。
func on_hold_stopped() -> void:
	pass


## 长按生效时准星下面那行字。默认就是上面那个 hold_text；
## 想让字数着涨（「接水中 45%」）就覆盖它。
func hold_hint_text() -> String:
	return hold_text


## 菜单没开时的每帧更新：正对着就提示按 E，否则把提示清掉。
## 第二个参数是「这行字归我」—— 场景里每台台座都在每帧写这一行，准星靠它决定
## 谁的「擦掉」算数（见 交互准星.gd 的 set_hint），不传的话没瞄到目标的台座会把别人的提示抹掉。
func _update_prompt() -> void:
	if not is_instance_valid(crosshair):
		return
	# 有人正拿着东西（炮台）时这行字归他（「左键放置炮台」），台座别去抢 ——
	# 两边每帧各写一次的话，准星那行字会在两句话之间来回拉锯（见 交互准星.gd 认主那段）。
	if _interact_blocked():
		return
	# 长按生效时这行字换成「正在干什么」（子类可以覆盖 hold_hint_text() 让它带进度）
	if _holding:
		crosshair.set_hint(hold_hint_text(), self)
		return
	crosshair.set_hint(prompt_text if _targeting else "", self)


## 长按的判定与维持（只有勾了 hold_enabled 的机器走得到这儿）。
##
## 按下的那一瞬间没法知道玩家打算按多久，所以**先记账、不下结论**：
## 按满 hold_delay 且准星还对着自己 → 才算长按；没按满就松手 → 那一下算点按，开菜单。
##
## 中途把准星移开就立刻结束长按，计时也归零 —— 于是走回来还得重新按满这么久，
## 不会出现「一瞄上就啪地开始接水」。松手、移开、以及以后可能加的"被临时打断"，
## 全都汇聚到 _end_hold()，保证 on_hold_started() / on_hold_stopped() 一定成对。
func _update_hold(delta: float) -> void:
	if not _targeting:
		_press_time = 0.0
	elif _pressing and not _holding:
		_press_time += delta
		if _press_time >= hold_delay:
			_holding = true
			on_hold_started()
	if _holding and (not _targeting or not Input.is_action_pressed(INTERACT_ACTION)):
		_end_hold()
	if _holding:
		on_hold(delta)


## 结束长按。重复调用无副作用。
func _end_hold() -> void:
	if not _holding:
		return
	_holding = false
	on_hold_stopped()


## 菜单开着时的每帧更新：算准星扫到哪一项、高亮它。
## **准星下面不写任何提示文字** —— 菜单里靠「哪一行亮着」和右上角的 × 反馈就够了，
## 再多一行字反而挡着选项。想让玩家看到「左键 升级 · 3 枚」这类字，
## 在这里加一句 crosshair.set_hint("...", self) 就接回来了。
func _update_menu(collider: Object) -> void:
	_hit = panel.hit_test(collider)
	panel.set_hit(_hit)
	if is_instance_valid(crosshair):
		crosshair.set_hint("", self)
	if _far_from_player():
		close_menu()


## 左键按下时：扫到 × 就关，扫到某项就让子类去处理，处理完重算一遍行。
func _activate(hit: int) -> void:
	if hit == InteractPanel.HIT_CLOSE:
		close_menu()
		return
	if hit < 0:
		return
	on_row_activated(hit)
	refresh_rows()


## 锁住玩家：不许走、不许跳，视角也只能在面板方向附近转。
func _lock_player() -> void:
	if not is_instance_valid(player):
		return
	if lock_player:
		player.set_move_lock(true)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(panel) and cam != null:
		player.lock_look(panel.global_position - cam.global_position, look_range)


## 解锁。
func _unlock_player() -> void:
	if not is_instance_valid(player):
		return
	player.set_move_lock(false)
	player.unlock_look()


## 菜单开着时把「实体」从射线里摘掉（碰撞层归零），收起时还回来。
##
## **菜单开着的时候，实体一点用都没有** —— 菜单里的命中判定全靠每一行的「选中区」，
## 而实体唯一的职责是「看着它才能开菜单」，那件事已经做完了。留着它反而会出事：
## 只要面板摆得离机器近一点（炮台商店就是），菜单下面几行就会被**自己这台机器**的碰撞盒
## 罩在肚子里 —— 射线先撞上盒子、压根到不了那一行的选中区，表现为「除了最上面那行，
## 别的怎么扫都没反应」。炮台商店的面板摆在 z=0.29，而模板给的碰撞盒前面伸到 z=0.40，
## 就是这么撞上的。
##
## **这是「菜单收起时把每行的选中区关掉」的镜像**，那一手见 交互选项行.gd 的文件头：
## 菜单收起时选中区不能横在射线里，菜单开着时实体不能横在射线里，两边各关一半，射线才干净。
##
## 代价：菜单开着那几秒，这台机器对水、对玩家都不挡了。玩家这时候本来就被 lock_player
## 锁着不动，所以看不出来；水团从商店模型里穿过去属于完全可以接受的边角。
##
## 用 set_deferred：碰撞层是物理状态，在物理帧里直接改会被引擎拒绝。
func _set_body_rayable(on: bool) -> void:
	if is_instance_valid(body):
		body.set_deferred("collision_layer", _body_layer if on else 0)


## 这会儿是不是「全场先别开菜单」—— 有人（拿在手上的炮台）挂着 GROUP_BLOCK_INTERACT 就算。
## 只在按 E 那一下问一次、不是每帧扫，所以这点开销可以忽略。
func _interact_blocked() -> bool:
	return get_tree().get_first_node_in_group(GROUP_BLOCK_INTERACT) != null


## 从摄像机正中心朝前打一条射线，返回打到的东西；没打到返回 null。
## 水块和吸水区在别的层上，所以水从眼前飞过不会把提示打断。
func _aimed_object() -> Object:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_basis.z * interact_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, ray_mask)
	# 菜单的选项和 × 都是 Area3D，而射线默认只打刚体 —— 不打开这个开关，永远选不中
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	return collider


## 玩家是不是已经走远了（菜单该收起来了）。
func _far_from_player() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_to(global_position) > close_distance


## 把四个引用自动找齐。**有这一手，新物体拖进主场景就什么线都不用接。**
##
## 面板和碰撞体是自己下面的子节点；主人公和准星住在主场景里
## （台座单独存成一个场景时它们根本不在场，检查器里想连也连不上），
## 那两个脚本在 _enter_tree 里把自己登记进组，这里按组捞 ——
## 所有节点的 _enter_tree 都跑完了才会有第一个 _ready，所以这里一定找得到。
##
## 结构跟模板不一样、自动找会找错时，**在子类里重写这个函数**：
## 先把自己要指定的那几项填上，再调 super() 即可（已经填了的不会被覆盖）。
## 例：
##     func _resolve_refs() -> void:
##         body = $外壳/碰撞体      # 这台机器的碰撞体藏在里面
##         super()                  # 其余三项照旧自动找
func _resolve_refs() -> void:
	if not is_instance_valid(panel):
		panel = _find_child_panel()
	if not is_instance_valid(body):
		body = _find_child_body()
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(GROUP_PLAYER) as Player
	if not is_instance_valid(crosshair):
		crosshair = get_tree().get_first_node_in_group(GROUP_CROSSHAIR) as InteractCrosshair
	# 找不到就当场喊一声：这几项都是自动找的，不喊的话表现只是"没反应"，很难查
	if not is_instance_valid(body):
		push_warning("交互台（%s）：找不到碰撞体，准星打不到它 —— 把「实体」挂在根节点下，并勾上「可交互」层。" % name)
	if not is_instance_valid(panel):
		push_warning("交互台（%s）：找不到菜单面板，按 E 不会有反应 —— 把面板挂在根节点下。" % name)
	if not is_instance_valid(player):
		push_warning("交互台（%s）：场景里没有「%s」组，菜单打开时锁不住玩家（主人公挂了 player.gd 就会自动进这个组）。" % [name, GROUP_PLAYER])
	if not is_instance_valid(crosshair):
		push_warning("交互台（%s）：场景里没有「%s」组，屏幕上不会有提示（HUD 里的准星挂了 交互准星.gd 就会自动进这个组）。" % [name, GROUP_CROSSHAIR])


## 自己下面第一个菜单面板。
func _find_child_panel() -> InteractPanel:
	for child: Node in get_children():
		if child is InteractPanel:
			return child as InteractPanel
	return null


## 自己下面第一个碰撞体 —— 就是那个又挡人、又被射线打的「实体」。
## **优先挑挂在「可交互」层上的那个**：机器上可能还有别的碰撞体（模型自带的、装饰用的），
## 只有勾了可交互层的那一个才是给准星打的。
func _find_child_body() -> CollisionObject3D:
	var fallback: CollisionObject3D = null
	for child: Node in get_children():
		if child is not CollisionObject3D:
			continue
		var collider: CollisionObject3D = child as CollisionObject3D
		if (collider.collision_layer & INTERACT_LAYER) != 0:
			return collider
		if fallback == null:
			fallback = collider
	return fallback
