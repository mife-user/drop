# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> 本项目由中文团队开发。**所有代码注释、面向用户的说明、以及 git 提交信息一律使用中文。**

---

## 项目概况

- **引擎**：Godot **4.8**（本项目 `config/features` 要求的版本；已在 4.8-dev6 上验证）。Forward+ 渲染，Windows 下使用 D3D12 驱动，3D 物理引擎为 **Jolt Physics**
- **引擎可执行文件**：**每台机器安装位置不同，不要假设固定路径。**下面的命令统一用 `$GODOT` 变量指代，使用前先按下文「确定 Godot 可执行文件位置」找到本机路径并赋值。
- **项目名**：drop —— TapTap 比赛作品，赛题「涌现」
- **主场景**：`scenes/main.tscn`

---

## 确定 Godot 可执行文件位置

> 团队成员各自 OS / 安装位置 / 版本后缀不同，以下路径**仅为示例**，不要照抄。

先确认版本是 `4.8`（本项目 `config/features` 写的是 `4.8`），再找到可执行文件：

```bash
# 若已加入 PATH（最常见的好情况）
godot --version
# 输出前缀以 4.8 开头即可（后面可能带 .devN 或具体的 stable 版本号）

# 示例：Windows/Git Bash 下搜索（把 <Godot安装目录> 换成你自己的位置，可多给几个候选目录）
find "<Godot安装目录>" -maxdepth 3 -iname "Godot*v4.8*.exe" 2>/dev/null
```

Linux / macOS 对应 `which -a godot`、`ls /Applications | grep -i godot`，或直接用自行编译 / 包管理器安装的 `godot4`。

拿到路径后赋值给变量，后续命令即可原样复制执行：

```bash
GODOT="<Godot可执行文件的完整路径>"   # ← 换成你自己机器上的路径
"$GODOT" --version
```

> Windows 下优先用带 `_console` 后缀的那个可执行文件：它会附带 stdout 输出，`--headless` 的日志和脚本里的 `print()` 才看得到。

---

## 常用命令

```bash
# 1) 生成 .uid / 导入新资源（新增脚本、模型、贴图后必须执行一次）
"$GODOT" --headless --editor --quit --path .

# 2) 语法检查单个脚本（有解析错误时退出码为 1，可直接用于 CI / 自测）
"$GODOT" --headless --check-only --script scripts/xxx.gd --path .

# 3) 验证某个场景能否正常加载运行（跑 2 帧后退出）
"$GODOT" --headless --path . res://scenes/main.tscn --quit-after 2

# 4) 打开编辑器
"$GODOT" --path .
```

**过滤无意义噪音**：headless 退出时会刷屏 `Leaked instance dependency` / `RID allocations were leaked` / `ObjectDB instances were leaked`，这是引擎退出时的正常噪音，**不是错误**。用这条管道筛掉：

```bash
"$GODOT" --headless --path . res://scenes/main.tscn --quit-after 2 2>&1 \
  | grep -viE "leaked|RID alloc|instance_notify|ObjectDB|resources still|servers/rendering|at: "
```

真正该关注的是：`SCRIPT ERROR` / `Parse Error` / 脚本里的 `push_error`，以及 `print` 输出是否符合预期。

---

## 铁律：AI 的改动必须在 Godot 编辑器里可见、可编辑

这是本仓库最重要的一条约束。AI 写的任何东西，用户打开 Godot 后都必须能正常看到、选中、改属性。因此：

1. **不要用 `_ready()` 里 `add_child()` 的方式"造"节点来绕过场景文件。**
   节点应该写进 `.tscn`，用户在远程场景树（Remote Scene Tree）里能看到它们，在编辑器的场景树里也能直接改。
   代码动态生成的节点只在"数量不定/运行时才知道"时才用（如随机刷出的小怪），且此时要给节点 `name` 和中文注释说明。

