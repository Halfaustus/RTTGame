## 本阶段收尾保存（0.3A～0.3C；不再扩展功能）

- 用户授权将本阶段成果提交并推送至现有 origin/main（https://github.com/Halfaustus/RTTGame.git），使用正常提交与推送，不改写历史。本节为最新阶段决策，以下 0.3A/B/C 小节保留开发时的验证记录。
- 已保留：服务器固定 tick/同 tick 序号、状态/事件 RTTReplay v1、对局玩家与临时 peer 的区分、完整录制/校验发布、最小离线 1× 播放、共用表现接口及独立录制/回放进程脚本。源码、Godot UID、文档、自动测试和冻结 v1 夹具纳入保存；缓存、临时日志/运行记录/实际录制文件不入库。
- 验收边界：0.2 已由用户人工验收并保存；用户确认 0.3B 完成。0.3C 自动验证通过，鼠标/GUI、镜头手感、路线/朝向/血条/射击画面仍待人工，不能标记为完整人工验收完成。没有实现暂停、倍速、跳转或正式历史对战列表/存储服务。
- 已通过且未受影响的检查不重复执行：最终导入+14 项离线检查均为 0；冻结 v1 读取/往返/边界/表现兼容通过，夹具 SHA-256 为 F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。实际 0.3B 文件（495 tick / 808 records）正常与实际 3 FPS 完整离线播放，最终状态/15 shot/1 death 与录制一致。必要真实 ENet 实时回归（496 tick / 808 records）、生产窗口脚本启动/停止和并存进程隔离通过。具体数值与限制保存在各验收文档，tmp/ 证据仅本地保留。
- 已发现并修复的 3 FPS delta 截短问题及首轮测试不足保留在记录中；没有用事件完整性替代 1× 计时。Linux、长场次/大文件性能、真实磁盘满/断电、人工画面验收仍未执行。
- 暂缓：断线重连、回放后续开发、历史对战记录。保留连接/断线事件、身份映射、tick_completed、录制格式/写入、ReplayClock/ReplayPresentation/PresentationFeed 和独立入口，不删除已有成果；不实现自动重连、旧身份/控制权恢复，不推进原计划 0.3D 跳转，也不新增历史对战系统。
- 下一阶段起点：以本次 main 保存版本为基线，先由用户明确新的开发目标；若恢复回放相关工作，先处理现有 0.3C 待人工验收与兼容性验证，再决定控制/跳转范围。暂缓事项不得自动继续，也不得因“阶段收尾”改标完成。
- 本轮收尾只更新状态/范围文档并检查 Git 差异、忽略规则、提交清单、敏感配置与空白；不新增功能，不重新启动已验证的游戏测试。
- 仓库可复查证据：数值/结果已记录在 PROTOTYPE_03A/B/C 与本交接，冻结夹具受版本控制；tmp 中实际录制、PID 会话和日志仅留本地，不上传 GitHub。新检出需自行录制并通过 -ReplayFile 指定文件；实际 03C 测试的 --actual-replay/--replay-file 参数指向本地产生的完整录制，文档中的旧 tmp 路径是该次验证证据，不是随仓库分发的资产。

## Prototype 0.3C 验证交接（自动检查通过，待人工验收；后续开发已暂缓）

- 用户确认 0.3B 完成；不补造人工操作记录。保留全部前序未提交工作，未自动提交或推送。0.3C 不改变 RTTReplay v1 结构/游标语义，冻结夹具未修改，game_version 仅更新为新生成程序 0.3C。
- 新 ReplayClock（open/start/advance/status/progress/finished 控制边界）与 ReplaySession/独立 replay.tscn：先结构/版本，再当前地图/规则和完整指纹清单校验，通过后才加载现有 GameWorld。加载后自动 1× 从 tick 0 播放，按 tick/sequence 完整消费，到 last_tick 停留最终状态。空 tick 正确计时，没有暂停/倍速/跳转，0.3D 再做跳转。
- 实际 3 FPS 首轮发现 Godot 帧 delta 被截短，8.25s 文件的总测试耗时 21.737s；当时只检查事件/状态，不能算 1× 通过。改用 Time.get_ticks_usec 单调时间，补实际耗时断言，正常/3 FPS 实际进程完整重测均 0，808 全记录/最终位置/yaw/生命/存活 ID/15 shot/1 death 正确，终点不继续推进。证据 tmp/03c/playback-normal.json、playback-low-fps.json、before-clock-fix.json。
- ReplayPresentation 缓存绝对表现状态，复用 PresentationFeed/GameWorld 的地图、单位、血条、射击线、朝向和路径。按历史对局 player_id（不是 peer）选择路线；UI 仅时间标签和 none/历史玩家下拉。切换观察只刷新当前表现，无时间变化、旧射击或复活。镜头沿用原控制，GameWorld 禁止游戏输入/RPC。
- 离线入口不加载联机 Bootstrap，不连接服务器、不初始化导航、不执行 AI/随机抽样/伤害/权威生成。NetworkManager autoload 保持 OfflineMultiplayerPeer、timeline.tick=0、权威单位空。ReplayContent 抽取原有地图/规则 ID 与 8 文件指纹供服务器/播放器共用，生产数据/规则未修改。
- 新 scripts/start-replay.ps1/stop-replay.ps1 支持指定 ReplayFile/GodotPath/ViewPlayerId，单独 tmp/replay-test manifest/日志/随机本地停止令牌，只管理该回放 PID/UTC/exe/角色。支持窗口，Headless 仅用于检查；等待真实播放就绪。拒绝联机 manifest，身份错/超时不关闭，重复停止安全。生产窗口实际完整播放及联机并存隔离通过，原有联机三进程不受回放停止影响，最后由本轮联机脚本正常清理。
- 自动：导入+14 项离线回归均退出 0，包含 03C、03B、冻结 v1/03A、0.2 镜头/输入/全部移动停止战斗及 0.1 模拟。正式 03B 文件 tmp/03b/enet-225234/match.rttreplay.json 在正常及实际 3 FPS 播放；不是重新生成的替代文件。
- 必要实时 ENet 回归 tmp/03b/enet-232338：server/driver/observer/audit 均 0，四模式/停止/双方射击死亡、加入断线和录制仍正确；808 records/header/最终状态/496 ticks/count 与独立权威采集一致。没有新增重连专项测试。
- 最终窗口脚本证据 tmp/03c/script-verification/results.json：回放可见至495/808、身份保护、正常/重复停止、联机进程保持存活；6 类真实入口拒绝（不完整、地图、版本、指纹、缺失清单、未知 player_id）均清理。规则错误等额外离线负例通过。详细手动步骤见 PROTOTYPE_03C.md；接口/限制见 REPLAY_PLAYBACK.md。
- 待人工：镜头鼠标/GUI与观察菜单、路线/朝向/血条/射击画面、实际观感。Linux、长文件/性能未测；低 FPS 验证保证记录/1×，不保证每个中间 tick 单独绘制或视觉流畅。所有本轮进程已结束，临时证据排除 Git，冻结 SHA-256 不变。

