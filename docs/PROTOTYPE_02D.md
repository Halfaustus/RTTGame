# Prototype 0.2D：服务器权威攻击移动（自动检查通过，待人工验收）

## 本轮输入规则复核

本轮仅统一输入并执行自动回归，倒车另行实现；当前没有倒车功能，不将其记录为通过检查或人工验收。

左键仅用于单选/框选，不确认目标指令。Q 攻击移动、F 快速移动均由下一次右键确认；无待确认模式时右键为基本移动。Esc 取消待确认模式，右键确认后退出。保留现有 Q/F/S 快捷键。客户端连接与角色检查后调用独立输入处理入口，以便离线检查实际事件分支。

新增 `command_input_test.gd`：实际按键/鼠标事件覆盖左键只选择且保留模式、右键确认、模式退出、后续基本移动、Esc 取消、GUI 焦点、重复按键和旧 A 不激活。自动检查通过，待人工验收；本轮未启动客户端或进行人工测试。

本轮编辑器导入、输入事件检查、0.2A/B/C/D、0.1B/C 纯模拟与 0.1D 回归通过，`git diff --check` 通过。0.1C 曾误用不支持的 `selection` 测试角色，触发入口断言，未连接客户端；已改用 `simulation` 重跑通过。环境证书、日志及编辑器设置权限报错仍存在，无最终脚本或资源错误。

```powershell
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/command_input_test.gd
```

0.2A、0.2B 已由用户确认人工验收通过。0.2C 人工复查合并到本页执行；0.2C、0.2D 尚未人工验收。保留全部既有未提交改动及手动启动/停止脚本删除，不提交或推送。

## 实现

- Q 进入攻击移动，下一次右键地面点击下令并退出。左键保留选择操作。Esc 取消；未进入指令模式时右键执行基本移动。F 与 Q 模式互斥，F 再按取消，F 后右键为快速移动。键盘重复、组合修饰键和 GUI 焦点不触发 Q。
- 复用已有移动 RPC；服务器通过真实发送者验证归属、存活、武器、目标和模式。ATTACK 使用 BASIC 距离代价。未知、外人、无武器及死亡单位逐个过滤，不覆盖其旧命令。
- 移动模拟保存攻击移动标记和交战暂停状态；服务器移动前、移动后复用战斗系统的最近存活敌军选择（射程、墙体视线、同距离 unit_id）。暂停保留目标、路径和路径进度；冷却期间仍停车。失去所有可攻击目标后下一模拟步继续原路线，不追击。
- 本步进入射程后先标记停车，再结算射击；射程判定精度为服务器物理步，最多多走一个物理步距离。不在命令时或每帧重新寻路。
- 所有武器在攻击移动交战时停车。普通/快速移动仍遵循每把武器的移动射击配置。普通/快速移动替换攻击移动；S、死亡、断线清除标记和路线。
- 两客户端复用可靠位置、射击、伤害、死亡同步；交战停车不发送会清除路线的 S 停止消息。实际路线仍仅发给所属玩家。客户端没有交战或移动模拟。
- 默认地图复用已有三个红色静止叛军（X/Z：-3/90、3/90、8/90），与玩家同场景；不新增部署或调整战斗平衡。墙体与方块继续阻挡视线。

## 自动检查记录

Godot 4.7.2：编辑器导入、0.2D 隔离模拟/表现输入检查、0.2A 战斗回归、0.2B 停止回归、0.2C 路面寻路回归、0.1D 导航回归及独立服务器启动检查通过。未启动客户端；双客户端同步、实际按键和下令时卡顿仍需下方人工检查。

0.2D 覆盖：混合选择与归属、无武器保留旧路线、遇敌停车与原路线保留、静止武器开火、墙体遮挡、敌人出射程与死亡后恢复、非法模式/目标、死亡过滤、基本移动替换、重复停止与再次快速移动、Q 重复键/GUI 焦点、F/Q 互斥、暂停位置不清路线和 S 清路线。

