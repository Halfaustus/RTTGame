# Prototype 0.2F：整体验证与收尾

当前统一验收追加 [0.2H 镜头与输入清单](PROTOTYPE_02H.md) 及 [0.2G 编队朝向清单](PROTOTYPE_02G.md)。E 已替代 S 停止，WASD 控制镜头，Q 保持攻击；右键释放确认或拖动指定编队朝向。下面历史验证说明保持原状，当前操作表已更新。0.2H 自动检查通过，待人工验收，本轮未执行 ENet 或窗口操作。

状态：**自动检查及真实 ENet 端到端检查通过，待统一人工验收**。没有自动提交或推送，未迁移键位。0.2A、0.2B 的既有人工验收通过记录保留；0.2C/D/E/F 未记录为人工通过。

当前人工验收入口已实际保存为 `scripts/start-local-test.ps1`、`scripts/stop-local-test.ps1`。默认 7777 的生产服务器＋两个可见客户端及停止已通过脚本验证，不等于游戏人工通过。请使用 [脚本验收清单和准确命令](LOCAL_TEST_ACCEPTANCE.md)；下方 0.2F 当时的端口占用/脚本删除记录是历史证据，不代表当前阻塞或文件缺失。

## 本轮发现和修复

真实服务器＋两个客户端测试确认：观察客户端离线期间敌人死亡、其他单位改变位置后，同一客户端重新连接仍保留已死亡敌人以及离线前的位置。重复 unit_id 的生成显示会被忽略，而死亡快照不会发送已死亡 ID。

仅修复 `game_world.gd` 的会话显示清理：断开服务器及连接开始时清空旧选择、路线、视觉单位和死亡记录，再用服务器当前存活快照重建。旧节点释放前解除 tree_exiting 回调，避免延迟释放误删同 ID 的新显示。新增离线回归检查该边界，并通过相同真实重连场景复核。

新增 `game/tests/prototype_02f_e2e.gd`（及 UID），扩展 `command_input_test.gd`，更新本页、HANDOFF；没有改战斗、速度、敌人生成或玩家身份规则。仍无玩家账号/重连接管机制：每次新连接生成一组新玩家单位，旧玩家单位保留并停止其移动。这是既有边界，不等于重复生成敌人。

## 实际验证证据

端到端是独立进程中的生产 NetworkManager、移动/战斗模拟及真实 ENet RPC；客户端加载生产 GameWorld 和单位场景，用程序构造键盘/右键事件调用生产输入入口。服务器仅正常 start_server；测试读取服务器及客户端状态进行断言，没有用文件同步取代网络，不修改平衡数据或直接写游戏状态。

运行模式是 headless，验证了数据、RPC 和显示节点状态；没有验证真实桌面鼠标、GUI 消费事件、图像渲染、转向观感或帧率体验。

最终端到端证据目录：`C:\Projects\RTTGame\tmp\02f-e2e-194108`。持久摘要如下，临时目录即使日后清理，本页仍保留结果与命令：

| 检查 | 实际结果 |
| --- | --- |
| 两玩家加入 | 服务器仍仅三个初始敌人 ID 1/2/3，owner 0；玩家同队 |
| 基本移动 | A 点到达、武装多选横排落点通过 |
| 快速移动 | F＋右键收到道路绕行路线，完成位置/朝向同步 |
| 倒车与停止 | R＋右键前进、S 清除倒车和所属路线、两个客户端位置/最终 yaw 与服务器一致 |
| 组合替换 | 快速替换倒车、攻击替换快速、倒车替换攻击、基本替换倒车、倒车后停止、停止后重新移动通过 |
| 命令权限 | 真实客户端发非己方移动/停止被拒绝；NaN 目标及非法模式被拒绝，不影响其他玩家单位 |
| 路径隐私 | 所属客户端收到真实路线；另一个客户端未收到这些目标 RPC，也没有对应路线节点 |
| 攻击移动与无武器过滤 | 武装单位停车交战、剩余路线保留；无武器单位保持基本移动旧命令 |
| 受伤与射击 | 两客户端收到射击，敌人当前生命值一致 |
| 双客户端死亡同步 | 两客户端在线时敌人 3 死亡，服务器及两个客户端同时不再存在该 ID |
| 重连 | 同一观察客户端关闭 ENet 后重新连接，当前存活 ID 集合、位置、生命值及 yaw 与服务器一致；离线期间死亡的敌人不再显示 |
| 新晚加入进程 | 主测试两客户端结束后启动全新 late 客户端，存活 ID、当前位置/生命/yaw 一致；已死亡敌人没有恢复 |
| 敌人无重复生成 | 初始加入、第二加入、重连、新晚加入均没有新敌人 ID 或死亡敌人复活 |