## Prototype 0.3B 历史交接（用户后续确认完成）

- 保留全部 0.3A 未提交实现和文档，没有自动提交或推送。格式仍 RTTReplay v1，旧 replay_v1.json 未修改；新生产 game_version 为 0.3B，冻结兼容性回归通过。
- 新 ReplayRecorder 在服务器 tick 0 后/第一次模拟前启动，订阅 tick_completed 深拷贝全记录，空 tick 也入暂存日志。默认 300 tick 快照、120 tick/约 256KiB 批写入与侧车更新；正常收尾使用最终全场注册表（包括历史离线玩家），最终游标/计数与快照，验证并读回成功后 rename 发布。
- .incomplete 是非 v1 的 NDJSON 暂存日志；.publishing 尚未发布。read_file 明确拒绝两者。失败日志/信号/可写状态文件明确报告且对局继续；不覆盖已有输出。真实强杀只留下暂存/最后已知状态，不存在 complete 文件，不会被停止脚本认定正常完成。整场最终组装/校验仍在收尾同步读入内存，长场次与磁盘满/断电未验证。
- NetworkManager 增加 configure_recording/finish_server；Bootstrap 解析录制与本地控制参数，无结束对局 RPC。正常结束在完整 tick 消费请求/连接并结束仍在线会话：player_leave.reason 区分 transport_disconnect 与 match_end，历史玩家不删除，不实现重连/身份或控制权恢复。
- 启动/停止脚本沿用真实生产入口与 PID/UTC/exe 身份保护，manifest v3 加会话专用请求文件/随机令牌；默认关闭录制，-RecordReplay/-ReplayOutputPath/-ReplaySnapshotTicks 配置。停止先关闭本轮客户端，然后请求服务器正常收尾、等待退出码 0/匹配回执。超时不强杀；-Force 明确报未成功收尾，重复停止也不掩盖。Windows Get-Process 先持有句柄避免正常退出码采集误报。
- 自动：导入+13 个离线检查均退出 0。03B 覆盖深拷贝、空 tick、周期/最终快照重复边界、tick 0 结束、历史玩家、不可写路径、缺 tick、写句柄失败、日志损坏、不覆盖。03A 冻结夹具往返/兼容/边界/表现检查和完整 0.2/0.1 回归通过。
- 真实 ENet 最终 tmp/03b/enet-225234：生产 Bootstrap/NetworkManager/ReplayRecorder +两个 headless 客户端，四移动模式/停止/双方射击伤害死亡/加入与自然断线。server/driver/observer 均退出 0；audit 0，全部 808 records 与独立服务器采集一致，header/最终 checkpoint/495 ticks/count 也严格相等；9 快照、2 join/leave、6 spawn、4 move/stop、15 shot、1 death。两次 leave 是 transport_disconnect；本轮未扩展或专项测试重连。
- 生产窗口脚本：tmp/03b/scripts-224018/results.json 为关闭录制/开启正常收尾及重复停止/实际强制中断三种验证；tmp/03b/custom-224500/results.json 为自定义路径/7 tick 快照/错误令牌不停止/录制启动失败清理。所有本轮进程结束/7777 释放，测试不记为人工通过。
- 已修正并保留失败证据：新 ENet SceneTree 夹具返回类型/退出信号解析错误；首次窗口脚本未缓存 Get-Process 原生句柄导致正常收尾误报失败。初次受限进程启动环境字典不可访问，经运行批准后真实测试完成；不修改系统权限。故意注入负例错误单独记为预期，最终无未解决功能失败。
- 文档：REPLAY_RECORDING.md 说明生命周期/暂存与正式边界/配置/失败与限制；PROTOTYPE_03B.md 为人工步骤/证据/准确启动正常停止；LOCAL_TEST_ACCEPTANCE 当前指向 03B。人工操作、Linux、长录制性能和播放器未验证。尚无播放入口、播放时钟/UI；留到 0.3C。

## Prototype 0.3A 历史交接（自动检查通过，待人工复查）

