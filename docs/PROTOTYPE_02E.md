# Prototype 0.2E：服务器权威倒车（自动检查通过，待人工验收）

本轮未进行人工测试，未启动客户端。0.2C、0.2D、0.2E 留到 0.2 收尾统一人工验收；0.2A、0.2B 的既有人工验收记录保留。

后续已核对环境报错，并使用项目内临时目录重跑全部自动检查：逐项原生退出码均为 0。日志与编辑器设置写入错误已消除，根证书读取报错仍存在，记录为不影响本次已执行检查的环境问题。准确命令、路径、退出码与未执行范围见 [环境验证核对](ENVIRONMENT_CHECK_02E.md)。

## 输入与命令

- R 进入倒车模式，下一次右键地面确认后退出；Esc 取消。左键仅单选/框选，不确认指令。
- Q 攻击移动、F 快速移动仍由右键确认，三种模式互斥；无待确认模式时右键基本移动。F 再按取消的既有行为保留，S 仍为停止。没有迁移其他快捷键。
- GUI 焦点、键盘 echo、Ctrl/Alt/Meta 修饰的 R 不激活倒车；失焦或服务器断开取消待确认模式。
- 服务器通过真实发送者验证 ID、归属、生命值、类型、模式、目标和配置。倒车仅接受存活己方装甲车辆，可无武器；混选步兵/非己方/未知/死亡 ID 逐个过滤，忽略者保留旧命令。
- 路径复用 BASIC 距离优先寻路：直达、绕障、横排落点、目标回退和不可达保留旧命令均沿用。新基本/快速/攻击移动替换倒车；S、死亡和断线清命令。
- 战斗代码不变；倒车及转向期间仍算移动，武器按 can_fire_while_moving 决定是否能射击，不自动追击。

## 朝向与速度

单位权威状态新增 yaw，局部 -Z 为车头、+Z 为车尾。倒车起步和路径折点先以配置角速度原地转向，尾部对齐下一段后沿既有路径平移；不横向滑行、不离开路线。到达折点的本步不继续转向，下步再转，以保证单步位置变化与同步朝向一致。每个折点最多损失一个物理步的剩余时间。

车辆资源临时参数：前进硬化/非硬化仍为 **8/3 m/s**；倒车硬化/非硬化为 **4/1.5 m/s**；转向 **180°/s**。倒车实际速度按当前位置路面分段积分，跨边界切换。倒车寻路不按倒车时间优化。非正数、NaN、无穷倒车速度或转速会拒绝倒车请求。

客户端只应用服务器 yaw，位置与朝向通过相同可靠有序通道依次广播给全部客户端；停止也补发最终朝向，死亡后忽略迟到朝向。晚加入快照包含当前 yaw，不恢复初始方向。没有客户端模拟。

车体新增黄色车头标记，车体尺寸 0.6×0.5×0.8m，使任意旋转的水平角点仍落在原 1m 导航占地内；导航间距不改。只旋转车体/标记，血条与选择显示保持原方向。

已知限制：本轮无连续弧线、最小转弯半径或动态避让；普通前进车体立即对齐路段，不增加转向等待或改变前进速度。客户端朝向直接显示 0.05s 周期的服务器值，尚未加入视觉插值，实际转向观感及双客户端同步待人工确认。

## 修改范围

- 单位：`unit_definition.gd`、`unit_state.gd`、`unit.gd`、`unit_mobile.tres`。
- 移动/联网/输入：`movement_simulation.gd`、`network_manager.gd`、`game_world.gd`。
- 检查：新增 `prototype_02e_test.gd` 与 UID；扩展 `command_input_test.gd`；`prototype_02a_test.gd` 在计时器结束后等待处理帧，避免 deferred queue_free 尚未完成时误报射击线未消失。
- 文档：本页和 HANDOFF.md。保留全部既有未提交修改和两份手动脚本删除；没有提交、推送或创建启动脚本。

## 自动检查

