# RTTReplay v1 录制与收尾（0.3B）

正式格式仍为 v1，旧夹具不变。0.3B 文件的 game_version 为 0.3B，0.3C 新录制为 0.3C；该字段不是格式版本。完整加载仍必须通过 ReplayFormat 校验。0.3C 已提供最小离线播放入口，见 [播放说明](REPLAY_PLAYBACK.md)。

版本决定：本轮不改变既有必需字段、身份或游标语义。player_leave.reason 是 v1 允许的可选审计扩展；旧文件缺少它仍按原有 player_leave 语义读取，表现层忽略该附加字段，因此不升级格式版本，也不迁移/重写旧夹具。

## 生命周期

1. `NetworkManager.start_server` 在创建服务器、初始化中立归属敌人后，首次模拟前捕获 tick 0。启用录制时 `ReplayRecorder.start` 深拷贝该状态及初始 header。
2. 录制器订阅 `tick_completed`，在 record 阶段立即深拷贝 records，先检查 JSON 安全性再序列化为自身缓冲，资源对象/非有限值/不安全整数不能被 JSON 隐式转换后悄然记录。信号引用、时间线数组及单位状态都不被保留为可变引用。每一个完成 tick（包括空 tick）都有日志条目；无需输入重模拟。
3. 每 `snapshot_ticks` 捕获含完整 through 游标的 tick 末状态。默认 300 tick（60Hz 下 5 秒），可配置为任意正整数。周期快照恢复后只应用严格更晚事件。
4. 默认每 120 tick 或缓冲约 256 KiB 时一次写入并 flush，状态侧车同时更新；不每 tick 同步刷盘。写入为批次同步操作，不引入后台线程。异常中断可能损失尚未写入的尾部数据，该日志始终是不完整文件，不能标记成功。
5. `finish_server` 停止自动模拟，消费已排队请求/连接；如果仍有玩家会话，在随后结束 tick 关闭这些会话、清除所属命令并记录 player_leave。真实 ENet 断线的 reason 为 transport_disconnect，正常对局结束关闭仍存会话的 reason 为 match_end。两者都保留历史注册表，不恢复身份或控制权。
6. `ReplayRecorder.finish` 在 idle 完整 tick 边界追加最终 checkpoint/header/last_tick/record_count。header 使用服务器全场注册表，包含历史离线玩家。若最终 tick 与周期快照重合，替换该快照而不是重复追加；tick 0 结束只保留初始状态。
7. 将日志组装成 v1，完整校验后写 `.publishing`，再读取实际落盘 JSON 校验，最后同目录 rename 发布正式文件。只有这一步成功，status 才为 complete。不会覆盖已有正式、暂存或状态文件。

## 文件及失败

- 正式输出：用户指定路径或脚本会话目录的 `match.rttreplay.json`，仅成功正常收尾才存在。
- `<输出>.incomplete`：追加式 NDJSON 日志，首条为 RTTReplayJournal（不是 RTTReplay），包含 tick 0、逐 tick records/周期快照以及正常收尾末条。成功后也保留作为证据；它自身不是可加载回放。
- `<输出>.publishing`：最终验证中的临时文件；若中断留存，不能当作已发布文件加载。
- `<输出>.status.json`：status/error/output/journal/last_tick/record_count/batch_writes；每批写入及完成/失败时更新。它是最后已知状态，不是进程存活证明，外部强杀后可能仍显示 recording。
- `ReplayFormat.read_file` 明确拒绝 `.incomplete` / `.publishing`；其日志内容也不符合正式 v1 根结构。任何缺失 tick、批写入失败、最终校验或发布失败都会明确 push_error、发出 recording_failed 并停止录制，对局模拟继续，不发布正式文件。可写侧车保存失败原因；目录不可写时以服务器日志为证。
- 正常结束失败返回服务器退出码 2；成功/录制关闭返回 0。强制进程终止没有正常收尾回执，不能认定成功。默认停止超时后保留服务器运行并报错，不自动强杀。
- `finish` 幂等。完整文件的最终游标、计数、身份、生命/死亡和状态必须通过同一 v1 校验器；不是只靠文件名或状态侧车判断有效。

最终组装和完整校验目前在正常收尾同步完成，并将全场数据读入内存；大规模/长时间录制、磁盘满及真实断电尚未验证。批写入最多仍有一次磁盘阻塞，尚未做性能结论。没有崩溃恢复工具，也没有把不完整日志转换为完整对局的入口。

## 配置及本地控制

生产服务器默认不录制。生产入口支持：

```text
--server --record-replay=<路径> --replay-snapshot-ticks=300
--shutdown-request=<本会话文件路径> --shutdown-token=<本会话随机令牌>
```

无 record-replay 参数即关闭录制。`NetworkManager.configure_recording` 在启动前配置，晚于 tick 0 不允许开始。空输出路径/非法间隔明确报错。录制写入失败不使直接启动的服务器停止；本地启动脚本发现请求的录制未启动则清理本轮启动进程并报错。

启动脚本参数：`-RecordReplay` 开关、`-ReplayOutputPath` 可选自定义路径、`-ReplaySnapshotTicks` 默认 300。不指定路径时为唯一会话目录，避免重复运行覆盖文件。临时日志与默认输出均在被 Git 忽略的 tmp/ 下；自定义输出建议也位于 tmp/。

会话 manifest v3 保存控制路径、随机令牌及已有 PID/UTC 启动时间/可执行文件身份。停止脚本先校验进程身份，只停止本轮客户端，然后原子写入本地 finish 请求；生产入口仅接受匹配令牌的请求，不提供客户端 RPC 结束对局。服务器完成收尾并写令牌匹配回执后自退出，脚本核对真实退出码和回执。Windows Get-Process 的原生句柄在退出前保留以可靠读取退出码。

`-ShutdownTimeoutSeconds` 默认 60（可调）；超时不强杀。`-Force` 是异常终止诊断选项：强制停止服务器会记录 forced-stopped-not-finalized 并使脚本报错，重复停止也不会将其改写为成功。旧 v2 manifest 没有正常收尾接口，强制停止不会报告正常录制完成。

准确实时启动/正常停止及验收证据见 [PROTOTYPE_03B.md](../PROTOTYPE_03B.md)。