- 用户已明确确认 0.2 人工验收并保存。开始时 Git 干净，HEAD 5598d11（前序 5b8b6d0 保存完整 0.2）。下面 0.2C～H 的“待人工”是当时历史记录，被本次用户验收结论覆盖；没有擅自编造具体人工操作日志。
- 实现固定服务器 tick（当前 60Hz）和同 tick 共用连续事件序号。真实来源请求及连接事件排队：session→commands→movement→combat→record→replication。record 边界后才发送实时结果。保留当前 tick 数据及 tick_completed 钩子，未接入整场文件录制或播放时钟/UI。
- 对局 match_id 与预留 seed 由服务器产生；owner_player_id 与控制用 owner_peer_id 分开，无账号系统。每次连接分配新对局玩家 ID，归属验证还检查当前玩家身份，重用 peer ID 不会取得旧玩家单位。单位 ID 持续递增，死亡不回收，快照带 retired_unit_ids/next_unit_id。
- RTTReplay v1 显式 JSON 结构与校验涵盖初始/最终快照、命令及处理结果、四移动模式、完整剩余路径/最终朝向/暂停、位置 yaw、生命、生成/射击/死亡、玩家连接与随机关键结果预留。快照包含到 through 游标为止的完整 tick；恢复后只应用严格更晚事件，命令仅审计，不重模拟。未知版本明确拒绝，资源指纹归一换行后 SHA-256。
- 实时与回放共用 PresentationFeed；保留 NetworkManager 原信号转发，现有订阅不失效。ReplayPresentation 只手动应用已校验的数据，GameWorld 离线模式不接网络信号、不发命令；使用对局 player_id 显示所属路线，不执行 AI/伤害/权威生成。
- 文件范围：新增 replay/simulation_timeline.gd、replay_format.gd、replay_presentation.gd、core/presentation_feed.gd 及 UID；单位加身份字段、移动加命令状态导出，NetworkManager 调整必要调度与导出，GameWorld 注入表现源；新增 prototype_03a_test.gd/UID 与冻结 replay_v1.json。未做无关重构。
- 0.3A 及完整 0.2/0.1 离线回归共 12 项原生退出码 0，编辑器导入/服务器隔离 17779 启动/diff 均 0。证据 tmp/03a/results.json、各日志、server-model.json/combat-model.json/round-trip.json；模型文件是测试验证数据，不是正式录制。旧 v1 夹具读取/往返、非法版本/顺序/快照边界/身份/死亡复用、实际 tick 模型及离线表现检查通过。
- 本轮未启动客户端或真实 ENet；新调度和表现转发后的双窗口同步待复查，完整录制/播放器留到 B/C。当前没有回放入口或回放命令。AGENTS 已加入每个大版本必须验证冻结回放兼容性、显式版本/迁移决定的约束。详见 [REPLAY_FORMAT_V1.md](REPLAY_FORMAT_V1.md)、[PROTOTYPE_03A.md](PROTOTYPE_03A.md)。
- 根证书环境报错不影响本轮已执行离线与服务器启动，Linux/TLS 未测；临时证据排除 Git。未自动提交或推送。

## Prototype 0.2H 历史状态（当时自动检查通过；0.2 后续已由用户人工验收并保存）

- 当前键位为 WASD 镜头平移、中键/Alt 旋转、滚轮缩放、E 停止、Q 攻击、F 快速、R 倒车、Esc 取消。S 已迁移到镜头后移，A 为镜头左移，既有 Q 目标语义不变；左键只选择，右键释放确认。没有其他预留键位功能。
- 新增独立 `local_camera.gd`、`camera_config.gd`、`prototype_camera.tres` 及 UID，绑定原 Camera3D。保持初始视图和透视投影/FOV；地面观察点平移/轨道旋转/距离缩放，不依赖网络或修改服务器模拟。18m/s、0.2°/屏幕像素、2m/滚轮格；俯仰 20°～80°、距离 6～60m，配置集中于资源。
- 镜头旋转开始取消选择/编队拖动和待处理点击，期间屏蔽选择与单位命令确认；GUI 经实际 Viewport 路由消费，不穿透；全局释放清理保证 GUI 消费释放后不留按键，窗口失焦/退出清理并恢复捕获前鼠标模式。Alt/中键任一仍按住时继续旋转。桌面光标位置恢复和手感待人工，headless 不能证明 OS 光标效果。
- 镜头可动后修正原拖动中心重新投影：右键按下记录实际地面中心，释放记录地面方向，物理帧仍负责发送请求；拖动期间移动镜头不改变已固定中心。服务器移动、战斗、路径和权限逻辑未改。
- 修改 GameWorld 的旋转屏蔽/E 停止、test_world 相机绑定；新增 `prototype_02h_test.gd/UID`。02B 输入检查及真实 ENet 夹具停止键更新 E，02F 夹具本轮未启动客户端执行；没有把历史 ENet 结果记为 E 真实联网通过。
- 最终编辑器导入与 0.2H/command_input/0.2G/0.2A/B/C/D/E/0.1B/C/D 共 11 项离线回归退出码均 0，无最终脚本/资源错误。证据 `tmp/02h/import.log`、`results.json`、各日志及 `diff-check.txt`。最初测试类型推断和 headless 隐藏鼠标固定预期已修正，最终状态比较引擎返回的实际鼠标模式。
- 本轮没有窗口/headless 客户端测试或真实 ENet，按项目约定仅做输入/隔离模拟；人工操作、帧率/手感、GUI 桌面行为、双窗口同步和 Linux 待执行。根证书环境报错不影响离线检查，TLS 未验证。临时证据排除 Git，未改系统权限、未提交或推送，保留原有未提交改动。
- 当前完整统一步骤见 [PROTOTYPE_02H.md](PROTOTYPE_02H.md)，PROTOTYPE_02F 的当前表及 LOCAL_TEST_ACCEPTANCE 已更新；0.2G 页面注明 S 的历史步骤改用 E。启动/停止脚本保留生产 7777 入口和此前验证证据，本轮未重复窗口启动。