Godot 4.7.2 编辑器导入、0.2E 倒车隔离检查、输入事件检查、0.2A/B/C/D、0.1B/C 纯模拟、0.1D 导航回归及独立服务器启动均通过，`git diff --check` 通过。

0.2E 覆盖：两种倒车速度与边界、原地转向限速、车尾对齐每步平移、绕障间距及到达、基本路线一致、多选落点/归属/存活/类型过滤、步兵保留旧命令、无效配置/目标、不可达保留旧路径、新命令替换、停止及最终 yaw、移动射击资格、当前朝向快照/广播数据、车头表现、死亡后迟到朝向。

输入检查覆盖 Q/F/R 的左键仅选择、右键确认、确认退出与后续基本移动、Esc 取消、重复键与 GUI 焦点，R 与现有模式替换。

初轮曾发现同一步越过折点再转向导致净位移与最终 yaw 不一致，以及测试中未使用类型化数组，均已修正重跑通过。0.2A 射击线清理检查的延迟释放时序已修正重跑通过。环境仍有根证书、user:// 日志及编辑器设置写入权限报错；最终没有脚本/资源错误。

在 `C:\Projects\RTTGame` 的 PowerShell 运行，均不连接客户端：

```powershell
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --editor --import --quit
$rttTests = @('prototype_02e_test.gd', 'command_input_test.gd', 'prototype_02a_test.gd', 'prototype_02b_test.gd', 'prototype_02c_test.gd', 'prototype_02d_test.gd', 'prototype_01d_test.gd')
foreach ($rttTest in $rttTests) {
    & 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script ('res://tests/' + $rttTest)
    if ($LASTEXITCODE -ne 0) { throw ('检查失败：' + $rttTest) }
}
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_01d_test.gd -- --server-smoke
git diff --check
```

## 0.2 收尾时手动启动（本轮未执行）

先确保 UDP 7777 空闲。在 PowerShell 启动服务器，待输出 `Dedicated server started on port 7777.` 再启动两个客户端：

```powershell
$rttServer = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList '--headless --path "C:\Projects\RTTGame\game" -- --server' -WindowStyle Hidden -PassThru
```

```powershell
$rttClientA = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList '--path "C:\Projects\RTTGame\game"' -WindowStyle Normal -PassThru
$rttClientB = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList '--path "C:\Projects\RTTGame\game"' -WindowStyle Normal -PassThru
```

收尾时只关闭本次返回的进程：

```powershell
foreach ($rttProcess in @($rttClientA, $rttClientB, $rttServer)) {
    if ($null -ne $rttProcess -and -not $rttProcess.HasExited) { $rttProcess.Kill() }
}
```

## 待人工验收（本轮全部未执行）

1. R 后左键仍选择，不下令；R 后右键倒车并退出；Esc 取消；Q/F/R 切换互斥，后续普通右键基本移动，GUI 与长按无干扰。
2. 车辆有黄色车头。向车后下达倒车，车尾朝前进方向；改变路线/绕墙时先平滑转向再倒车，不横滑或穿墙。两窗口位置和朝向一致。
3. 跨硬化/非硬化路面，倒车按 4/1.5m/s 切换；原有基本/快速前进 8/3m/s 不变。
4. 混选车辆与步兵，先建立旧路线再 R 下令：只有己方车辆倒车，步兵继续旧路线；多辆己方车辆横排落点正常，非己方不可控制。
5. 新基本/快速/攻击移动替换倒车；S 立即停止并清所属路线，重复 S、再次倒车正常；停止在转向中时两窗口方向一致。
6. 倒车武器移动射击资格不变；不追击、不动态避让；晚加入得到存活单位当前生命、位置和朝向，死亡单位不复活。
7. 合并执行 [0.2D 与 0.2C 清单](PROTOTYPE_02D.md)，包括道路代价选择、下令卡顿复查、遇敌停车与原路线恢复、路径隐私和死亡清理。
