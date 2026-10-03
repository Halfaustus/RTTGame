# RTTReplay v1：状态与事件契约

0.3A 定义、导出、序列化、校验及应用表现数据；0.3B 加入服务器整场录制和正常收尾参数；0.3C 已有独立离线 1× 播放入口、时间显示与路线观察玩家选择，详见 [播放说明](REPLAY_PLAYBACK.md)。暂停/倍速/跳转未实现。回放不重新执行命令、寻路、AI、随机抽样或伤害计算。

## 时间与执行顺序

服务器实例对应一场对局，`match_id` 为服务器产生的 128 位随机标识。`tick_hz` 在时间线构造时读取 `Engine.physics_ticks_per_second`（当前 60），之后固定；模拟每步使用 `1/tick_hz`，不使用网络时间或回调传入的变长 delta。初始状态为 tick 0；tick N 是第 N 个固定步骤完成后的边界，模拟时间 N/tick_hz。

网络回调只排队连接/断线及合法来源的请求；同阶段按服务器收取顺序处理。不同 peer 的网络到达顺序不保证相同，也不宣称输入重模拟确定性。

| 阶段 | 执行及记录 |
| --- | --- |
| session | 验证当前连接，分配对局玩家 ID、生成单位；断线停止所属命令。记录 player_join/player_leave/spawn |
| commands | 验证仍连接的真实 peer、排队时绑定的 player_id、单位当前归属/资格、模式、目标与朝向；执行命令或拒绝。记录命令及结果 |
| movement | 检查攻击移动交战暂停，再推进路径与车体朝向；之后重新检查交战资格 |
| combat | 现有稳定射手 ID 顺序计算射击、立即伤害与死亡；记录绝对生命结果的 shot，随后 death；死亡 ID 加入 retired 集合 |
| record | 按单位 ID 导出变动/活动单位的完整最终表现状态（包括交战暂停）。记录 unit_state；发出 tick_completed；允许生成 tick 末快照 |
| replication | 按已排好的顺序发送可靠实时结果及到期的位置/朝向；没有新回放事件。最后关闭 tick |

同 tick 的所有命令与事件共用 `sequence`，从 0 连续递增；不分别给命令和战斗计数。空 tick 的最后 sequence=-1。`SimulationTimeline.records` 在下一 tick 清空，只保留一 tick；0.3B 的 `ReplayRecorder` 已订阅 `tick_completed` 并深拷贝后流式消费。

## 文件结构

文件是 UTF-8 JSON 对象。完整冻结样例：[replay_v1.json](../game/tests/fixtures/replay_v1.json)。

| 字段 | 定义 |
| --- | --- |
| header.format / format_version | `RTTReplay` / 整数 1；未知版本明确拒绝 |
| header.game_version / match_id / tick_hz | 生产版本、对局标识、固定模拟频率 |
| header.map_id / rules_id | 显式地图与规则标识，当前生产为 prototype-map-0.2 / prototype-rules-0.2 |
| header.content_fingerprints | 地图、移动/战斗、单位/武器资源文本归一 CRLF→LF 后 SHA-256；播放器加载地图前调用 compatibility 并要求完整当前清单 |
| header.players | 全场对局玩家注册表 `{player_id, label}`；不是账号或临时 ENet peer 表，必须包含历史离线玩家 |
| header.random_seed | 16 位十六进制文本，保留 64 位种子而不经过 JSON 大整数；当前规则尚无随机行为，不据此重新抽样 |
| initial_state | tick 0 初始 checkpoint，不含待处理命令 |
| records | 按 `(tick, sequence)` 排好的统一命令/事件数组 |
| snapshots | 严格按 tick 增长的 tick 末 checkpoint 数组 |
| last_tick / record_count | 文件完成边界与精确记录数；last_tick>0 时必须有最终 tick 的快照，拒绝缺失尾部边界 |

真实玩家/单位/tick/sequence ID 使用 JSON 可精确表达的整数，范围不超过 2^53−1。空间数值为有限浮点数；Vector3 显式表示为 `[x,y,z]`，不存在 Resource、Node 或字符串化 Vector3。Godot JSON 将数字读作 float，校验先确认整数性再按整数 ID 比较，不用 Array.has(float) 直接匹配枚举。

### checkpoint