## Prototype 0.2G 历史交接（自动检查通过，待人工验收）

- 修复之前不可读的 0.2G 交接段文字，保留其实际结论：服务器复用 yaw/倒车平滑转向，前进车头/倒车车尾沿路线，最终朝向转向；稳定 ID 的 1.5m 横排沿最终左右轴，合法选中单位中心决定点击默认方向；静止零距离保留朝向。射击不修改车体 yaw。
- 右键释放确认与 8 像素拖动、候选落点/朝向预览、Esc 取消；服务端验证真实归属/模式/目标/朝向并保留可达回退和旧命令。0.2G 当时停止键为 S，本轮迁移为 E。
- `tmp/02g/results.json` 记录 10 项离线检查通过；`tmp/02g/enet-final` 为 UDP 18889 真实生产链路检查，driver/observer/late 退出码均 0，服务器由测试持有句柄清理。拖动预览不提前提交、旋转落点/最终 yaw、非法朝向、权限/所属路线/伤亡/重连/晚加入/无敌人重复生成通过。
- 保留限制：折线路径原地转向，无转弯半径或连续曲线；拐点最多损耗一物理步时间余量；快速规划不计转向耗时；0.05s 朝向复制且无客户端插值；候选预览可能不同于服务器障碍/边界回退。0.2G 没有游戏人工通过记录，细项见 [PROTOTYPE_02G.md](PROTOTYPE_02G.md)。

## 人工验收启动／停止脚本最新状态（脚本检查通过，游戏人工验收待执行）

- 按用户明确要求，已实际保存 scripts/start-local-test.ps1 和 scripts/stop-local-test.ps1；先确认文件存在及语法，再执行生产入口验证。脚本删除的旧记录仅代表历史状态；当前两文件存在。
- 最终脚本已在默认 7777 启动隐藏生产服务器及两个可见窗口客户端，两个客户端均连接；按会话身份停止并重复停止通过，端口释放。端口占用拒绝、启动失败清理、启动时间不匹配拒绝及不误杀独立 Godot 检查通过。脚本验证不是游戏人工验收。
- 记录 PID/UTC 启动时间/真实主程序路径/进程名/角色/参数/日志，包装器解析到真实主程序；停止仅关闭匹配本轮身份的进程。日志和记录放 tmp/local-test，现有 Git 忽略规则已覆盖。
- 最终证据 tmp/local-test/20261003-201044-2aaadb9d55cc427a831ee4b632a98ba1；保护检查证据 tmp/local-test/20261003-200638-d049bdfcad954e9a943cff8de4d41ec0。清单、准确命令及证据见 [LOCAL_TEST_ACCEPTANCE.md](LOCAL_TEST_ACCEPTANCE.md)。游戏手动清单继续见 PROTOTYPE_02F.md，尚未记为人工通过。
- AGENTS.md 已写入最终验收输出约定：只保留人工验证清单（步骤/预期/实际）、验证证据（明确未验证项）、准确启动/停止命令；不附开发过程、修改摘要或无关环境信息。影响验收的问题放对应清单和证据。
- 保留其他未提交改动，未自动提交或推送。

## Prototype 0.2F 记录（端到端自动检查通过，待统一人工验收）

- 已实际运行生产 NetworkManager/模拟/显示链路的独立服务器＋两个 headless ENet 客户端；真实命令、权限、基本/快速/攻击/倒车/停止组合、位置/yaw、所属路线、受伤/死亡、同进程重连及随后全新晚加入检查通过。最终证据 tmp/02f-e2e-194108；driver/observer/late 原生退出码 0，常驻服务器由测试清理主动终止 -1，不能记为自然退出通过。
- 发现并最小修复 GameWorld 重连旧显示残留：断线/新连接清视觉、路径、选择和死亡记录；旧节点退出回调解除，防止延迟释放误删新快照。其他游戏逻辑未改；新增 prototype_02f_e2e.gd/UID，输入测试补充会话重建回归。
- 编辑器、input、0.2A/B/C/D/E、0.1B/C 模拟、0.1D 及 diff 回归通过。根证书环境报错仍存在；项目临时目录无日志或编辑器设置写入错误。
- 默认 7777 生产启动本轮失败（原生退出码 1）：已有 Godot PID 40616 占用，未关闭已有进程。18888 独立端到端启动与本轮 Process 对象清理通过；默认 7777 的新三进程启动当前被占用阻塞，可见窗口人工测试未执行。
- 0.2C/D/E/F 未记录为人工验收通过；所有可见交互/观感/卡顿、Linux、高延迟等未执行范围及当前 Q/F/R/S 实际键位统一列入 [PROTOTYPE_02F.md](PROTOTYPE_02F.md)。现有重连仍生成新玩家单位，不恢复旧玩家控制身份；不新增身份系统。
- tmp/permission-audit 和所有本轮临时产物均命中现有忽略规则，git ls-files tmp temp 无输出；验证摘要持久保存在文档。保留所有原有未提交修改和脚本删除，未提交或推送。

## Prototype 0.2E 历史记录（自动检查通过，待人工验收）