2. **脚本必须真的挂到节点上**，而不是只创建了 `.gd` 文件。
   在 `.tscn` 中通过 `script = ExtResource("...")` 挂载。挂载后用户点开该节点能在检查器里看到 `@export` 变量。

3. **`@export` 是第一公民。** 凡是美术、策划、用户可能想调数值（速度、半径、颜色、开关），一律暴露成 `@export` 并写中文注释，让用户能在检查器里直接改，而不是每次回来改代码。

4. **写完场景/脚本后，按上面的命令 1) + 3) 自测一遍**，确认没有解析错误、能正常加载。

---

## 手写 `.tscn` 的规则（已实测）

Godot 4.8 对**纯手写、不写 uid** 的 `.tscn` 完全兼容，编辑器打开后**不会**重写你的 `ext_resource` 行。可以放心手写。

```gdscript
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/foo.gd" id="1_foo"]
[ext_resource type="PackedScene" path="res://resources/bar/bar.glb" id="2_bar"]

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3(1, 1, 1)

[node name="Root" type="Node3D"]

[node name="Foo" type="Node3D" parent="."]
script = ExtResource("1_foo")

[node name="Bar" parent="." instance=ExtResource("2_bar")]
```

要点：

- **`ext_resource` 的 `uid` 可以省略**，只写 `path` 即可，Godot 会按路径解析。
  如果想带上 `uid`，必须和该资源的 `.gd.uid` / `.import` 文件里的值一致，写错反而会报错。
- `instance=ExtResource(...)` 的那一行**不要写 `type=`**，这是继承源场景的实例。
- 父路径用相对写法：根节点省略 `parent`，子节点 `parent="."`，孙节点 `parent="Foo"`。
- `Transform3D(xx, xy, xz, yx, yy, yz, zx, zy, zz, ox, oy, oz)` —— 前 9 个是**基向量按列排列**，最后 3 个是原点坐标。只改位置时保持前 9 个为 `1,0,0, 0,1,0, 0,0,1`。
- 节点名可以用中文（本项目已有 `奶蛋`、`场景` 等），场景文件是 UTF-8。

**新增脚本后必须跑一次命令 1)**：Godot 会自动生成 `scripts/xxx.gd.uid`。
这些 `.uid` 文件和资源的 `.import` 文件**都要提交到 git**（`.gitignore` 只忽略了 `.godot/`）。

---

## 节点选择速查

用户不一定熟悉各类节点的用途。AI 在新增节点时，**必须为选择该节点给出理由**（写在中文注释或回复里），并让它在编辑器里可见。

### 静态物体 / 美术

| 需求 | 选它 | 为什么 |
|---|---|---|
| 纯占位、挂子节点、分组 | `Node3D` | 没有额外开销，只提供变换和层级 |
| 显示模型 | `MeshInstance3D` | 只负责渲染，不参与物理；`mesh` 属性在检查器里换 |
| 导入的模型（.glb/.fbx） | 用 `instance=ExtResource()` 实例化整个 PackedScene，**不要**手动拆成 MeshInstance3D | 保留原始层级、材质、骨骼；拆开会丢失蒙皮和动画 |
| 摄像机 | `Camera3D` | —— |
| 环境/天空盒/雾/泛光 | `WorldEnvironment` + `Environment` 子资源 | 全局环境设置，一个场景放一个即可 |
| 平行光（太阳） | `DirectionalLight3D` | 方向光，无衰减，适合日光；本项目 `scripts/sun.gd` 已挂在它上面做昼夜循环 |

### 需要"能碰到"的东西

