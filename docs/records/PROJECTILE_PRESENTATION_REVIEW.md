# 弹丸表现实现审查

所属现行基线：[DB-2026-10-06-39](../constraints/DESIGN_BASELINE.md)；下列实现与测量保留各自原轮证据。本轮依据用户明确的解耦、插值和客户端故障修复要求；未扩大自主设计授权，未更新其人工审查清单。下列数字为集中客户端实现参数，非正式武器／战斗数值。服务端正式 DATA 与冻结回放未改。

## 实现前审计

1. `DB29ProjectileSimulation.step()` 是唯一权威弹丸固定步入口，`FixedStepClock` 保留时间债务并调用它；固定频率由 `GravityBallistics.STEP_SECONDS=1/30` 定义。
2. 服务器槽位 `state.position` 等价 simulation_position，用于重力运动、路径碰撞、终止；900 m/s 的水平首步仍移动30米。没有客户端节点参与这些计算。
3. `ProjectileProjection.spawn()` 白名单中的 position 是 network_position，来自生成事件或当前活动状态；time_seconds 是同一权威模拟时钟。封套 authority_time 也来自该时钟。
4. 原 `ProjectileVisuals` 没有独立视觉对象位置缓冲；用 `PresentationFeed.projectile_position()` 从生成状态解析重力运动，并把最近一个模拟步的两个解析位置画成网格。因此30米不是额外弹速错误，而是把步位移当成曳光长度。共享 Feed 是表现接口，未参与权威战斗；网格只在客户端活动场景创建。
5. 已有逐渲染帧解析运动和有界时钟外推，但没有两份网络快照插值，也没有延迟渲染时间；原时间锚到达会推进显示时钟。最小复用点是 Feed 与现有单个 ImmediateMesh，无需重写战斗框架。
6. 晚加入原本发送 `active_spawns()` 当前状态，不补历史。终止信号先通知表现，再移除活动状态；初始化／断线 reset 清理，结束ID阻止重播复活。保留这些契约。

## 当前数据流

服务器 state.position → 白名单 snapshot.position → 每ID ProjectileSnapshotBuffer → visual_position → 黄色渐隐网格。三个位置可能在某时刻数值相等，但职责与存储分离；不存在视觉结果写回服务器的路径。

公开RPC名称、权限、字段、ID与终止语义不变。生成数组现在也携带每个完成模拟步的活动状态，故正常具备相邻权威快照；同批新生成与当前状态按逐ID时间比较去重接收。实时活动快照调用 `active_spawns(false)`，不为每个广播步排序全部活动弹丸；默认有序接口与晚加入顺序保持。增加发送频率中的载荷量，未做带宽／长期压力验收。

每弹丸缓冲最多8份不可变网络快照，拒绝旧／重复时间。Feed已有服务器时钟复用为 estimated_server_time：首锚初始化，其后按 render delta 连续推进，落后时以指数方式小幅追赶，不在每包到达时覆盖视觉位置。无RTT估计／通用抗抖动系统。

render_time = estimated_server_time - interpolation_delay。默认 delay=0.05秒，约30Hz的1.5个快照间隔，可按客户端配置调整。两快照之间 position=lerp(P0,P1,alpha)，velocity也插值；早于第一快照则保持第一位置，适用于新发射与晚加入。超过最后快照则用已有速度／加速度解析外推，最多0.05秒，之后固定在预测上限。显示时钟自身也受“插值延迟＋0.05秒”的上限约束；不是服务器步长。

正常插值直接生成连续位置。外推后收到新状态时，保留预测误差偏移，按0.05秒时间常数指数衰减；误差超过30米则直接服从新状态。三个参数均为客户端稳定性实现值，需真实网络视觉验证。重复包不重新初始化缓冲。每个 render frame 更新 visual_position；不依赖30Hz网格重绘。

服务器终止立即清空活动状态和缓冲，停止外推，不延迟权威结果。用实际终止位置与该时刻速度生成0.12秒渐隐尾迹；这是终止后的视觉余辉，不是额外飞行寿命。重复终止不重复生成尾迹，reset清理所有余辉。

## 曳光参数

集中在 ProjectileVisuals：

|参数|默认值|用途与依据|
|---|---|---|
|tracer_visual_time|0.012秒|用户建议窗口内，900m/s亮段10.8米|
|tracer_min_length|0.2米|小型视觉下限，仅可读性|
|tracer_max_length|15米|主要亮段上限|
|tracer_fade_time|0.012秒|额外淡尾按速度缩放|
|tracer_fade_max_length|15米|淡尾上限，总长最多30米|
|tracer_alpha|1|弹头基础透明度|
|FADE_SEGMENTS|8|共享网格顶点渐变最小实现|
|HALF_WIDTH|0.035米|沿用既有视觉宽度，不是碰撞半径|
|TERMINAL_FLASH_SECONDS|0.12秒|短程同批终止仍可观察，按时间衰减|

bright=clamp(speed×visual_time,min,max)，fade=clamp(speed×fade_time,0,fade_max)，total=bright+fade。900m/s默认10.8米主要亮段＋10.8米淡尾；head alpha=1，亮段结束约0.5，淡尾二次衰减至0。head=visual_position；上述total只是配置上限。实际网格沿最多8份已有快照的历史折线后退，用客户端已知路径预算裁剪，不越过首次已知状态；首次出膛帧为零长度，同批终止使用实际终止位置到已有历史的范围。晚加入保守从首次收到的当前状态开始，不猜测源单位或原炮口。曲线不替换成一根全程直线，终止余辉仍0.12秒。改变采样频率不会改变公式；速度变化仍合理影响长度。未增加Glow／Bloom或屏幕空间放大。初始参数建议先保持，人工复验可读性后再调整。