- 环境报错复核完成：默认 0.2E 和编辑器导入均原生退出码 0；原日志实际在 AppData/Roaming/Godot/app_userdata/New Game Project/logs，编辑器设置在 AppData/Roaming/Godot。仅对子进程临时设置 APPDATA/LOCALAPPDATA 到项目 tmp/permission-audit 并指定 --log-file，已消除文件写入错误，不改系统权限或持久环境变量。
- 项目临时目录下完整复核编辑器、输入、0.2A/B/C/D/E、0.1B/C 模拟、0.1D、服务器启动全部原生退出码 0，测试均 PASS；diff 检查 0。根证书读取仍报错，无文件路径，记录为环境问题，不影响已执行离线与 ENet 启动检查；HTTPS/TLS 未验证。双客户端/人工/Linux 检查未执行。具体命令、路径、退出码和历史失败区分见 [ENVIRONMENT_CHECK_02E.md](ENVIRONMENT_CHECK_02E.md)，逐项证据位于被忽略的 tmp/permission-audit/results.json。

- 本轮实现服务器权威倒车：R 进入、右键确认后退出、Esc 取消；左键仅选择。Q/F/S 保留，待确认模式互斥，无模式右键基本移动。
- 仅存活己方装甲车辆接受，步兵及无效/非己方 ID 保留旧命令；复用基本距离寻路、多选落点、绕障及不可达处理。
- 新增权威 yaw、倒车两种路面速度、配置转速和黄色车头标记。车辆倒车起步/折点先平滑原地转向再沿原路线移动，不横滑；前进速度不变。位置/朝向由服务器广播，停止和晚加入也同步当前朝向。
- 默认车辆倒车速度硬化/非硬化 4/1.5m/s，转速 180°/s，原有前进 8/3m/s。无连续弧线/转弯半径；折点最多损失一物理步剩余时间。客户端每 0.05s 应用朝向，无视觉插值，观感待人工验收。
- 自动通过：编辑器导入、0.2E、输入、0.2A/B/C/D、0.1B/C 模拟、0.1D 导航与服务器独立启动、diff 检查。0.2A 射击线清理测试补等处理帧，解决 deferred queue_free 的时序误报；最终没有脚本/资源错误，环境权限报错仍存在。
- 本轮未运行客户端或人工测试。0.2C/D/E 留到 0.2 收尾统一人工验收，不记为人工通过。保留原有未提交改动与脚本删除，未提交或推送。文件范围、自动命令、双客户端启动和验收清单见 [PROTOTYPE_02E.md](PROTOTYPE_02E.md)。

## Prototype 0.2D 历史记录（自动检查通过，待人工验收）

- 本轮输入复核：左键只选择；Q 攻击移动、F 快速移动由右键确认，无待确认模式时右键基本移动；Esc 取消，确认后退出。不迁移其他快捷键。
- 用户明确本轮只统一输入并回归，倒车另行实现。当前不存在倒车功能，不记录为完成或验证通过。
- 新增 command_input_test.gd（实际事件离线检查），将客户端输入分支提取为可隔离验证的入口，保留连接/角色检查。输入事件检查、编辑器导入、0.2A/B/C/D、0.1B/C 纯模拟、0.1D 回归和 diff 检查通过。
- 本轮没有客户端测试或人工测试；状态为“自动检查通过，待人工验收”。环境权限报错与一次不支持的测试角色调用及纠正已在 PROTOTYPE_02D.md 记录。保留既有修改及脚本删除，未提交或推送。

- 0.2B 用户人工验收已通过；0.2C 人工复查合并至 0.2D，尚未通过人工验收。
- 已实现服务器权威攻击移动：Q 后右键下令，Esc 取消，下令后退出；F/Q 互斥。服务器复用真实发送者验证、基本距离寻路、最近射程内且视线通畅敌人选择；仅存活己方武装单位接受。
- 交战暂停保留目标及剩余路径，无可攻击目标后恢复；无追击。普通/快速移动替换，S/死亡/断线清理。既有位置与战斗同步显示结果，路线仅所属玩家可见。
- 本轮修改 movement_simulation.gd、network_manager.gd、game_world.gd；新增 prototype_02d_test.gd 和 PROTOTYPE_02D.md。复用现有三名静止叛军与战斗数据。
- 自动检查：编辑器导入、0.2D 隔离检查、0.2A/B/C 回归、0.1D 导航回归及独立服务器启动通过；未运行客户端。环境证书/日志/编辑器设置权限错误仍存在，没有最终脚本或资源错误。
- 双客户端操作、同步与 0.2C 下令卡顿复查仍待人工验证。准确启动命令、检查命令及合并验收清单见 [PROTOTYPE_02D.md](PROTOTYPE_02D.md)。
- 保留全部原有未提交修改和 scripts/start-local-test.ps1、scripts/stop-local-test.ps1 的删除；没有创建启动脚本、提交或推送。

# RTTGame 开发交接

## 最新状态：Prototype 0.2C（2026-10-03）

- 后续修正：快速移动改为 **F 进入一次性模式，再次 F 取消，右键提交后退出**；显示模式提示，失焦/断线取消，忽略键盘 echo 和 GUI 焦点。Ctrl+右键恢复基本移动。
- 用户确认卡顿出现在下达快速移动命令瞬间。Godot `--profiling --debug` 定位到重复端点组合搜索与边代价计算；改为复用原网格生成的静态 AStar2D 连接，一次搜索连接全部端点，并缓存同速度配置的静态边代价。地图重建/速度配置变化时失效，查询临时节点用完移除。
- 同组 23 次寻路 Profiler 累计约 **3.049 → 0.206 s（减少 93%）**，边代价调用 **567670 → 33930**；初始化建图在服务器监听前完成，不在每次命令中重建。A-B 路线仍为 16.000 m / 4.917 s 与 20.615 m / 2.577 s。
- 更新后编辑器导入、0.2C（含 F 状态和缓存失效测试）、B/C/D/0.2A/0.2B 回归通过；没有启动客户端。F 实际操作及下令停顿改善待人工复核。

