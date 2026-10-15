extends Node
class_name WaterReward

## 水量换币：有水流进**任何一个**吸水区，就按水量攒邮币 —— 攒够 water_per_coin 立方米
## 就往账本里加 coins_per_step 枚，零头留着，下一发接着攒。
##
## **它是照着「吸水区」组把容器捞上来的**：开机时
## `get_nodes_in_group(WaterSink.GROUP_WATER_SINK)` 一次把全场吸水区都拿上，各自连 water_received。
## 所以再摆一个新容器不用回来改这个脚本 —— 只要那个节点挂的是 `吸水区.gd`（或继承它的子类），
## 它进树时就会自己登记进组（见 吸水区.gd 的 _enter_tree），`吸水区.gd` 里没有一行是为邮币写的。
##
## **全场只该有一份**，所以它跟钱包住在一起（`scenes/money.tscn` 里挂在 Money 下面）——
## 钱包全场只有一份，它就只会有一份。**挂两份就是双倍发钱。**
##
## 「装满就停」是靠**看容器水位涨了多少**实现的，不是看这团水多大：
## 装满之后 amount 不再上涨，增量自然是 0，也就不再发钱 ——
## 不用另外判断「满了没有」，也不用纠结「正好装满的那一发算不算」。
##
## 币按**水量**给、不按发数给，所以升级「水块大小」之后每发更大、单位时间赚得更快，
## 但攒一枚要的水量不变 —— 经济不会被升级刷爆，之前攒的币也不会贬值。
##
## **局限：只在开机时捞一次组**，运行时才生成的吸水区不会被自动盯上。
## 真要做「能放下的水桶」那类玩法，放完之后调一次 rescan()。


## 邮币账本（右上角那个数字）。**这个必须接**，不接就只是白攒。
@export var wallet: CurrencyLabel
## 攒够多少立方米给一次币。**填 0 = 关掉**（和项目里 capacity 填 0 的约定一致）。
##
## 换算成发数：一发水的体积 = 水枪的 blob_size 的三次方。主场景现在是 0.1 米的水块，
## 一发 0.001 m³，所以 0.01 ≈ **10 发一枚**，一整箱水（1 m³）全射进去约 100 枚。
## 填大了钱来得慢，填小了站着刷几下就满了 —— 手感不对就只动这一个数。
@export_range(0.0, 10.0, 0.001) var water_per_coin: float = 0.01
## 每攒够一次给几枚。
@export_range(1, 999, 1) var coins_per_step: int = 1

## 攒了一半、还没凑够一枚的水（立方米）。**发完币要留下零头**，不能清零 ——
## 清零的话阈值不是单发水量的整数倍时，玩家每发都白丢一点水，永远攒不满。
var _progress: float = 0.0
## 容器 id → 这个容器**已经算过钱的水位**。存 id 不存节点，容器被删了也不会留下野引用。
## 发币靠的是「水位涨了多少」，所以记的是水位本身，不是累计水量。
var _paid: Dictionary = {}


func _ready() -> void:
	if not is_instance_valid(wallet):
		push_warning("水量换币：没接邮币账本，攒出来的币没处放 —— 把同一个场景里的 Money2 拖到 wallet 上。")
	rescan()
	if _paid.is_empty():
		push_warning("水量换币：一个吸水区都没找到，射水不会给币（吸水区要在 _enter_tree 里登记进「%s」组）。" % WaterSink.GROUP_WATER_SINK)


## 把「吸水区」组里的容器重新捞一遍，没收下的收下。
## 开机自动跑一次；**运行时才生成的吸水区要自己再调一次**（见文件头那条局限）。
func rescan() -> void:
	for node: Node in get_tree().get_nodes_in_group(WaterSink.GROUP_WATER_SINK):
		var sink: WaterSink = node as WaterSink
		if sink != null:
			_watch(sink)


## 盯上一个吸水区。**从它现在的水位起算** —— 场景里预填的水不打折成币。
func _watch(sink: WaterSink) -> void:
	var id: int = sink.get_instance_id()
	if _paid.has(id):
		return   # 已经盯上了（rescan 可能又捞到同一个），别连两次
	_paid[id] = sink.amount
	sink.water_received.connect(_on_water_received.bind(sink))


## 有水进来了。**不看这团水多大，看容器水位涨了多少** —— 装满之后水位不涨，增量就是 0。
func _on_water_received(_volume: float, sink: WaterSink) -> void:
	var id: int = sink.get_instance_id()
	var level: float = sink.amount
	var gained: float = level - float(_paid.get(id, 0.0))
	# 不管发不发币都记下当前水位：这样运行时把阈值从 0 调回正数，也不会补发之前攒的那一坨。
	# （顺带自愈：万一以后有玩法把容器里的水放掉，水位降了也不会一直「欠着」不发钱。）
	_paid[id] = level
	if gained <= 0.0 or water_per_coin <= 0.0:
		return
	_progress += gained
	var coins: int = floori(_progress / water_per_coin)
	if coins <= 0:
		return
	_progress -= coins * water_per_coin   # 只减掉发出去的那几档，零头留着
	if is_instance_valid(wallet):
		wallet.add_money(coins * coins_per_step)


## 距离下一枚还差几成（0 ~ 1）。
## 以后想在屏幕上写「再射 0.003 m³ 就有一枚」，接这个就行，不用自己去读 _progress。
func progress_ratio() -> float:
	if water_per_coin <= 0.0:
		return 0.0
	return clampf(_progress / water_per_coin, 0.0, 1.0)