自然结束的 driver、observer、late **原生退出码均为 0**，打印各自 `PASS E2E ... complete`；夹具编排器退出码 **0**。服务器是常驻进程，检查后由编排器对本次 Process 对象调用 Kill，退出码 **-1 / TerminatedByRunner=true**；不将该值表述为服务器自然退出成功。全部本轮进程结束后已有 PID 40616 仍存在，未被清理命令关闭。

最终服务器与 late 客户端均无敌人 ID 1/2/3，也无死亡玩家单位 ID 5；一致的存活集合为 4、6、7、8、9、10、11、12、13、14、15。单位 4 在两侧均为 HP=80，位置约 (5.703154,0.5,94.868721)，yaw 约 -0.997850；单位 12 两侧 HP=50，说明晚加入没有恢复旧生命值。

修复前的观察证据曾出现：服务器 unit 4 已在约 (-10,0.5,105)，观察客户端仍在约 (-9.687047,0.5,94.377930)，并残留死亡敌人 1。最终精确存活 ID/当前位置/生命/yaw 断言通过，生命比较使用相等判断，不用伤害容差放宽结果。

完整过程参数和退出码位于 `process-results.json`，逐阶段 PASS 在 driver/observer/late.log；server.log 含命令拒绝、玩家连接/断开及生成日志。第一次游戏重连失败证据在 `tmp/02f-e2e-193326/observer.log`（原生退出码 1），最终复核在上述最终目录。

本轮早期夹具有类型化数组遗漏、离线 peer ID 查询、跨进程 JSON 读写竞态，以及先停止尚未进入战斗的车辆导致敌人无法按预期死亡；均为夹具问题，已经修正。文件仅作观察与阶段协调，采用临时文件替换及读缓存；功能命令和复制仍走真实 RPC。不会把这些失败归为环境问题或掩盖游戏重连失败。

### 自动回归

`tmp/02f-regression/results.json` 记录 input、0.2A/B/C/D/E、0.1D 每条原生退出码 0、PASS、无 SCRIPT ERROR/FAIL。编辑器导入、0.1B/C 的 simulation 角色和 `git diff --check` 也退出码 0。原 0.2E 环境核对证据保留，见 [ENVIRONMENT_CHECK_02E.md](ENVIRONMENT_CHECK_02E.md)。

APPDATA、LOCALAPPDATA、日志全部临时放项目内 tmp；不修改系统权限或持久变量。根证书读取报错仍存在，不影响本次离线/ENet 验证；没有默认日志或编辑器设置保存错误。

### 默认启动失败及未执行项目

默认生产启动命令 `--headless --path C:\Projects\RTTGame\game -- --server` 在本轮退出码 **1**：UDP **7777 被已有 Godot PID 40616 占用**，日志包含 `Couldn't create an ENet host`、`Failed to start server on port 7777. Error: 20`。证据为 `tmp/02f-launch-193855/server.log` 与 results.json。PID 40616 的启动时间为 2026-10-03 18:45:09，本轮没有关闭它。

因此默认 7777 的新生产服务器＋两个客户端启动 **当前被端口占用阻塞，未完成**；不能将 18888 测试误记为默认端口启动通过。18888 测试角色启动与只停止本次进程已实际通过。窗口客户端的人工启动/显示和停止操作未执行。

另在 `tmp/02f-stop-check` 独立验证了 18888 服务器重新启动、按返回 Process 对象停止、再次执行相同停止代码：两次均 PASS，调用进程退出码 0；服务器主动终止为 -1。本轮结束时仍存在的 PID 40616/42000 均在 18:45:09 启动，早于本轮，未关闭。

未执行：统一人工清单、真实桌面 GUI/键盘/鼠标交互、可见射击线及血条观感、连续移动显示/转向抖动与下令卡顿体验、丢包/高延迟/广域网、Linux 构建和 HTTPS/TLS。没有使用模拟检查替代这些项。

## 可复现的端到端启动命令（18888）

以下是自动检查角色，不是人工游戏入口。在仓库 PowerShell 中创建全新证据目录，显式写项目内日志并保存启动返回的 Process 对象。端口 18888 必须空闲；绑定失败时检查日志，不关闭无关进程。

```powershell
$rttEvidence = 'C:\Projects\RTTGame\tmp\02f-e2e-' + [Guid]::NewGuid().ToString('N')
[IO.Directory]::CreateDirectory($rttEvidence) | Out-Null
$rttSavedAppData = $env:APPDATA
$rttSavedLocal = $env:LOCALAPPDATA
$env:APPDATA = Join-Path $rttEvidence 'appdata'
$env:LOCALAPPDATA = Join-Path $rttEvidence 'localappdata'
$rttTestArgs = '--headless --path "C:\Projects\RTTGame\game" --log-file "{0}\{1}.log" --script res://tests/prototype_02f_e2e.gd -- --test-role={1} --test-port=18888 --evidence="{0}"'
$rttServer = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList ($rttTestArgs -f $rttEvidence, 'server') -WindowStyle Hidden -PassThru
```