- 用户明确确认 0.2B 已完成人工验收。当前仍为 `main` / `cce23af`，保留此前全部未提交改动和两个手动脚本删除，没有提交或推送。
- 新增单位类型与路面速度。每玩家仍为三名单位：首名平矮方块装甲车辆（硬化 8 / 非硬化 3 m/s，原移动射击武器），另两名球形步兵（两路面均 4 m/s，原停步武器/无武器）。不增加部署系统。
- 默认右键基本移动，F 后右键快速移动；核对没有现有快捷键冲突。请求使用服务器验证的模式整数：0=基本，1=快速；归属仍由真实 RPC 发送者校验。
- 复用 0.5 m `AStarGrid2D` 占用网格生成 AStar2D 静态连接：基本按距离，快速按分路面的预计时间计价，直接路线也作为候选，不强制道路。平滑每段检查膨胀障碍净空；快速捷径不得增加预计时间。步兵等速复用基本距离规划，避免无意义绕路。
- 实际移动按单位速度与路面边界分段消耗 tick 时间，与模式无关。保留多选横排、不可达保留旧路径、新命令替换、S 停止、死亡清理和所属玩家实际路线显示。
- 共享地图新增灰色 U 形硬化道路与 A/B/C 标记。A=(-8,102)、B=(8,102)、C=(-4,102)。A-B 直达 16.000 m / 4.917 s，快速车辆约 20.615 m / 2.577 s；A-C 快速选择直达。更长道路绕行也由离线地图覆盖。
- 自动检查通过：Godot 4.7.2 编辑器导入、0.2C 路线/速度/边界/输入/表现检查、B/C 纯模拟、D/0.2A/0.2B 离线回归、仅服务器独立启动（隔离 UDP 17779）、`git diff --check`。旧 D 启动检查已改为验证叛军 owner 0，而不是“单位表为空”。没有启动客户端。
- **0.2C 实际双客户端人工验收待进行**。沙箱证书读取、user:// 日志和编辑器设置权限错误仍存在；最终无脚本或资源错误。Linux 服务器未验证。
- 自动交战代码未改变，不保持位置、不追击、不驱动移动；快速移动不增加速度或改变武器规则。未加入动态避让、攻击移动、倒车或新战斗功能。
- 详见 [PROTOTYPE_02C.md](PROTOTYPE_02C.md)：修改文件、参数、验证证据、限制、人工清单与可直接粘贴的一键启动命令。没有恢复或创建启动脚本。

## Prototype 0.2B 实现记录（已人工验收）

- 用户明确确认 0.2A 已完成人工验收。本轮核对发现此前只有断线停止逻辑，尚无玩家停止请求。
- 已新增 S 键多选停止：沿用 `_unhandled_input` / 动作队列，忽略 echo、按键释放和 Ctrl/Alt/Meta 修饰；GUI 有焦点时不触发。空选择不发送请求。
- 客户端只发送 `Array[int]` 单位 ID。服务器使用 `get_remote_sender_id()` 并核对已连接 peer，模拟逐个过滤无效、死亡、非己方 ID，去重后清除目标、路径及进度；停止位置保持服务器当前位置。
- 可靠 authority 停止结果为平行的 `Array[int]` 与 `Array[Vector3]`，向所有客户端广播。发送前清除已停止单位的旧待复制位置；客户端更新位置、所有者清理路线，并保留选择。未知或已死亡单位不会被停止结果生成。
- 停止不修改战斗状态；重复停止、已静止停止和再次移动均支持。未添加其他移动模式或动态避让。
- 本轮自动检查通过：Godot 4.7.2 编辑器导入、0.2B 离线模拟/服务器结果/输入与表现检查、B/C 纯模拟、D 与 0.2A 离线回归、`git diff --check`。没有启动客户端；沙箱证书、日志和编辑器设置权限错误仍存在，最终没有脚本或资源错误。
- 用户已明确确认 **0.2B 人工验收通过**；下列检查为当时自动检查记录，不补写用户未提供的逐项操作结果。
- 保留本轮开始时全部未提交改动及手动脚本删除；没有自动提交、推送或创建启动脚本。
- 本轮文件：`game_world.gd`、`network_manager.gd`、`movement_simulation.gd`，新增 `game/tests/prototype_02b_test.gd` 及 `.gd.uid`；更新交接与 0.2A 验收状态。启动命令、0.2B 验收清单见 [PROTOTYPE_02B.md](PROTOTYPE_02B.md)。

## Prototype 0.2A 实现记录（已人工验收）

- 用户已明确确认 Prototype 0.1D 通过手动验收。
- 本轮开始时为 `main` / `cce23af`，工作区干净；以下 0.2A 改动未提交、未推送。
- 已实现基础服务器自动交战和死亡同步；用户已明确确认 0.2A 人工验收通过。
- 玩家控制按 `owner_peer_id`；双方玩家同为 team 1，叛军为 team 2 / owner 0。
- 新增单位/武器数据资源、独立战斗模拟、三名静止叛军、阵营颜色、血条和 0.12 秒射击线。每玩家依次生成移动射击、停步射击、无武器三种单位。
- 服务器按最近距离、同距 unit_id 选存活敌人，实际地图障碍盒阻挡视线；伤害立即结算。交战不追击、不改移动命令。死亡清理模拟、冷却、待发送位置及客户端选择/路径。
- 晚加入快照只含存活单位及当前阵营、生命值；叛军只在服务器初始化时生成一次。客户端位置/生命值消息不会生成单位，死亡 ID 也拒绝迟到生成。
- 验证通过：Godot 4.7.2 编辑器导入、0.2A 离线模拟/服务器快照/表现清理、0.1B/C 纯模拟及 0.1D 离线回归。未启动客户端。仍有沙箱根证书、user:// 日志和编辑器设置权限错误；没有脚本或资源错误。
- 旧 B/C 联网测试服务器夹具跳过叛军以保留移动测试的原有 ID 假设；本轮未运行这些客户端测试。
- 详细实现范围、检查命令和双客户端验收步骤见 [PROTOTYPE_02A.md](PROTOTYPE_02A.md)。Linux 专用服务器仍未验证；0.2A 双客户端人工验收已由用户确认。
- 用户要求删除手动验证脚本，已删除 `scripts/start-local-test.ps1` 与 `scripts/stop-local-test.ps1`；保留自动测试脚本。当前手动验收改用上述 0.2A 文档中的直接 Godot 命令，下方历史启动器命令不再适用。

