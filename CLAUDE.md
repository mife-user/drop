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
scripts/milkegg.gd           「奶蛋」角色脚本（挂在 奶蛋 节点）
scripts/sun.gd               太阳昼夜循环（挂在 DirectionalLight3D）
```

### `scenes/main.tscn` 现有节点

- `Node3D` —— 场景根
- `Camera3D` —— 主摄像机
- `WorldEnvironment` —— 环境（Environment 子资源）
- `场景` —— `resources/场景.fbx` 实例。内部层级：`GRP_City` / `GRP_Fence` / `GRP_House`（含室内家具 `Interior_*`）/ `GRP_Pool` / `GRP_Props` / `GRP_Vegetation` / `GRP_Yard`，每个 `GRP_` 下是若干 `MeshInstance3D`。
  **要单独操作某栋房子/家具时，用 `$场景/GRP_House/House_Roof` 这样的路径访问，但注意这些是导入资源的内部节点，改它们不会回写到 .fbx——需要改美术时找建模的同学重新导出。**
- `奶蛋` —— `resources/奶蛋/奶蛋.glb` 实例，已挂 `scripts/milkegg.gd`，位置 `(0.99, 0.39, 2.29)`。内部是 `球体` / `球体_001` 两个 `MeshInstance3D`。
- `DirectionalLight3D` —— 已挂 `scripts/sun.gd`，绕 Z 轴在 XY 平面公转模拟昼夜，参数（半径、角速度、初始角度）都在检查器里可调。

---

## Git 约定

- 提交信息用中文，沿用现有风格：`Add: ...` / `Fix: ...` / `feat:...` / `change:...` / `Init:...`
- **不要**在提交信息里添加 `Co-Authored-By` 等署名尾注。
- 要提交的：`.gd`、`.gd.uid`、`.tscn`、`.import`、`project.godot`、`addons/`
- 不提交的：`.godot/`（已在 `.gitignore`）、`*.tmp`