server.log 出现 `Dedicated server started on port 18888.` 后运行：

```powershell
$rttDriver = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList ($rttTestArgs -f $rttEvidence, 'driver') -WindowStyle Hidden -PassThru
```

driver.log 出现 `live spawn snapshots` 后运行：

```powershell
$rttObserver = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList ($rttTestArgs -f $rttEvidence, 'observer') -WindowStyle Hidden -PassThru
```

等待 driver、observer 自然结束且日志分别包含 complete，无 SCRIPT ERROR/FAIL，并检查 `$rttDriver.ExitCode`、`$rttObserver.ExitCode` 均 0，然后运行：

```powershell
$rttLate = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList ($rttTestArgs -f $rttEvidence, 'late') -WindowStyle Hidden -PassThru
```

late 自然结束且打印 complete、ExitCode=0 后结束服务器。中途失败也执行下述清理；这些是直接命令，没有恢复已删除的手动脚本。

```powershell
foreach ($rttProcess in @($rttLate, $rttObserver, $rttDriver, $rttServer)) {
    if ($null -ne $rttProcess -and -not $rttProcess.HasExited) {
        $rttProcess.Kill()
        if (-not $rttProcess.WaitForExit(5000)) { throw '本轮进程未停止' }
    }
}
$env:APPDATA = $rttSavedAppData
$env:LOCALAPPDATA = $rttSavedLocal
```

上述 Process 对象的重复清理不报错，不使用全局进程名杀进程。自动检查时实际采用相同参数与流程的临时编排器，置于被忽略的 tmp，不加入仓库。

## 人工游戏启动（7777 空闲后）

当前已有 7777 会话，先由操作者正常结束自己已有的测试会话，再启动；不按任意查到的 PID 直接杀进程。本轮没有验证可见窗口启动。

```powershell
$rttManualLogs = 'C:\Projects\RTTGame\tmp\02-manual-' + [Guid]::NewGuid().ToString('N')
[IO.Directory]::CreateDirectory($rttManualLogs) | Out-Null
$rttServer = Start-Process 'C:\Dev\Godot\Godot_console.exe' -ArgumentList "--headless --path C:\Projects\RTTGame\game --log-file $rttManualLogs\server.log -- --server" -WindowStyle Hidden -PassThru
```

确认 server.log 出现 `Dedicated server started on port 7777.`，服务器仍运行后启动两窗口：

```powershell
$rttClientA = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList "--path C:\Projects\RTTGame\game --log-file $rttManualLogs\client-A.log" -WindowStyle Normal -PassThru
$rttClientB = Start-Process 'C:\Dev\Godot\Godot.exe' -ArgumentList "--path C:\Projects\RTTGame\game --log-file $rttManualLogs\client-B.log" -WindowStyle Normal -PassThru
```

结束时只清理这三个返回对象，可重复执行：

```powershell
foreach ($rttProcess in @($rttClientA, $rttClientB, $rttServer)) {
    if ($null -ne $rttProcess -and -not $rttProcess.HasExited) {
        $rttProcess.Kill()
        $rttProcess.WaitForExit(5000) | Out-Null
    }
}
```

## 统一人工验收清单（全部待执行）

实际键位如下，不将 A 或 Ctrl＋右键记为攻击/快速移动快捷键：

| 输入 | 当前作用 |
| --- | --- |
| 左键点击／拖动 | 单选／框选己方单位；不确认目标指令 |
| 右键地面 | 释放确认当前 Q/F/R 指令；无待确认模式时基本移动；拖动指定编队中心与朝向 |
| WASD | 随镜头水平朝向平移；S 不再停止单位，A 不进入攻击模式 |
| 按住中键或 Alt 移动鼠标 | 水平旋转及俯仰；期间屏蔽选择与指令确认 |
| 滚轮上／下 | 拉近／拉远，保持现有透视投影 |
| Q | 进入一次性攻击移动模式 |
| F | 进入快速移动模式；再次 F 取消 |
| R | 进入一次性倒车模式 |
| Esc | 取消待确认模式 |
| E | 对选中己方单位立即停止，不需要目标点击 |
| 失焦／断开连接 | 取消模式；断开清当前会话显示 |

两客户端共用服务器，蓝色玩家同队，红色敌人敌队。玩家每组方形车辆一辆、球形步兵两名，其中一名无武器；车头为黄色标记。地图 A=(-8,102)、B=(8,102)、C=(-4,102)，墙体在两队之间。