环境仍输出根证书、user:// 日志及编辑器设置写入权限错误；没有脚本/资源错误。一次新增表现测试的数组类型错误已修正并重跑通过。

在仓库根目录运行（均不启动客户端）：

```powershell
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --editor --import --quit
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_02d_test.gd
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_02b_test.gd
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_02c_test.gd
```

## 手动启动服务器和两个客户端

PowerShell 直接粘贴以下命令，不创建脚本。先确认 UDP 7777 空闲。服务器启动后日志出现 `Dedicated server started on port 7777.` 再启动客户端。服务端和两个客户端使用同一个项目。

```powershell
$rttServer = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList '--headless --path "C:\Projects\RTTGame\game" --log-file "C:\Projects\RTTGame\server-02d.log" -- --server' -WindowStyle Hidden -PassThru
```

```powershell
$rttClientA = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList '--path "C:\Projects\RTTGame\game" --log-file "C:\Projects\RTTGame\client-A-02d.log"' -WindowStyle Normal -PassThru
$rttClientB = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList '--path "C:\Projects\RTTGame\game" --log-file "C:\Projects\RTTGame\client-B-02d.log"' -WindowStyle Normal -PassThru
```

日志文件仅用于运行，不加入 Git。结束时只关闭这些命令返回的进程：

```powershell
foreach ($rttProcess in @($rttClientA, $rttClientB, $rttServer)) {
    if ($null -ne $rttProcess -and -not $rttProcess.HasExited) { $rttProcess.Kill() }
}
```

## 0.2D 双客户端验收清单

1. 每名玩家有一辆蓝色方形车辆及两名球形步兵（其中一名无武器），三名红色叛军在墙另一侧。双方玩家同队，不互相攻击或控制。
2. 选武装单位，Q 后右键墙外远端地面（建议 X=-3、Z=86，即越过墙及叛军），确认选择不变化，距离路线绕墙；未进入射程/没有视线时继续移动。遇可攻击敌人统一停车，射击线/掉血在两窗口一致。
3. 停车时所属窗口剩余路线保留，另一窗口无此路线。敌人死亡后继续剩余路线；有另一名射程内敌人时继续停车交战。测试新局以免目标已全死。
4. 普通右键替换攻击移动后继续执行普通路线；F 后右键替换为快速路线，普通/快速移动的射击资格不变。S 清路线、原地自动交战、再移动；连按 S 无错误。
5. 混选全部三单位，先右键建立旧路线，再 Q 后右键下令：两名武装单位接受攻击移动，无武器单位继续旧路线。点击其他玩家或叛军不能取得控制。
6. Q 后 Esc 取消；Q 后右键下达攻击移动并退出；Q/F 相互切换；长按 Q/F 不重复切换；界面输入取得焦点时不下令。左键仍可选择，右键指令不改变选择。
7. 用墙/方块遮住敌人时不停车攻击；不为射击主动贴近敌人，不转向追击，不离开剩余路线。死亡清选择及路线，后续同步不复活。

## 合并的 0.2C 人工复查

详见 [0.2C 验收说明](PROTOTYPE_02C.md)。以下全部仍待人工确认：

1. 将车辆移到地图 A，再普通右键 B：尽量直达；F 后右键 B：走稍长的硬化 U 形路。自动预计值为基本 16m / 4.917s，快速 20.615m / 2.577s。
2. A 到 C 的短距离即便快速移动仍直达；步兵 A 到 B 两种命令通常使用同一条最短路线。
3. 同一路面上车辆实际速度不因命令改变；跨路面边界切换速度，步兵速度不变。无额外快速移动加成。
4. 下达快速移动命令时观察此前的短暂停顿是否消失；自动检查只验证寻路实现和代价，不能代替实际帧率体验。
5. 绕障保持间距、多选横排落点、不可达处理、命令替换、S 停止、再次移动及两个窗口位置一致均无回退。