| 需求 | 选它 | 为什么 |
|---|---|---|
| 静态碰撞（墙、地板、房子） | `StaticBody3D` + `CollisionShape3D` | 不受力、不移动，物理开销最低 |
| 会移动的物体（玩家、掉落物） | `CharacterBody3D`（有移动逻辑）或 `RigidBody3D`（交给物理演算） | `CharacterBody3D` 由代码控制、不会被打飞；`RigidBody3D` 由物理引擎推 |
| 只做"检测"，不阻挡 | `Area3D` + `CollisionShape3D` | 触发区/拾取范围/水域判定，不产生物理阻挡 |
| 射线打不中/不参与碰撞 | 在 `CollisionObject3D` 上设 `collision_layer` / `collision_mask` | 分层过滤，比加判断代码更高效 |

> **`CollisionShape3D` 必须挂 `shape` 子资源**（`BoxShape3D` / `SphereShape3D` / `CapsuleShape3D` / `ConcavePolygonShape3D` 等），否则该碰撞体完全不生效且编辑器会报警告。形状要匹配模型尺寸，外形复杂的再用 `ConcavePolygonShape3D`（仅静态物体可用）。

### 组织与逻辑

| 需求 | 选它 | 为什么 |
|---|---|---|
| 把子节点打包成可复用单元 | 拆成独立 `.tscn` 再实例化 | 改一处全场景生效，是本项目推荐做法 |
| 一条变化的数值（血量、时间） | `Node` + `@export` 变量 | 保持简单，不引入不必要层级 |
| UI | `CanvasLayer` 打底，内部用 `Control` 系列 | `CanvasLayer` 不受 3D 相机影响，做 HUD 必加 |
| 音效 | `AudioStreamPlayer3D`（有方位感）/ `AudioStreamPlayer`（全局 BGM） | —— |

---

## GDScript 规范

```gdscript
extends Node3D

## 一句话说明这个脚本负责什么（中文）。
## 需要时补充第二段解释机制。

## 每个 @export 都要有一行中文说明，用户靠它在检查器里理解参数含义
@export var move_speed: float = 5.0

var _internal_timer: float = 0.0   # 私有变量用 _ 前缀，行尾写中文注释


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass
```

- **必须有中文注释**。`@export` 变量、`_ready`/`_process` 等生命周期函数、以及任何非直觉的算法逻辑都要注释。
- 参考 `scripts/sun.gd` 的写法：文件头用 `##` 写整体说明，每个 `@export` 上方用 `##` 写参数说明，机制性的行内用 `#`。
- 使用 **静态类型**（`func f(x: float) -> void:`、`@export var n: int`），Godot 4.8 下能更早发现错误。
- 缩进用 **Tab**（Godot 默认；`.editorconfig` 只强制 UTF-8）。
- 信号用 `signal` + `connect()`，命名用中文注释说明触发时机。
- 命名：文件/函数/变量用 `snake_case`，节点/类名用 `PascalCase`。

---

## 资源与场景结构

```
addons/markdown_previewer/   Markdown 预览插件（编辑器内读 .md，已在 project.godot 启用）
resources/
  场景.fbx                   House 场景模型（已导入为 PackedScene）
  奶蛋/奶蛋.glb              「奶蛋」角色模型 —— 实际使用的资源
  奶蛋/奶蛋.pmx              PMX 原始文件，Godot 4.8 无内置导入器，无 .import，不参与构建
  奶蛋/奶蛋_奶蛋.png         贴图
scenes/main.tscn             主场景（run/main_scene）
scenes/水块.tscn             一团水（scripts/水块.gd）
scenes/吸水区.tscn           吞吐水的通用区域（scripts/吸水区.gd）
scripts/milkegg.gd           「奶蛋」角色脚本（挂在 奶蛋 节点）
scripts/sun.gd               太阳昼夜循环（挂在 DirectionalLight3D）
scripts/水枪.gd              水枪发射器（挂在 主人公/水枪发射器）
scripts/水块.gd              水团：飞行 / 落地 / 合并 / 消失
scripts/水块容器.gd          水团的出生点与登记处（挂在 水块容器）
scripts/吸水区.gd            吸水区：水飘进来就收下
```

### 水的玩法（一套互相不认识的通用件）