## 以下为 0.1D 收尾时的历史记录

下文中的 `master` / `70ab89b`、未提交文件数量和“0.1D 待验收”描述只代表当时状态，以本页最新状态为准。

更新日期：2026-10-03（Asia/Shanghai）。本次收尾只新增此记录，没有添加功能、启动客户端、暂存、提交或推送，也没有删除或撤销原有修改。

## 当前阶段

Godot 4.7.2 / GDScript，专用服务器权威架构。当前为 Prototype 0.1D：基础寻路与静态障碍绕行已实现，自动检查通过，双客户端人工验收待进行。

| 阶段 | 今天完成的内容 | 验证状态 |
| --- | --- | --- |
| 基础联网与生成 | headless 专用服务器、ENet 本机连接、服务器分配 ID 和归属、生成广播、晚加入同步、Unit 脚本移至 scripts/units | 已有联网检查；用户提供稳定运行记录 |
| 0.1A | 本机所属单位点击选择与选择标记 | 已有检查；后续由 0.1C 扩展 |
| 0.1B | 客户端移动命令、真实发送者归属验证、服务器移动、位置同步、晚加入当前位置、断线停止 | 用户明确记录“已完成并审查通过”；本次纯模拟回归通过 |
| 0.1C | 选择集合、框选、每玩家三个单位、多单位命令、稳定 ID 顺序落点；随后改为世界 X 方向一横排、仅所属客户端显示虚线路径 | 用户明确记录“已通过手动验收”；本次纯模拟回归通过 |
| 0.1D | 静态墙与障碍、服务器 A* 网格路径、绕行、路径替换、可达落点检查、障碍内目标附近回退、失败保留旧命令 | 本次离线检查通过；此前服务器独立启动检查通过；尚无用户双客户端验收记录 |
| 本地测试工具 | 一键服务器加两个窗口客户端、分开日志、等待就绪、UDP 7777 占用检查、进程身份记录、仅关闭本轮进程 | 之前启动、端口冲突、身份不匹配保护、重复停止及不影响其他 Godot 的检查通过；本次 PowerShell 语法检查通过 |

人工验收只依据会话中用户已提供的记录，不把自动检查当作人工验收，不补填未提供的具体操作结果。

## 当前实现与文件职责

- `game/scripts/networking/network_manager.gd`：Autoload。只有服务器分配 unit_id 和 owner_peer_id；移动 RPC 使用真实发送者逐个校验、过滤无效或非本人 ID。生成与位置由服务器复制，路径仅发送给对应所有者。
- `game/scripts/units/unit_state.gd`：权威运行时单位状态；`game/scripts/units/unit.gd` 仅承担视觉表现及选择标记。
- `game/scripts/movement/movement_simulation.gd`：服务器移动命令及沿路径推进。无有效路径的单位保留旧目标、旧路径和进度。断线停止该玩家单位，当前不删除其单位。
- `game/scripts/movement/static_navigation_grid.gd`：同步初始化 AStarGrid2D，服务器监听前完成。按单位半宽加余量扩大静态障碍，检查完整路径线段，避免切墙角；不依赖客户端相机或异步导航烘焙。
- `game/scripts/core/game_world.gd`、`selection_rectangle.gd`、`movement_path_visual.gd`：本地点击、框选、所属单位验证及剩余虚线路径显示。选择不发送到服务器；客户端不提交路径、不执行权威移动。
- `game/data/prototype_movement.tres`：速度 4 m/s，复制间隔 0.05 s，每玩家 3 单位，单位宽 1 m，落点间距 1.5 m，导航格 0.5 m，障碍余量 0.05 m，附近目标搜索半径 2 m。地图 X 范围 [-20,60]、Z 范围 [80,120]。
- `game/data/prototype_map.tres` 与 `game/scripts/maps/`：共享静态障碍数据及对应可见几何、碰撞体。主墙 X=[-4,4]、Z=[93.5,94.5]；另一障碍 X=[5,7]、Z=[89,92]；高度 2.5 m。
- 实际世界场景仍是 `game/scenes/maps/test_world.tscn`，增加 StaticMap 节点。Camera3D 设置保持原样。
- 多单位先按稳定 ID 分配世界 X 横排；遇到障碍时分别寻找可行走且可达、彼此间隔足够的附近终点，因此回退后可能不保持完全笔直的一排。

## 本次自动检查

以下检查在收尾时重新运行，均退出码 0，没有启动任何客户端：

1. Godot headless 编辑器导入：没有脚本或资源解析错误。
2. 0.1B 纯模拟：归属和目标拒绝、速度、到达、重定向、断线停止。
3. 0.1C 纯模拟：ID 排序、去重、混合归属、非法目标、横排及边界处理。
4. 0.1D 离线测试：导航未就绪、出生点、墙绕行及连续净空、到达停止、途中换命令、障碍目标回退、组落点、地图边界、隔离区域不可达及旧命令保留、碰撞数据和折线虚线表现。
5. 四个 PowerShell 脚本的语法解析；文档写入后运行 `git diff --check`。

