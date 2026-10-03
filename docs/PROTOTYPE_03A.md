# 人工验证清单

0.2 已由用户确认人工验收并保存（基线提交 5b8b6d0 / 当前 HEAD 5598d11）。本轮 0.3A 状态：**自动检查通过，待人工复查**；没有自动提交或推送。

| 操作步骤 | 预期结果 | 实际状态 |
| --- | --- | --- |
| 阅读 [v1 格式说明](REPLAY_FORMAT_V1.md) 与冻结夹具 | 对局/版本/频率/地图规则、身份、命令、状态/事件、随机预留字段完整；快照边界明确 | 自动格式/往返/拒绝校验通过；文档待人工复查 |
| 使用现有脚本启动两个窗口，操作基本/F/Q/R 移动、E 停止和编队拖动 | 命令在下一固定 tick 接受；权限、路线隐私、生命/朝向/生成死亡同步保持 0.2 行为 | 0.2 已有人工验收保留；本轮离线回归通过，新调度后的双窗口/ENet 待验证 |
| 对两窗口分别选择和命令，再关闭/重开一个窗口 | 归属验证有效、旧玩家保留但停止、新玩家生成新 ID；敌人不重复生成 | 隔离服务器模型回归通过；本轮窗口操作未执行 |
| 尝试寻找录制/回放菜单或参数 | **本轮没有录制或回放入口**；现有启动脚本只启动实时游戏 | 完整录制、播放、跳转和速度控制留到 0.3B/C，不能执行人工播放验收 |

# 验证证据

- `tmp/03a/results.json`：0.3A、0.2H、command_input、0.2G、0.2A/B/C/D/E、0.1B/C/D 共 12 项检查退出码均 0。
- `tmp/03a/prototype_03a_test.log`：冻结 v1 兼容、文件/JSON 往返、未知版本/非法字段/顺序/快照/死亡复用拒绝、真实服务器代码的隔离模型 tick 顺序与身份、共用表现与快照后不重播旧射击 PASS。
- `tmp/03a/server-model.json`：隔离模型生成的多模式命令、路径、最终朝向、停止、断线/peer 复用及 player_id/单位 ID 状态；`combat-model.json`：同 tick 命令→伤害→死亡→最终状态；`round-trip.json`：冻结夹具往返文件。这些是测试构建的验证数据，**不是整场自动录制功能**。
- `game/tests/fixtures/replay_v1.json`：受版本控制的冻结格式兼容性基准；不能当成生产对局回放入口。
- `tmp/03a/import.log`：最终编辑器导入无脚本/资源解析错误；`server-smoke.log`：仅专用服务器 UDP 17779 启动及三名中立归属敌军检查退出码 0；没有连接客户端。
- `tmp/03a/diff-check.txt`：Git 空白检查退出码 0；所有临时证据由 `tmp/` 忽略规则排除。
- 首轮夹具/校验发现 Godot JSON 数字为 float、字典新增字段可能使用 StringName 键；已修正边界比较和 JSON 安全键处理，并复测实际服务器数据的写入再读取。没有把这些问题归为环境错误。
- 未执行：本轮真实 ENet、两个客户端、桌面人工操作、Linux、完整录制/播放器。根证书读取环境报错不影响离线与服务器启动；TLS 未测。0.2 已验收是用户记录，本轮不伪造新的人工通过记录。

# 准确的启动／停止命令

检查调用记录：最终复测首次调用 0.1B 漏传 `--test-role=simulation`，在角色断言处中止（外层命令退出码 1），不计为通过；补齐参数后重跑 0.1B/0.1C 隔离模拟及完整检查集，最终结果见 `tmp/03a/results.json`。没有启动客户端。

在 `C:\Projects\RTTGame` 启动实时生产服务器和两个窗口客户端：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath 'C:\Dev\Godot\Godot.exe'
```

停止最近一次成功会话：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1
```

暂无回放启动／停止命令。上述命令不能启动回放。
