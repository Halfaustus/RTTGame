# 人工验证清单

本页保留 0.3B 当时记录；用户后续已确认完成。0.3C 现在已有最小播放入口，当前验收及命令见 [0.3C 清单](PROTOTYPE_03C.md)，下方“尚无播放入口”只描述 0.3B 阶段。

**自动检查通过，待人工验收。0.2 已验收；本轮没有新增人工验收通过记录。尚无播放入口。**

| 操作步骤 | 预期结果 | 实际状态 |
| --- | --- | --- |
| 使用下方带 -RecordReplay 的启动命令，观察两个窗口并查看本会话 server.log / match.rttreplay.json.status.json | 两客户端连接；tick 0 先包含三名服务器敌人；日志明确 REPLAY recording；正式文件暂不存在 | 真实生产脚本自动检查通过，窗口操作待人工 |
| 选车辆右键移动；F/Q/R 后右键确认；E 停止；移动己方武装单位至左侧敌人附近，观察双方血条和死亡 | 四模式/路径/最终朝向/位置/生命/伤亡均由服务器记录，两客户端显示，路线仍只属主可见 | 13 项离线回归及真实 ENet 四模式、停止、战斗/死亡检查通过；手感/画面人工待验 |
| 正常关闭一个客户端，等待 server.log 的 Peer disconnected，再继续操作另一个 | 断线停止该玩家所属路径，录制保留 join/leave 与历史 player_id；不需要重连、不恢复旧控制权 | 两个真实 ENet 客户端自然退出/断线记录通过；人工窗口操作待验 |
| 执行正常停止命令，查看日志、回执与正式 JSON | 服务器正常退出 0，REPLAY complete；最终 snapshot 游标 tick 等于 last_tick，record_count 等于 records 长度，全场注册表保留两玩家，停止清理仅本轮进程 | 真实 ENet 独立记录/最终状态/header/tick/count 逐条核对通过；脚本正常及重复停止检查通过，人工待验 |
| 另启唯一会话并指定输出路径/快照间隔 | 指定路径发布有效 v1，周期快照间隔生效；原有输出不覆盖 | 自定义路径及 7 tick 间隔自动检查通过，人工待验 |
| 查阅强制中断证据（不必为人工验收再次强杀） | 无正式文件，保留 .incomplete；强制停止与重复停止明确失败，不伪报完整收尾 | 实际生产三进程强制中断保护检查通过；两次停止按预期报错 |
| 查找播放入口 | 当前只有录制、序列化和数据表现接口，没有播放时钟/UI/启动入口 | 不可进行播放验收；留到 0.3C |

# 验证证据

- `tmp/03b/results.json`：编辑器导入及 13 项检查（03B、冻结 v1/03A、02H/input/02G/02A/B/C/D/E、01B/C/D）退出码均 0。03B 故意注入路径错误、tick 缺失、写句柄丢失、日志损坏，明确失败且不发布；这些 ERROR 是负例断言预期，不是检查失败。
- `tmp/03b/prototype_03a_test.log`：冻结 v1 读取、往返、游标边界/表现及非法数据拒绝通过；旧夹具没有修改。SHA-256：F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。
- `tmp/03b/enet-225234/`：最终真实 ENet server/driver/observer 原生退出码均 0，audit 退出码 0；正式回放所有 records 与独立服务器采集逐条一致，header/final checkpoint/tick/count 也完全相等。last_tick=495，record_count=808，快照 9；join=2、leave=2、spawn=6、move=4、stop=4、shot=15、death=1、unit_state=774。两次 leave 来源为真实 transport_disconnect，没有重连测试或控制权恢复。
- 该目录 `server-final.json` 是独立权威采集（测试专用），`match.rttreplay.json` 是生产 ReplayRecorder 正式文件，`audit.log` 是完整校验与比对结果，`process-results.json` 是各进程身份/退出码。`observer-result.json` 记录第二客户端射击/死亡显示及无他人路线。
- `tmp/03b/scripts-224018/results.json`：默认关闭录制、开启录制正常/重复停止、实际强制中断不发布、窗口句柄/双连接/端口释放通过。对应生产会话路径记录在文件内。强制 case 停止脚本预期失败，不算成功收尾。
- `tmp/03b/custom-224500/results.json`：自定义输出及间隔、错误控制令牌被忽略、正常停止、录制启动失败清理、端口释放通过。正式文件是 `custom.rttreplay.json`；失败会话 `tmp/local-test/20261003-224504-5af5706681864118bad9690c0bbe39ec/session.json` 为 failed-cleaned。
- `tmp/03b/diff-check.txt` / `verification-summary.json`：最终空白检查、临时产物忽略与验证摘要。所有本轮进程已结束，默认 7777 已释放。
- 修正记录：首次 ENet 夹具未匹配 SceneTree 的 _process 返回类型并误用 tree_exiting，服务器测试退出 1；修正后真实链路复测通过。窗口脚本首轮 Get-Process 未保留句柄导致成功收尾被误报失败；服务器文件/回执当时已 complete，修正原生句柄后正常/重复停止均通过。没有将失败调用计为通过。
- 未验证：人工操作/画面手感、Linux、长场次/大规模录制性能、真实磁盘满/断电、完整播放器。录制失败隔离和批写入错误是自动注入检查；强杀保护另外有实际进程证据。详见 [录制生命周期](REPLAY_RECORDING.md)。

# 准确的启动／正常停止命令

在 `C:\Projects\RTTGame` 启动生产服务器与两个窗口客户端，并录制到唯一会话目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath 'C:\Dev\Godot\Godot.exe' -RecordReplay -ReplaySnapshotTicks 300
```

正常停止最近成功会话，等待正式文件发布；不要以关闭服务器窗口或强杀替代：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1 -ShutdownTimeoutSeconds 60
```

启动命令可额外附加 `-ReplayOutputPath '.\tmp\replays\manual-03b.json'`（该路径必须未被使用），正常停止可附加 `-SessionFile '<启动时打印的 session.json 路径>'`。省略 -RecordReplay 即关闭录制。尚无播放启动命令。
