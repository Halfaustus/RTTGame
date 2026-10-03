# Prototype 0.2B：服务器权威停止命令

0.2A、0.2B 均已由用户确认人工验收通过。下文保留自动检查记录和验收清单，不补写用户未提供的逐项操作结果。

## 行为与文件

- `game/scripts/core/game_world.gd`：现有 `_unhandled_input` 接收 S 的首次按下，经原动作队列处理当前选择。忽略 echo、释放和 Ctrl/Alt/Meta 修饰，GUI 持有焦点时让出键盘。只对仍有效且所属本机的选中单位发送请求，空选择不发送；收到停止结果后更新位置、清理所属单位路线，保留选择。
- `game/scripts/networking/network_manager.gd`：客户端 `request_stops(Array[int])` 不携带 owner 或位置；`_submit_stop` 仅在服务器执行，使用实际 RPC 发送者和已连接 peer 校验。`_apply_stop` 调用移动模拟，读取当前服务器位置并删除这些单位的旧待复制位置；可靠 authority 结果 `_receive_unit_stops(Array[int], Array[Vector3])` 向两个客户端广播。
- `game/scripts/movement/movement_simulation.gd`：`request_stop` 独立过滤未知、死亡、非己方 ID，去重、按 ID 排序，清除目标、剩余路径和路径进度。位置、生命值、武器和冷却均不改变。
- 新增 `game/tests/prototype_02b_test.gd` 与 Godot `.gd.uid`；更新 `docs/HANDOFF.md`、`docs/PROTOTYPE_02A.md`，新增本文。没有创建启动脚本。

停止是服务器收到请求时的位置，因此客户端可在网络延迟期间继续看到移动，随后校正到服务器停止位置。所有停止结果与原有移动/生成/死亡消息在默认可靠通道按序处理，后续再次移动能正常建立新路线。停止不取消自动交战；停步射击武器在停止后可按现有冷却开火。

## 自动检查

以下检查通过，最终没有脚本或资源错误。沙箱仍输出根证书读取、user:// 日志写入及编辑器设置保存权限错误，不能表述为完全没有 ERROR。

```powershell
Set-Location C:\Projects\RTTGame
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --editor --import --quit
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02b_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02a_test.gd
git diff --check
```

0.2B 覆盖混合无效/外人/重复 ID、未选中单位不受影响、目标/路径/进度清理、服务器当前位置保持、其他单位继续移动、重复与静止停止、停止后再移动、死亡 ID、RPC 无有效发送者拒绝、结果载荷与旧缓冲位置清理、按键 echo/释放/修饰/GUI 焦点过滤、两类客户端单位的停止位置更新、所有者路线清理、选择保留以及死后迟到停止不复活。

未启动任何窗口或 headless 客户端；实际 ENet 双客户端传播、完整 S 键输入操作和 GUI 事件传播待人工验收。Linux 服务器未验证。

## 测试启动命令

在三个独立 PowerShell 终端分别执行。先启动服务器，看到 `Dedicated server started on port 7777.` 后启动两个客户端。端口需空闲；不自动结束占用进程。

服务器：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path "C:\Projects\RTTGame\game" --log-file "$env:TEMP\RTTGame-02B-server.log" -- --server
```

客户端 A：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --path "C:\Projects\RTTGame\game" --log-file "$env:TEMP\RTTGame-02B-client-A.log"
```

客户端 B：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --path "C:\Projects\RTTGame\game" --log-file "$env:TEMP\RTTGame-02B-client-B.log"
```

结束时关闭本轮客户端窗口，并在服务器终端按 Ctrl+C；不要按进程名批量终止 Godot。现已删除的手动启动/停止脚本不再使用。

## 人工验收清单

1. 在远离叛军的位置测试。A 框选自己的三个蓝色单位，右键较远落点，途中按 S：三个单位在两端同一位置停止，A 的虚线路线全部消失，选择标记保留。
2. 只选中一个正在移动的单位按 S：该单位停下，未选中的己方单位与 B 的单位继续执行原命令。
3. B 对自己的单位重复上述操作；A 无法控制 B 的单位，即便双方同队。正常 UI 不能构造混合伪造 ID；这种过滤由离线测试覆盖，不冒充手动网络攻击测试。
4. 未选中时按 S，服务器不出现新的 `Stop accepted`；已静止单位连续按 S，无异常。按住 S 一秒，服务器只产生一次对应停止日志，释放再按可以再次停止。
5. 停止后直接右键新目标，所选单位重新移动，A/B 位置一致，所属玩家重新出现新路径；墙绕行仍正常。
6. 靠近敌人用停步射击单位移动并按 S，确认停止后继续遵循自动交战、冷却和死亡规则，不因停止取消攻击；死亡后无选择/路径残留。
7. 检查服务器和两个客户端日志没有脚本/RPC 错误。当前游戏没有可输入文字的 GUI；离线测试已覆盖 GUI 焦点过滤，未来添加 GUI 后需复核实际事件消费。

本轮不添加快速移动、攻击移动、倒车、动态避让；没有提交或推送。