此前 0.1D 还通过了仅服务器的 headless 启动检查，使用隔离端口 17779，不连接客户端。本次未重复该联网检查。

环境问题：沙箱内 Godot 输出根证书存储读取失败、user:// 日志写入失败，以及编辑器设置保存权限错误。上述检查仍通过，未出现脚本或资源错误；不能将输出描述为完全无 ERROR。Linux 专用服务器尚未验证。

## 已知限制与待验证事项

- 0.1D 的两个实际客户端路径显示、位置一致性、晚加入和断线行为尚待人工验收；之前 B/C 的验收不能替代 D 的回归验收。
- 当前为平面、静态、轴对齐障碍与 0.5 m 网格；没有动态单位避让，途中单位可以相互穿过；狭窄通道受网格和单位净空限制。
- 障碍内终点只在 2 m 范围寻找替代位置；无法找到路径时保留该单位旧命令。整排无法容纳于地图时拒绝命令。
- 右键目标由地面平面投影获得。验证障碍内目标时应点击墙脚对应地面位置，点击墙上部不一定映射到墙内。
- 断线单位保留并停止，重连获得新 peer 和新单位；尚无重连恢复或生产系统。
- 不添加战斗、动态避障、其他移动模式、控制组或编队朝向。后续功能须另行确定范围。

## 启动与停止（Windows PowerShell）

在 `C:\Projects\RTTGame` 执行同一条快捷命令；只有用户要求客户端测试时才运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath "C:\Dev\Godot\Godot_console.exe"
```

启动器自动定位项目，读取现有 DEFAULT_PORT（当前 UDP 7777），使用项目现有入口：服务器 `--headless -- --server`，客户端无额外角色参数，连接 127.0.0.1。启动前端口占用时输出 PID 和进程信息并停止，不结束其他进程。服务器日志就绪后再启动客户端，并等待连接日志；失败时报告已创建进程及日志。

日志与进程清单保存到启动器打印的 `%TEMP%\RTTGame-local-<时间>-<唯一后缀>\`：`server.log`、`client1.log`、`client2.log`、`session.json`。启动器会打印包含实际路径的完整停止命令。复制该命令；也可在项目根目录执行下面的形式，将占位符替换为本轮打印的完整路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1 -SessionFile "<本轮完整 session.json 路径>"
```

停止脚本核对 PID、创建时间、可执行文件路径，只关闭清单中身份匹配的本轮进程。启动失败后也用该清单清理；不要通过进程名批量终止 Godot。自行额外启动的客户端不在清单中，应自行关闭。

## 下一轮任务及人工验收清单

下一步首先在用户明确要求后进行 0.1D 的一个服务器加两个客户端人工验收，并记录实际结果，再决定下一阶段；不自动提交。

1. 用上述启动命令启动，确认分别有日志且两个客户端看到同样的六个单位。
2. 在客户端 A 框选自己的三个单位，右键墙另一侧地面；两端都观察单位绕过墙，到达停止且不穿墙。虚线路径只在 A 可见；无遮挡终点保持一横排。
3. 在客户端 B 对自己的单位重复操作，核对所属玩家才能选择及命令，路径只在 B 显示。
4. 移动途中更换目标，观察替换旧路径；右键墙脚范围，观察终点落在附近可走地面；地图外命令应拒绝。无法到达保留旧命令已由隔离地图测试覆盖，当前默认地图不包含完全隔离区域。
5. 关闭一个客户端，观察服务器正常且该玩家单位停止；需要晚加入回归时重新启动一个客户端，核对现有单位当前位置与其他客户端一致。额外客户端需手动关闭。
6. 保存并检查三个日志，使用本轮 session.json 停止命令，只关闭本轮测试进程；再次启动前确认占用检测正常。

## 不启动客户端的检查命令

在项目根目录执行：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --editor --import --quit
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd
git diff --check
```

`scripts/test-prototype-01b.ps1` 与 `scripts/test-prototype-01c.ps1` 会启动 headless 客户端，同样需要用户明确要求才能运行，不能与上面的纯模拟检查混淆。

## Git 与文件检查

当前分支 `master`，HEAD `70ab89b`（Add repeatable local multiplayer test launcher）。今天已有基础项目、启动入口、联网、权威生成、选择及基础启动器提交；当前工作区还包含后续移动、框选、寻路、启动器安全增强和本交接记录，均未暂存。

收尾前为 5 个已跟踪文件修改、27 个未跟踪文件；本次新增本记录后为 5 个修改、28 个未跟踪文件。未暂存、未提交、未推送。完整逐文件状态以 `git status --short --untracked-files=all` 为准。

已检查已跟踪文件、工作区文件名及常见私钥/API key 特征：没有发现误加入的 .godot 缓存、导出产物、日志或明显敏感配置。`game/.godot/` 已被忽略；日志目录和 *.log 也有忽略规则，启动器日志位于 TEMP。`.gd.uid` 和 `icon.svg.import` 是应保留的 Godot 源资源身份/导入配置，不是 .godot 缓存。此检查不等同于全面的秘密扫描；没有删除、撤销或修改任何原有文件。

建议提交说明（由用户手动完成）：

```text
Implement Prototype 0.1B–0.1D movement and development handoff

- Add authoritative movement, local box selection and multi-unit orders
- Route units around static obstacles with validated reachable destinations
- Show movement paths only to the owning client
- Guard local test startup and stop only recorded session processes
- Add isolated regression tests and document validation and pending acceptance
```

人工记录：0.1B、0.1C 已由用户确认；0.1D 人工验收待完成。不要在提交说明中写成 0.1D 已人工通过。
