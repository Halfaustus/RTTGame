# 最小离线播放（0.3C）

## 兼容性与入口

独立入口 `res://scenes/replay/replay.tscn` 使用 ReplaySession；不加载联机 Bootstrap，不尝试连接服务器。先 ReplayFormat.read_file 校验 JSON/RTTReplay v1/必需字段/全场事件顺序和快照一致性，再 ReplayContent 校验当前地图、规则 ID 与全部 8 项内容指纹；未知版本、错误或缺失指纹、不完整/未发布文件及未知 player_id 均明确拒绝，进程退出 1，启动脚本保留失败日志并清理本轮进程。全部通过后才实例化现有 test_world 地图。

格式版本仍为 v1，没有修改字段或游标语义，不需要迁移；game_version 仅为生成程序版本（新录制为 0.3C），不代替地图/规则/内容校验。实际 0.3B 文件直接兼容。冻结 fixture-map-v1 文件仍用于格式/时钟/表现兼容检查，该测试地图没有生产资产映射，正式播放器不会把它加载为当前生产地图，也不重写旧夹具绕过校验。

ReplayContent 抽取服务器原有地图/规则 ID 和指纹清单，服务器与播放器使用同一目录。指纹 SHA-256 保留 CRLF→LF 归一规则；本轮没有改地图、规则、单位/武器数据。

生产播放参数：

```text
res://scenes/replay/replay.tscn -- --replay-file=<完整回放路径> --view-player-id=1
```

## 播放与表现

- ReplayClock 是无场景/网络/模拟依赖的控制接口：open→start→advance，status / elapsed_seconds / duration_seconds / current_tick，以及 progress_changed / playback_finished 信号。start 先应用 tick 0；入口加载成功自动调用 start，仅支持 1×。没有暂停、倍率或 seek 控件/接口，本轮不实现跳转。
- ReplaySession 用 Time.get_ticks_usec 单调时钟计算实际经过时间，避免 Godot 低帧率时截短帧 delta 导致回放变慢。ReplayClock 将时间换算为 tick_hz 下的 tick，完整消费截至该 tick 的全部已校验记录。tick 内按 sequence 严格应用；不丢弃追帧记录，也不重新应用旧记录。
- 空 tick/尾部空 tick 仍计入时间，最后事件发生并不等于对局结束。总时长 last_tick/tick_hz；到终点 clamp 并进入 finished，仅发一次结束信号，保持最终单位状态和窗口，等待用户停止。高低帧率的事件可在同一显示帧批量呈现，没有插值或保证每个中间 tick 单独渲染。
- ReplayPresentation 缓存绝对表现状态；PresentationFeed 和原 GameWorld 复用单位、血条、射击线、死亡、车体朝向、路径与地图。commands 仅审计，shot 使用已记录的绝对生命结果，不计算伤害。期间不应用周期快照替代记录；完整播放依次应用所有事件。
- 游戏输入在 replay_mode 禁用；GameWorld 不发移动/停止 RPC。NetworkManager autoload 仍存在但没有 ENet peer、模拟 tick、权威单位或已初始化导航；不运行 AI、寻路、随机抽样和权威生成。
- 镜头沿用 WASD、中键/Alt 旋转、滚轮缩放和 GUI 输入阻挡。左键仍可操作观察下拉菜单；单位选择和移动/停止键不执行游戏操作。
- 时间标签显示当前秒数/总时长/tick，结束为 END。唯一额外控件是路线观察下拉菜单：none 或全场历史 player_id。启动参数 -ViewPlayerId 为对局 ID，默认 0=不显示路线，绝非临时 ENet peer ID。控件用 metadata 保存完整 ID；切换只清路径并刷新缓存表现，不改变时间/游标、不重播射击、不恢复死亡单位。

本轮完整文件仍一次读入内存，校验和初始化有加载成本；大文件、长场次/性能、Linux、真实鼠标操作和画面手感待验证。3 FPS 的验证证明记录无丢失与 1× 计时，不证明视觉流畅或所有短暂射击线在低帧率下逐帧可见。实际逐帧画面留人工验收。

## 独立进程脚本

`scripts/start-replay.ps1` 支持必需 -ReplayFile、-GodotPath、-ViewPlayerId、-StartupTimeoutSeconds；默认窗口模式，-Headless 仅供自动检查。解析 console 包装器为实际引擎，等待 REPLAY playback ready，不监听或占用联机端口。日志/进程身份/本地停止令牌存入被 Git 忽略的 tmp/replay-test/唯一会话。

`scripts/stop-replay.ps1` 仅使用 replay-test/latest-session.json 或显式 -SessionFile，拒绝联机会话 manifest。校验 PID、UTC 启动时间、实际 exe、进程名及回放角色参数后，原子写入本会话 stop_replay 请求，等待该回放正常退出 0；不按 Godot 进程名批量关闭，不调用联机停止脚本。超时或身份不符保留进程并报错；重复停止安全。默认 -TimeoutSeconds=10。

验收步骤、最终证据与可复制命令见 [PROTOTYPE_03C.md](../PROTOTYPE_03C.md)。