包含 `through={tick,sequence}`、`units`、`retired_unit_ids`、`next_unit_id`、`connected_player_ids`。列表按 ID 排序。单位仅包含当前存活单位，生命必须在 `(0, maximum_health]`；retired ID 与存活 ID 不相交。

单位包含 `unit_id`、`owner_player_id`、诊断用 `owner_peer_id`、`team_id`、`definition_id`、`unit_type`、`armed`、`position`、`yaw`、`maximum_health`、`health` 和 `command`。

`command={mode,target,path,final_yaw,engaging}`：mode=-1 为无命令，其余 0/1/2/3 分别为基本/快速/攻击/倒车。无命令时 target/final_yaw=null、path=[]、engaging=false；活动命令有完整剩余折线，第一点是当前 position、最后一点是 target。到达后的最终转向可表现为只有当前点的活动路径。攻击移动停车仍保留路径/目标/最终朝向及 engaging=true。倒车只允许装甲单位，攻击移动只允许武装单位。

服务器保持递增 `_next_unit_id`，死亡不回收；即使导航导致某次分配失败，也不会回填 ID。`next_unit_id` 表示所有已分配（包括跳过）ID 的上界，retired 集合保留已死亡 ID。玩家 ID 从 1 递增，0 为中立/服务器敌军。ENet peer 重用不能获取旧 player_id 单位；断线重连仍按已验收 0.2 行为分配新玩家和新单位，不恢复旧控制身份，不新增账号系统。

### records

每条记录包含 `{tick, sequence, phase, kind, type, payload}`。kind=command 时 type=move/stop；保存服务器绑定的 player_id/peer_id、请求 unit_ids/mode/target/facing、accepted_ids/failed_ids/rejection。未知/非己方 ID 不影响其他有效成员。拒绝的非有限 target/facing 记为 null，原因记在 rejection；超过 JSON 精确范围的拒绝请求整数保存为 `{invalid_integer:"原 int64 十进制文本"}`，不能作为实际 ID 或已接受模式。离线表现只推进这些审计记录的游标，绝不执行请求。

kind=event 支持：

- player_join/player_leave：对局 player_id 与该次临时 peer_id。
- spawn：完整单位状态，只能引入新递增 ID。
- unit_state：完整当前单位/命令表现状态，不能生成未知单位或复活零生命/死亡 ID。
- shot：attacker_id、target_id、start/end、目标当前绝对 health；射击线是事件效果，health 是赋值，不能再次减血。
- death：unit_id，移除已存活且生命归零的单位及其路线/选择。
- random_result：`{key,result,context}`，预留关键随机结果；未来随机系统必须记录实际选出的结果，回放不得重新抽样。冻结夹具中的示例不添加游戏随机功能。

## 快照／事件边界

快照是在 record 阶段结束、replication 阶段开始之前取得的完整当前状态。`through` 是它**已经包含**的最后 `(tick,sequence)`；只能指向该 tick 的最后事件，不能指向中途射击/死亡之间。tick 0 的边界固定 `(0,-1)`。

恢复 checkpoint 时清空旧表现和效果、以快照重建存活单位。后续只应用严格大于 through 的记录；相同/更早记录忽略，不重播旧射击。不能跳过未包含的记录再应用后续记录。快照与已有事件折叠结果不符、事件缺号/逆序、重复死亡、死亡 ID 再生成、非法拥有者或命令状态均拒绝。

`ReplayPresentation` 只接受已完整校验的文档，然后手动应用 checkpoint/record；无播放计时、网络连接或模拟。它与实时 RPC 使用同一个 `PresentationFeed`，驱动 GameWorld 现有单位/血条/射击/路线表现。离线 GameWorld 在入树前设 replay_mode=true 并注入 feed，阻止连接信号绑定和任何移动/停止 RPC。观察路线采用选择的对局 player_id，而不查询活跃 peer；这只映射显示元数据，不修改权威归属。

## 兼容性约束

每个大版本必须运行冻结旧夹具的读取/校验/往返/事件边界/表现检查。不能重写旧夹具使测试通过。结构或字段语义变化必须决定格式版本、迁移/拒绝策略，并按需新增夹具。v1 当前支持 v1、明确拒绝其他版本；没有隐式迁移。地图/规则/内容不匹配在播放器加载地图场景前明确拒绝。

冻结 fixture-map-v1 / fixture-rules-v1 是独立数据契约样例，不是生产地图；测试显式传入匹配指纹。它的 schema/表现验证不代表已经实现地图加载或完整回放。