| 项目 | 操作步骤 | 通过标准 |
| --- | --- | --- |
| 连接与敌人 | 先开服务器再依次两窗口；后续关闭/重开 B | 初始三名红色敌人，第二玩家加入或重连不新增敌人；双方玩家不互相攻击 |
| 选择与确认 | 左键选车辆，Q/F/R 后再左键或框选，再右键地面；试 Esc | 左键只改变选择，模式保留；右键执行待确认指令一次并退出，后续右键基本移动；Esc 不移动 |
| 重复键与 GUI | 长按 Q/F/R/E，切窗口失焦；界面可取得焦点时尝试按键 | 不因键盘 echo 重复下令/切换；GUI 消费输入时不发游戏命令；失焦取消模式及镜头按键/捕获 |
| 基本移动 | 车辆放 A，普通右键 B；再点墙另一侧及方块内 | 无障碍尽量直线，遇障保持间距绕行；不可达/回退不会穿墙或丢有效旧命令 |
| 多选 | 框选三个己方单位到地面目标，随后右键拖动朝向并重新下令 | 沿最终朝向左右轴横排；有效单位逐个处理；新命令替换旧路线和最终转向，位置/朝向两窗口一致 |
| 快速道路 | 车辆 A 后 F＋右键 B，再 A→C；步兵重复 A→B | 车辆 A→B 能利用稍长但更快的硬化路；A→C 仍直达；步兵两种模式通常同最短路线 |
| 实际速度 | 同一路面比较基本/F 前进，跨道路边界 | 车辆前进硬化/非硬化 8/3m/s，不因命令加速；步兵同速；边界切换合理 |
| 下令性能 | 连续多选 F＋右键及远目标绕障 | 无明显下令短暂停顿；本项必须实际观察，不以算法计时替代 |
| 倒车 | R＋右键车后，再向侧面或绕墙下倒车指令 | 车尾朝行进方向；先平滑转向再倒车，不横滑、穿墙；车頭标记明确；两窗口方向一致 |
| 倒车速度与过滤 | 跨道路，混选车辆与有旧路线步兵后 R | 倒车硬化/非硬化 4/1.5m/s；步兵保留旧命令；他人车辆不能控制 |
| 组合替换 | 移动中 F→Q→R→普通右键；E 后再次移动 | 新有效命令替换旧命令；无残留暂停/倒车状态；E 当前服务器位置停止并清所属路线和最终转向，重复 E 正常 |
| 攻击移动 | 两武装单位先移墙左侧约(-8,100)，Q＋右键(-10,88) | 使用基本距离路线；射程/视线允许时停下打最近敌人，路径保留；不追击、不离开指定路线 |
| 目标丢失/死亡 | 交战中等敌人死亡，或利用墙遮挡；再普通移动 | 无可攻击目标时继续剩余路线；有其他近敌则继续交战；新基本命令可离开原交战暂停 |
| 混合攻击 | 无武器步兵先有基本路线，再混选 Q 下令 | 武装单位接受攻击移动，无武器继续旧路线 |
| 战斗与 LOS | 墙/方块两侧移动，观察血条和射击；E 原地交战 | 障碍挡射线；两窗口生命/射击一致，无实体弹丸；普通/快速/倒车遵守每把武器移动射击资格，攻击移动遇敌停车 |
| 死亡清理 | 选中交战单位，等待其死亡 | 两窗口移除单位；选择/路径清理，后续同步不复活 |
| 路线隐私 | 客户端 A 给己方下令，观察 B，再反向测试 | 所属窗口有实际折线路线，另一个窗口无该路线；交战暂停保留，E 清除 |
| 新晚加入 | 敌人受伤/死亡、车辆移动及倒车转向后，关闭 B，再重开 | 当前存活敌人生命值不恢复，死亡不复活；位置/朝向为当前值，敌人数不增加 |
| 同进程重连 | 当前产品没有 UI 重连入口，已用真实 ENet 自动验证；未来有入口再人工操作 | 会话显示重建，无离线期间死亡残留/旧位置；不要求重新取得旧玩家单位控制权 |
| 结束 | 使用本页保存的 Process 对象停止本次会话，再重复停止 | 本次三个进程结束，不影响无关 Godot；端口释放后可重新启动 |

任何一项实际失败应记录服务器/两个客户端日志与步骤，不将 headless PASS 当作可见窗口人工通过。

## Git 排除与交接

既有 `.gitignore` 已排除 `tmp/`、`temp/`、日志、game/.godot。已实际执行 `git check-ignore tmp/permission-audit/results.json tmp/02f-regression/results.json tmp/run-02f-e2e.ps1`，全部命中；`git ls-files tmp temp` 无输出。临时产物不进入 Git，本页持久保存证据摘要。原有未提交改动和手动脚本删除保持，未提交或推送。
