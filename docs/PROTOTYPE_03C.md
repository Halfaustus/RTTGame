# 人工验证清单

**自动检查通过，待人工验收。用户确认 0.3B 完成；本轮没有人工播放通过记录。已提供独立播放入口，不提供暂停、倍速或跳转。**

| 操作步骤 | 预期结果 | 实际状态 |
| --- | --- | --- |
| 从项目根目录运行下方回放启动命令，不启动服务器 | 独立窗口加载实际 0.3B 文件，自动 1×；显示当前/总时间与 tick，地图/单位/阵营颜色/血条/车头标记正常 | 实际进程与窗口脚本通过；画面待人工 |
| 观察这份 8.25 秒录制的基本/快速/倒车/攻击移动、停车交战、伤害及敌人死亡 | 按文件顺序显示，空 tick 正确计时，无再生成死亡单位，结束为 8.25/8.25 tick 495 END | 正常及实际 3 FPS 完整播放自动通过，808 条记录与最终状态一致；逐帧画面待人工 |
| -ViewPlayerId 1 启动观察路线；重新启动选 2，或运行中切换下拉菜单 none/1/2 | 仅当前对局 player_id 的剩余路线；其他单位仍可见；切换不重播射击、不推进时间或恢复死亡单位 | 适配器/状态与 ID 区分检查通过；下拉菜单实际鼠标操作待人工 |
| 使用 WASD、中键/Alt、滚轮；对地面左/右键并按 Q/F/R/E | 镜头沿用原操作；游戏操作不发命令，不运行寻路/AI/伤害；GUI 操作不穿透 | 输入/镜头回归及离线隔离检查通过；真实鼠标手感待人工 |
| 结束后等待，再执行独立回放停止命令 | 最终位置/yaw/生命/死亡状态保持，停止只退出本轮回放；重复停止安全 | 完整状态保持及正常/重复停止自动通过 |
| 保留联机服务器和两个客户端，同时启动/停止回放 | 原联机三进程继续运行，不被回放脚本关闭 | 实际并存窗口脚本验证通过，人工待验 |
| 参考非法加载证据，不必修改原回放或夹具 | 不完整文件、未知版本、地图/规则或指纹不符、缺失指纹、未知观察玩家明确拒绝；不建立单位显示 | 结构/规则等离线负例、六类真实入口拒绝检查通过；没有重写冻结 v1 |

# 验证证据

- 源文件 `tmp/03b/enet-225234/match.rttreplay.json` 是上一轮正式录制，不是构造替代品；last_tick=495、tick_hz=60、record_count=808、15 shot、1 death。完整播放器读取并播放此文件。
- `tmp/03c/results.json`：导入+14 项检查全部退出 0（03C、03B、冻结 v1/03A、02H/input/02G/02A/B/C/D/E、01B/C/D）。冻结夹具 SHA-256 仍 F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。
- `tmp/03c/playback-normal.json` / `playback-low-fps.json`：生产 replay.tscn/ReplaySession 在实际进程完整播放；两次原生退出码 0。最终缓存与显示单位位置/yaw/生命/ID 完全匹配原正式文件最终快照，808 记录全部应用，15 shot/1 death，无 ENet/服务器 tick/导航/权威单位。正常 wall 8.521s、3 FPS wall 9.058s（含入口初始化与下一显示帧观察延迟，另留 0.5s 终点稳定检查）；两次均满足时长断言，结束标签精确 8.25s/8.25s tick 495 END。
- `tmp/03c/playback-low-fps-before-clock-fix.json`：首轮 3 FPS 使用 Godot delta，记录/状态虽然通过，实际总测试耗时 21.737s，未满足 1× 意图。发现后改用单调时钟并补实际耗时断言；该首轮不能记为 1× 通过。最终低帧率与正常进程均重跑通过。
- `tmp/03c/script-verification/results.json`：可见回放窗口完整播放至 495/808；身份不符拒绝、正常及重复停止、联机三进程不受影响。六类真实启动拒绝均清理本轮进程，日志/身份在各 tmp/replay-test 会话；结果文件指向最终回放与联机会话路径。
- `tmp/03b/enet-232338/process-results.json` 与 `tmp/03c/realtime-audit.log`：必要真实 ENet 回归 server/driver/observer/audit 均退出 0，四模式/停止/双方射击伤害死亡、加入断线及正常录制仍正确。全部 808 records、header、最终状态、496 ticks/count 与独立服务器采集一致。没有新增重连测试。
- `tmp/03c/verification-summary.json` / `diff-check.txt`：最终检查/临时产物忽略/进程结束摘要。Git 保留原未提交工作，未自动提交或推送。
- 未执行人工鼠标/画面验收、Linux、大文件/长场次性能；没有实现暂停/倍速/跳转，也未将这些列为已验证。详见 [播放接口与限制](REPLAY_PLAYBACK.md)。

# 准确的启动／停止命令

在 `C:\Projects\RTTGame` 启动独立回放窗口，指定本轮已完整验证的 0.3B 文件及对局 player_id：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-replay.ps1 -GodotPath 'C:\Dev\Godot\Godot.exe' -ReplayFile '.\tmp\03b\enet-225234\match.rttreplay.json' -ViewPlayerId 1
```

只停止最近成功启动的回放进程，不停止联机服务器/客户端：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-replay.ps1
```

其他正式回放可替换 -ReplayFile，-ViewPlayerId 0 为不显示路线；要停止指定回放可附 `-SessionFile '<启动打印的回放 session.json 路径>'`。联机启动/停止仍用 start-local-test.ps1 / stop-local-test.ps1，见 [0.3B 清单](PROTOTYPE_03B.md)。
