# 奶蛋随机活动

启动主场景后等待2–5秒，奶蛋会在摄像机内的安全位置出现，边跳跃边连续随机选路。
活动30秒后开始寻找出口，身体完全走出画面后隐藏，随后等待10秒再随机出现，循环执行。
退出路线较长或需要绕行时，实际离屏时间会晚于第30秒。

场景仅复用一个 `CharacterBody3D` 实体。其隐藏期间同时关闭碰撞，换路时不会重新生成或瞬移。
`CharacterBody3D` 负责跳跃及碰撞，模型独立转向和缩放；默认每次出场有80%的概率持续正面朝向摄像机。

## 检查器参数

主场景的 `MilkeggEncounter` 节点控制出现和选路：

- `Respawn Delay`：完全离屏后等待多久再次出现，默认10秒。
- `Roam Duration`：镜头内随机活动时间，默认30秒。
- `First Delay Min / Max`：第一次出现的等待范围。
- `Max Leg Distance`：单段路程上限，到达后继续随机选路。
- `Face Camera Probability`：正面朝向摄像机的概率。
- `Route Memory`：降低最近若干条路线的重复概率。

子节点“奶蛋”控制移动速度、跳高、落地停顿和弹性效果。
`PoolExclusion/CollisionShape3D` 标记泳池禁区，选路和移动时都会排除该区域及身体安全间距。
没有安全路线时会延后重试，不会强行在泳池或障碍中出现。

`scenes/world_collision.tscn` 是根据当前场景模型烘焙的静态碰撞；修改环境模型或布局后需要同步碰撞。
泳池位置和大小改变时，也需要同步调整禁区节点。
奶蛋模型使用GLB内嵌材质，避免引用仓库中不存在的两个外部材质文件，确保首次克隆后也能正常导入。

## 验证

使用实际安装的 Godot 可执行文件运行下面的命令，`$godotExe` 为该文件的完整路径：

```powershell
& $godotExe --headless --editor --quit --path .
& $godotExe --headless --path . --fixed-fps 60 --script res://tests/milkegg_roaming_test.gd -- 1152 648 81234
& $godotExe --headless --path . --fixed-fps 60 --script res://tests/milkegg_roaming_test.gd -- 960 720 4321
```

每轮测试模拟12分钟，检查连续换路、30秒开始退场、整个身体离屏后隐藏、隐藏后等待10秒、泳池避让、单实体及无瞬移。
测试成功输出 `PASS` 并返回退出码0。
本次本机验证使用 Godot 4.7.2；提交保留组织仓库原有的4.8版本声明。