三个脚本刻意互不依赖，加东西时别把它们串起来：

- **`水枪.gd`** 只负责「什么时候、从哪儿、朝哪个方向吐出一团水、这团水多大」。
  它不知道水飞多快、怎么合并。**全项目只有它定义「一发水的初始大小」**（`blob_size`）。
- **`水块容器.gd`（WaterField）** 是唯一知道「水长什么样、弹道什么手感、合并规则」的地方 ——
  换水模型改它的 `blob_scene`，调弹道改 `muzzle_speed` / `gravity`，
  调合并阶梯改 `grow_factor` / `max_size` / `merge_gap` / `merge_size_tolerance`，
  调水在地上一待多久改 `lifetime`。
  **水的行为参数一律放这个节点，不要往 `水块.tscn` 上加** —— 水块是运行时才生成的，
  在主场景的检查器里看不到它，调一次要来回切文件，很容易调出对不上的组合。
  水团是运行时才知道出几个的，所以由它 `add_child` 挂在自己下面（远程场景树里能看到，名字是「水 0.35m」）。
- **`水块.gd`（WaterBlob）** 负责飞行、落地、合并、到点消失。它**不认识水池**。
- **`吸水区.gd`（WaterSink）** 是通用件：任何「水」层的东西飘进来就被收下，水面随水量上涨。
  放在水池、消防栓、花盆旁边都行，摆几个都行。吸收后要接别的玩法（音效、计数、开门）就连
  它的 `water_received` / `filled` 信号，**不要**改脚本里的判定。
- **射满木碗才会出奶蛋**：主场景里奶蛋默认**永远不出现** —— `奶神` 的 `gate_sink` 指向
  `场景/木碗/吸水区`，射满它（默认容量 0.025 m³ ≈ 6 发）才从 `spawn_marker`
  （`场景/木碗/出生点`）蹦出一颗，漫游 30 秒后离场，**这一颗走完就永久停工**。
  木碗是一次性启动开关，不是循环的蛋源；`gate_sink` 留空 = 退回原来那套无限随机出场。
  门槛是靠 `milkegg_encounter.gd` 去连 `WaterSink.filled` 实现的，`吸水区.gd` 一行没改 ——
  同一个信号还被 `场景/木碗/OmniLight3D` 上的 `scripts/水量灯.gd` 拿去把灯点亮，
  被 `奶神/奶蛋/字幕层/解锁字幕` 上的 `scripts/水量字幕.gd` 拿去弹金色字幕。
  主场景改的是这三处连接 + 一个 `出生点` Marker3D，没有新增任何"木碗专用"的逻辑。
  **要加新的「装满后发生什么」，一律去连 `filled` 信号，别改吸水区。**

身份靠**碰撞层**而不是「是不是水池」来认：`水块` 在「水」层（第 3 层）、`吸水区` 在第 4 层。
水块的 `mask` 只勾「水」层，所以它只找得到同类、看不到吸水区；吸水区的 `mask` 也只勾「水」层。
**以后加新样式的水，只要根脚本继承 `WaterBlob`、碰撞层留在「水」层，就会自动被吸收、自动参与合并。**

### 弹道是自由抛物线，不是直线

水一出膛就只受 `水块容器.gravity`（默认 9.8）支配，**没有任何预计算的落点**：
每帧 `水块.gd` 从上一帧位置到当前位置打一条射线（线段查询，所以再快也不会穿薄墙），
按命中面法线分流 —— 这是**故意设计成这样**的关键一处：

- 法线竖直分量 `>= ground_normal_y`（默认 0.9）→ 算「地面」，沿法线抬半个身位贴上去落地，
  再走上面的合并 / 到时消失流程。
- 否则算撞在墙面 / 屋顶 / 围栏上 → **水花散掉，直接 `queue_free()`**，不留水洼。

