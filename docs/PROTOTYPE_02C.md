# Prototype 0.2C：路面速度与快速移动路线规划

0.2B 已由用户确认人工验收通过。0.2C 自动检查通过，实际双客户端人工验收待进行。保留所有原有未提交改动及手动脚本删除，没有提交、推送或创建启动脚本。

## 规则与实现

- `UnitDefinition` 新增步兵/装甲车辆类型和硬化/非硬化速度。步兵始终使用非硬化速度，保证两路面相同。正式服务器单位均经过定义配置；旧隔离测试直接构造的未配置 `UnitState` 保留 `MovementConfig.speed` 回退。
- 右键基本移动（模式 0），按 F 进入快速移动模式（模式 1），再次 F 取消；右键进入队列时消费模式并立即恢复基本移动。显示简短模式提示，失焦或断线取消；忽略键盘 echo、修饰键和 GUI 焦点。Ctrl+右键不再触发快速移动。沿用原 `_unhandled_input` 与动作队列，S 停止保持原规则。
- 移动请求仅增加模式整数，不接收客户端路线、速度或归属声明。服务器检查目标、模式、真实发送者归属和定义速度合法性，按每名单位自身速度规划。
- 原有导航网格、静态障碍膨胀、最近可达终点与横排槽位继续使用。服务器初始化时将网格合法八邻接连接建立为 AStar2D 静态图，连接均经过连续净空和防切角检查。每次查询将全部可见起终点连接为两个临时节点，仅执行一次搜索，完成后移除临时节点。自定义 `_compute_cost` / `_estimate_cost` 保留距离或时间代价及最大速度下界；静态边代价按速度配置缓存，地图重建或配置切换时失效。没有速度加成。
- 共享 `TerrainSurface` 将线段在每个道路矩形入口/出口处分段，按覆盖区域的并集识别硬化路面，计算 `sum(length / surface_speed)`。网格代价、平滑代价和实际移动共用同一份路面数据。
- 基本移动无遮挡时直接返回直线；有障碍时比较可见端点连接的网格路径，按距离选择并去除多余折点。快速车辆比较时间最优网格候选与直达候选，不要求经过道路。步兵或两路面等速车辆复用距离规划。
- 平滑每条捷径必须通过完整障碍净空检查。快速路径仅接受预计时间不高于原子路径的捷径，允许在硬化路面的宽度内切角，但不能为了直线抹掉道路收益。
- 实际推进消耗剩余时间，每段按道路边界切分，先走完旧路面部分再以新路面速度继续；一个大 tick 可跨越多个边界和路线折点。命令模式不参与实际速度计算。
- 原有多选 ID 排序与横排落点、目标回退、不可达保留旧路径、新命令替换、S 停止、死亡清理、位置同步和仅所有者收到实际路径均保留。生成/晚加入快照新增 `unit_type`，客户端只切换轮廓，不计算权威速度。
- 自动交战代码没有改变：不追击、不保持位置、不驱动移动。快速移动仍按原武器 `can_fire_while_moving` 与冷却规则射击。