## 其他已授权修复及接口

G对地面命令绑定每武器通道一个实际发射预算，发射时扣减并清目标；移动／停止取消待发，不改变已经生成弹丸。预算可通过运行时值快照表达；不改变射速、库存、瞄准或散布。当前客户端G走地面选点入口，非完整单位目标强制攻击菜单。

T选点使用客户端 ArtilleryPreview，读取己方原私有武器状态与正式DATA，复用无随机名义高抛解算，绘制128段红色实线及距离／射程文字。预览不采样散布、不判断命中。半宽0.05米为临时表现参数；高弧多数可能超出地面相机视域。增加 `weapon_position`、`muzzle_position` 到原拥有者私有武器状态，供位置准确预览；并未增加公开弹丸字段或向其他玩家复制私有武器信息。

镜头旋转事件在GUI消费前接收，捕获期间不因悬停或焦点控件被每帧取消；Alt／中键独立保持，失焦与释放恢复控制。两窗口实际输入故障是否完全消除仍待人工验证。

本地归属颜色基于稳定 player_id 与 viewer_player_id，己方蓝色（0.2,0.6,1），其他玩家绿色（0.3,0.85,0.4）；世界模型、兵牌与己方订单一致，敌方team表现及离线冻结旧配色保留。当前规则见[兵牌正文](../constraints/design/UI_INPUT.md#section-14)，扩展检查／待办只在[玩家扩展记录](PLAYER_EXTENSIBILITY_REVIEW.md)维护。

## 验证与限制

证据在 tmp/db36-client-fixes：projectile_render_separation-final.log专项58项、client_acceptance_fixes-final.log 92项、projectile_projection-final.log 42项、db33_active_projectiles-final.log 60项、db29_combat_timeline-final.log 53项、db29_projectile-final.log 41项、design_review-final.log 49项、prototype_05f-final.log 61项均零失败；command_input与冻结03A/B/C通过。本轮相关05A/B/C/D/E及02G/H回归通过，详见该目录日志。

渲染专项验证实际服务器900m/s首步30米，给定0→30的插值，中间位置和30/60/120/144FPS，20/30/60Hz采样下视觉长度一致，速度上限、透明度曲线、有界外推、纠正、终止优先、重复安全、断线清理与三玩家白名单投影。20/60Hz为客户端采样夹具，没有改正式服务器频率。改变客户端FPS和视觉参数，实际服务器轨迹、终止时刻、碰撞对象和生命周期事件完全一致。当前活动系统尚无完整伤害结算，不能声称对未实现伤害进行数值验收；客户端没有新增伤害入口。

Replay v1读取、验证、round-trip、checkpoint/event边界与离线表现保留；未知版本拒绝不变。新活动地图完整录制／播放不支持。本次不保存视觉帧，未来权威回放可复用缓冲及表现，不依赖原客户端FPS；公开裁剪载荷仍不等于完整战斗回放数据。

真实ENet双端、不同设备FPS、抖动／丢包、远距离可读性、Linux和长期带宽／性能未验证；自动测试不是人工通过。人工步骤与精确启停指令见CLIENT_PROJECTILE_ACCEPTANCE.md。

## 相关实现文件（并非全部为本轮修改）

- 渲染／插值：game/scripts/core/projectile_visuals.gd、projectile_snapshot_buffer.gd、presentation_feed.gd。
- 权威快照发送：game/scripts/networking/network_manager.gd；game/scripts/combat/db29_projectile_simulation.gd仅增加可跳过快照排序的只读选项，原默认行为保留。
- G单次预算：game/scripts/combat/runtime_weapon_instance.gd、fixed_fire_scheduler.gd；network_manager.gd中的命令绑定／取消。
- 预览：game/scripts/core/artillery_preview.gd、game_world.gd；game/scripts/combat/ammo_selection.gd的纯数据复用入口，runtime_weapon_instance.gd中的拥有者位置快照。
- 镜头与配色：game/scripts/core/local_camera.gd；game/scripts/ui/unit_marker.gd、unit_marker_style.gd；game/scripts/units/unit.gd；game/scripts/deployment/deployment_ui.gd；game_world.gd的本地归属刷新。
- 自动测试：game/tests/projectile_render_separation_test.gd、client_acceptance_fixes_test.gd、projectile_projection_test.gd。
- 当前文档：docs/constraints/DESIGN_BASELINE.md、HANDOFF.md、PROJECTILE_VISIBILITY_CONTRACT.md、PROJECTILE_PRESENTATION_REVIEW.md、PLAYER_EXTENSIBILITY_REVIEW.md、CLIENT_PROJECTILE_ACCEPTANCE.md。

新脚本对应.gd.uid由Godot导入建立。清单不把既有未提交工作归入本轮。解耦实现的19个隔离脚本全部退出0，本轮复检结果见DB37_MANUAL_RECHECK.md；编辑器import-final.log退出0，无ERROR／Parse／SCRIPT ERROR。隔离测试日志的证书环境ERROR与03B预期录制拒绝，不是失败断言。git diff --check通过（既有换行提示除外）。正式JSON SHA256 B66FBFFECD48EF6DC48085BDAF58377D61D9BAB07917643456F27DA4E5A2F54D，冻结replay_v1.json SHA256 F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15，均与修改前一致。
当前人工复检修复、M252实测、独立相机配置与最新验证以[DB37_MANUAL_RECHECK.md](DB37_MANUAL_RECHECK.md)为准；本文保留其他现行表现说明。