因为准星方向就是出膛方向，水**会明显落在准星下方**，玩家得自己抬头补提前量。
这是 2026-10-11 讨论后有意选的（另一条路是「射线定落点 + 反解发射角」让准星保持精确，
真要改回准确准星，去改 `水枪.gd` 的 `_fire()` 和 `水块.gd` 的 `_fly()`，别在别处加补丁）。

`muzzle_speed = 15` 时的手感参考（站立、枪口约 1.5 米高）：
平视约打 8 米、抬 15° 约 15 米、抬 30° 约 22 米、抬 45° 最远约 24 米。

### 合并：按「边长」认，不按「等级」认

两团水**水种相同、大小差不多**、表面间距小于 `merge_gap` 时合成一团，
新水团在两者正中间、底面仍贴地，边长取两者较大的那个 × `grow_factor`。

- **没有「等级」这个概念**，身份就是边长 `size`：判等看相对差（`merge_size_tolerance`，默认 5%），
  到顶看 `size >= max_size`。
  **不要改回等级制** —— 多把水枪射出不同大小的水时，两团都叫「1 级」但边长可能差一倍，
  按等级合并会在 `_merge_with()` 里算出两个不同的贴地高度，位置就错了。
  容差也**不能**调到 13% 以上，否则相邻两档会被误判成同一档（合并倍率是 26%）。
- **水种 `water_type` 不用配置**，直接取 `blob_scene` 的场景路径 —— 换个水模型就是换个水种，
  地上旧的水不会跟新射出来的混在一起。
- `max_size` 是「**达到就冻结**」而不是「超过才不许合」：填 1.5 时最大的水可能是 1.77 米那一档，
  因为它是 1.40 米的两团合出来的，合完才发现过线。
- 水量 `volume` 就是 `size³`，**绝对的立方米，不带任何「相当于几发基础水」的换算**。
  这是升级系统能生效的前提：水枪 `blob_size` 变大后，每发灌进水池的水量真的更多，
  填满同样容积需要的发数自动变少。**不要**改回「一发 = 1 单位」那种跟着水枪走的相对单位 ——
  那样不管怎么升级，水池都要射同样多发才满，升级等于白升。
  （2026-10-11 已经因为这个原因删掉了 `base_size` 这个参数，别再请回来。）

吸水区的 `capacity` 单位是**立方米**：边长 0.05 米的水 = 0.000125 m³，想「200 发填满」就填 0.025。
吸满后继续吸水、水面不再上涨。

### 换水模型 / 加新水样式：用「继承场景」，不要复制

在文件系统里右键 `scenes/水块.tscn` → **新建继承场景（New Inherited Scene）** → 存成
比如 `scenes/水球.tscn`。然后**只动两处**：

1. 换掉 `Visual` 节点下的网格（新模型实例挂到 `Visual` 下面即可，别删 `Visual` 本身）
2. 填 `model_size`；**填 0 就自动按模型包围盒量取**，连这个都不用算

脚本、碰撞层「水」（第 3 层）、`CollisionShape3D`、以及全部行为参数都是继承来的，
一行逻辑都不用碰。最后把 `main.tscn` 的 `水块容器.blob_scene` 指向新场景。

**不要复制 `水块.tscn` 再改** —— 那样上面那些都得自己保证，而且漏掉任何一个
多数不会报错，只会安静地不工作（最典型的是 `visual` 引用断掉，水块合体变大、视觉却不动）。

水种是自动的：取的就是 `blob_scene` 的场景路径，所以换模型之后新旧两种水不会混在一起。

> 如果以后要**两把枪同时射不同样式的水**（而不是换掉全局那一种），才需要把 `blob_scene`
> 从「水块容器」挪到「水枪发射器」上。现在只有一种水，放在容器上是对的。

### `scenes/main.tscn` 现有节点