接口依据：[Godot AStar2D 自定义代价与图连接接口](https://docs.godotengine.org/en/stable/classes/class_astar2d.html)。本项目通过 Godot 4.7.2 实际导入和测试验证这些接口可用。

## 临时测试参数与地图

| 单位 | 硬化速度 | 非硬化速度 | 轮廓 / 武器 |
| --- | --- | --- | --- |
| 每玩家首名装甲车辆 | 8 m/s | 3 m/s | 平矮方块 / 原移动射击武器 |
| 每玩家第二名步兵 | 4 m/s | 4 m/s | 球形 / 原停步射击武器 |
| 每玩家第三名步兵 | 4 m/s | 4 m/s | 球形 / 无武器 |

两队颜色、生命值、武器射程/伤害/间隔和叛军生成机制不变。单位占地仍按原 1 m 导航宽度和 0.05 m 障碍余量处理；不同轮廓都在该宽度以内。

地图保留原墙和方块，在安全测试区新增灰色 U 形道路：左腿 X=[-9,-7], Z=[101,107]；横段 X=[-9,9], Z=[105,107]；右腿 X=[7,9], Z=[101,107]。道路仅显示地面覆盖，不增加阻挡射击或移动的碰撞体。其余地图为非硬化路面。

标记 A=(-8,102)、B=(8,102)、C=(-4,102)，均为世界 X/Z，地图生成单位高度仍为 0.5 m。A-B 中间是非硬化直达路线；A-C 是用于拒绝过长道路绕行的短途。默认出生位置不变，无正式部署系统。

## 修改文件

- 单位：`game/scripts/units/unit_definition.gd`、`unit_state.gd`、`unit.gd`、`game/data/unit_mobile.tres`。
- 路面/地图：`game/scripts/maps/prototype_map_definition.gd`、`test_map_geometry.gd`、`game/data/prototype_map.tres`；新增 `game/scripts/movement/terrain_surface.gd`。
- 导航/移动：`game/scripts/movement/static_navigation_grid.gd`、`movement_simulation.gd`；新增 `route_cost_grid.gd`。
- 输入/同步：`game/scripts/core/game_world.gd`、`game/scripts/networking/network_manager.gd`。
- 测试：新增 `game/tests/prototype_02c_test.gd`；更新 `prototype_01d_test.gd` 的地图节点计数及服务器只拥有 owner 0 叛军的启动断言。新增脚本对应 `.gd.uid`。
- 文档：更新 `HANDOFF.md`、`PROTOTYPE_02B.md`，新增本文。

## 自动验证

均通过，未启动任何客户端：

```powershell
Set-Location C:\Projects\RTTGame
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --editor --import --quit
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02c_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02a_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02b_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd -- --server-smoke
git diff --check
```

0.2C 覆盖车辆基本直达、快速道路收益、过长 U 形道路拒绝、默认 A-C 直达、步兵路线一致、同路面不同模式同速度、双向边界与重叠道路、边界起步、大/小 tick 一致、实际到达时间与规划时间一致、两模式障碍净空、非法模式/归属过滤、异类多选横排、停止和重新移动、不可达保留旧路径、F 切换/右键消费/echo/GUI 过滤、模式提示、失焦取消、缓存速度配置切换与地图重建失效、临时节点不泄漏、类型轮廓与快照、所有者实际路线显示和停止清理。

实测 A-B：基本 **16.000 m / 4.917 s**，快速 **20.615 m / 2.577 s**。快速路径平滑后保留道路收益；实际以 0.05 s tick 到达的时间与估算误差不超过一个 tick。

用户反馈下达快速移动命令时短暂停顿。修正前/后对同组 23 次寻路使用 Godot 脚本 Profiler：`find_path` 累计 **3.049186 → 0.205708 s**，`_compute_cost` 调用 **567670 → 33930**，寻路耗时减少约 93%。初始化时新增静态图构建成本，因此不能将此数字解释为整个测试进程运行时间减少 93%；服务器监听前建图，命令不再重复建图。该性能对比采集后新增了缓存失效测试，最新测试调用数量不再等于 23。

性能检查命令（只运行离线测试，不启动客户端）：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path "C:\Projects\RTTGame\game" --profiling --debug --script res://tests/prototype_02c_test.gd
```

Profiler 输出还包含旧代码的整数除法、变量遮蔽及 Variant 类型警告；本轮没有无关清理。实际 F 输入和下令停顿改善尚待双客户端复核。

编辑器导入、所有离线测试与服务器独立启动最终无脚本/资源错误。首次旧服务器 smoke 断言“无任何单位”因叛军生成失败，修正为“叛军 owner 0、无玩家单位”后通过。沙箱仍有根证书读取、user:// 日志写入和编辑器设置保存权限错误；这些环境错误不能描述为完全无 ERROR。

## 一键启动命令

在 PowerShell 一次粘贴执行下面整个代码块。不创建脚本文件；检查端口、等待服务器日志就绪后打开两个交互客户端。日志使用独立 TEMP 目录。Godot.exe 和 Godot_console.exe 的路径已在本机核实存在。本轮只检查命令语法，没有执行客户端启动。

```powershell
$ErrorActionPreference = 'Stop'
if (Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue) { throw 'UDP 7777 已被占用，请先关闭本轮旧服务器。' }
$rttLogs = Join-Path $env:TEMP ('RTTGame-02C-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($rttLogs) | Out-Null
$rttArgs = '--path "C:\Projects\RTTGame\game" --log-file "{0}"'
$rttServerLog = Join-Path $rttLogs 'server.log'
$rttServer = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList (($rttArgs -f $rttServerLog) + ' --headless -- --server') -WindowStyle Hidden -PassThru
$rttDeadline = [DateTime]::UtcNow.AddSeconds(15)
$rttReady = $false
while ([DateTime]::UtcNow -lt $rttDeadline) {
    if ($rttServer.HasExited) { throw "服务器启动失败，日志：$rttServerLog" }
    if ((Test-Path -LiteralPath $rttServerLog) -and (Select-String -LiteralPath $rttServerLog -SimpleMatch 'Dedicated server started on port 7777.' -Quiet)) { $rttReady = $true; break }
    Start-Sleep -Milliseconds 100
}
if (-not $rttReady) { if (-not $rttServer.HasExited) { $rttServer.Kill() }; throw "服务器未就绪，日志：$rttServerLog" }
$rttClientA = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList ($rttArgs -f (Join-Path $rttLogs 'client-A.log')) -WindowStyle Normal -PassThru
$rttClientB = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList ($rttArgs -f (Join-Path $rttLogs 'client-B.log')) -WindowStyle Normal -PassThru
Write-Host "日志：$rttLogs；服务器 PID：$($rttServer.Id)；客户端 PID：$($rttClientA.Id), $($rttClientB.Id)"
```

验收结束后，在同一终端只关闭上述进程对象：

```powershell
foreach ($rttProcess in @($rttClientA, $rttClientB, $rttServer)) {
    if ($null -ne $rttProcess -and -not $rttProcess.HasExited) { $rttProcess.Kill() }
}
```

不按进程名批量终止 Godot；之前删除的 start-local-test.ps1 / stop-local-test.ps1 保持删除。

## 待人工验收

1. 确认两端初始相同单位、阵营、生命值和形状：每玩家一辆平矮蓝色车辆、两名球形蓝色步兵；叛军红色。灰色道路与 A/B/C 标记可辨认。
2. 用基本移动将自己的车辆停到 A 附近。右键 B：路线沿 A-B 非硬化直达，不绕 U 形路；实际经过硬化与非硬化区域时速度变化。只有所属客户端显示虚线。
3. 回到 A，按 F 后右键 B：虚线沿 U 形硬化路绕行，距离稍长但抵达更快。道路宽度内切角允许；不能穿墙或离开路面导致收益丢失。重复操作时从同一位置开始，鼠标落点稍有误差，不要求手动秒表达到离线的精确数值。确认下令瞬间停顿改善。
4. 回到 A，按 F 后右键 C：短途仍走直达，不能为了“快速”强制绕 U 形路。离线长 U 地图也已覆盖长绕行拒绝。
5. 步兵从 A 到 B，分别右键和按 F 后右键：两次均尽量直线，灰色道路上不额外加速。车辆同路面上的两种命令也不加成；用道路左腿和旁边非硬化地面各比较一次。
6. 混合选择车辆和步兵移动到同一落点：单位各按自己的速度与代价走，终点保留 ID 稳定横排；途中改用另一模式的新目标，应替换旧路径。绕墙、障碍内终点回退、地图外目标拒绝仍正常。
7. 移动途中 S 停止：两端停在相同位置，所有者路线清除；再右键或按 F 后右键可以继续移动。未选中单位不受影响。
8. A 操作时 B 看见位置变化和交战效果，但看不见 A 路线；B 操作时反向核对。普通和快速移动中都继续遵守武器移动射击资格；敌人不追击，单位不自动走向敌人。
9. 可关闭一个客户端后重新打开，核对晚加入单位类型、位置和当前血量；死亡单位不重生。检查三份日志没有脚本/RPC 错误。
10. 按 F 显示快速模式提示，再按 F 取消；按住 F 不重复切换。F 后右键提交一次快速命令，提示立即消失，下一次右键恢复基本移动；空选择右键也退出。Ctrl+右键仍为基本移动。切换窗口或断线后模式复位。

## 限制

寻路仍为 0.5 m、八邻接静态网格及可见端点连接，再进行连续净空/时间检查和平滑，是离散导航上的距离/时间最优候选比较，并非连续平面任意曲线的解析全局最优求解。道路按单位中心的 X/Z 判断；高度不改变路面类型。没有动态单位避让或道路中心线约束。实际双客户端 0.2C 同步及 Linux 服务器尚未验证；规模扩大前应先用 Profiler 测量命令规划成本。