- `Node3D` —— 场景根
- `Camera3D` —— 主摄像机
- `WorldEnvironment` —— 环境（Environment 子资源）
- `场景` —— `resources/场景.fbx` 实例。内部层级：`GRP_City` / `GRP_Fence` / `GRP_House`（含室内家具 `Interior_*`）/ `GRP_Pool` / `GRP_Props` / `GRP_Vegetation` / `GRP_Yard`，每个 `GRP_` 下是若干 `MeshInstance3D`。
  **要单独操作某栋房子/家具时，用 `$场景/GRP_House/House_Roof` 这样的路径访问，但注意这些是导入资源的内部节点，改它们不会回写到 .fbx——需要改美术时找建模的同学重新导出。**
- `奶蛋` —— `resources/奶蛋/奶蛋.glb` 实例，已挂 `scripts/milkegg.gd`，位置 `(0.99, 0.39, 2.29)`。内部是 `球体` / `球体_001` 两个 `MeshInstance3D`。
- `DirectionalLight3D` —— 已挂 `scripts/sun.gd`，绕 Z 轴在 XY 平面公转模拟昼夜，参数（半径、角速度、初始角度）都在检查器里可调。
- `水块容器` —— 挂 `scripts/水块容器.gd`，`blob_scene` 指向 `scenes/水块.tscn`，`ignore_body` 指向主人公自己（水团飞行打射线时忽略他）。所有水团都是它运行时生成的子节点；初速、重力、合并规则都在这个节点上调。
- `主人公/水枪发射器` —— 挂 `scripts/水枪.gd`，`muzzle` 指向 `主人公/人物/水枪/Muzzle`。只负责朝视线方向吐水，不参与弹道计算；`blob_size` 是全项目唯一定义「一发水初始大小」的地方。
- `主人公/人物/水枪/Muzzle` —— 出膛点 `Marker3D`。**位置是按 水枪.glb 包围盒估的，不是实测，觉得水不是从枪口出来就直接在编辑器里拖它。**
- `场景/吸水区` —— `scenes/吸水区.tscn` 实例，摆在水池里，几何故意和 `场景/PoolExclusion` 对齐（但两者无关：那个是奶蛋禁区，只被 `milkegg_encounter.gd` 当数据读，不做物理检测）。
- `场景/木碗` —— `scenes/木碗.tscn` 实例（`resources/木碗.glb`，缩放 3.965）。**碗本身没有碰撞体**（水才能穿过碗壁进到 `吸水区` 里），
  下面挂着 `吸水区`（装水用，容量 0.025 m³）、`出生点` Marker3D（奶蛋的出生点）和 `OmniLight3D`（挂 `scripts/水量灯.gd`，亮度跟着水量走）。
- `奶神` —— 挂 `scripts/milkegg_encounter.gd`，奶蛋的出场调度与选路。主场景里它被木碗锁着（见上面「水的玩法」的奶蛋那条）。
- `奶神/奶蛋/字幕层` —— `CanvasLayer`，里面一个 `解锁字幕` Label（挂 `scripts/水量字幕.gd`，木碗装满时弹金色字幕）。
  **项目里没有字体文件**，所以它用 `SystemFont` 去系统里找中文字体 —— 换正式字体时把 ttf 丢进 `resources/`，再改 Label 的 `LabelSettings.Font`。
  UI 一律挂在 `CanvasLayer` 下面，不要直接挂在 3D 根节点上；`CanvasLayer` 不受父节点 `visible` 影响，所以挂在会被 `hide()` 的角色下面也不会跟着消失。

---

## Git 约定

- 提交信息用中文，沿用现有风格：`Add: ...` / `Fix: ...` / `feat:...` / `change:...` / `Init:...`
- **不要**在提交信息里添加 `Co-Authored-By` 等署名尾注。
- 要提交的：`.gd`、`.gd.uid`、`.tscn`、`.import`、`project.godot`、`addons/`
- 不提交的：`.godot/`（已在 `.gitignore`）、`*.tmp`
