# GreyLine Taskforce / 灰线战术群 当前交接

正式名称已由用户确定为 GreyLine Taskforce / 灰线战术群，内部代号 GREYLINE / 灰线。Godot 项目显示名采用 GreyLine Taskforce；仓库地址、资源 UID、DATA 与规则标识及回放契约保留。命名约定见[PROJECT_NAMING.md](../PROJECT_NAMING.md)。此次品牌更新不改变以下阶段授权与验收状态。

## 当前状态与授权

现行基线：[DB-2026-10-06-40](../constraints/DESIGN_BASELINE.md)。正文按局外与局内系统拆分，入口列出的模块共同组成基线，原章号保留。用户已确认完成0.5F验证并保存至GitHub；0.5G按距离选速已由用户确认通过；用户已确认本轮清单全部通过：开火停止后的路线清理、兵牌缩放、G红线／距离、左／右键确认分工、T开火与双端表现。当前授权保存并上传GitHub，随后仅进行0.6开发准备，不自动开展伤害等实现。

用户明确授权0.5G：按距离选速，非直射弹药DATA不记录固定初速，M252全有效射程落弹飞行时间控制在20秒内，为后续火炮保留实现参考。本轮另获明确授权修复移动指示线、兵牌视角缩放、G红线／距离预览和指令确认键位；不开发伤害、压制、其他T模式或Replay v2，不改g10、射程或公开隐私。0.5F已保存的提交为751b748；当前0.5G及已完成P0／P1配置守卫获用户授权保存并推送；以实际Git结果确认上传状态。无新增清单维护授权，不更新AUTONOMOUS_DESIGN_REVIEW.md。来源用途未确认的外部JSON及工作区其他配置校验改动保留，不归为本轮弹道实现。

用户已确认25分钟标准任务、四阶段、生存性目标、8分钟弹药窗口及无经验成长，集中在[第25节](../constraints/design/MATCH_MISSION.md#section-25)。规则未接入任务计时或完整战斗结果；下一设计工作优先细化步兵班减员模型。PVP为长期愿景，不是当前阻塞项。

## 配置守卫：P0／P1 当前结果与边界

用户已明确授权推进P1（A01／A02／A09／A13），现已完成本轮最小实现及自动验证；已实现的P0守卫继续保留。实际读取并遵守DB-2026-10-06-40及相关正文。当前不授权P2／P3或0.6实现，不启动客户端；本次用户另行授权保存与GitHub上传，不改变该实现边界。并行0.5G复检、界面及其他会话改动保持各自范围；不更新自主设计复核清单。

- A07／A10：统一实际安装占用守卫与射速一致性守卫保持；同槽冲突在运行武器创建前拒绝。单武器间隔＝消耗数×60/rpm，固定N由运行通道再除一次；AT4／Carl-Gustaf准备式豁免，机械装填不豁免。1e-9秒绝对＋1e-9相对容差仅容纳浮点计算。
- A12：TEST／PARTIAL／COMPLETE统一入口及部署接入保持。分别报告结构、局部瞄准测试、现有战斗静态契约、正式目录与完整战斗资格，不给旧fixture补无关字段。DB40间接弹药不要求固定初速，化学弹药不要求动能距离锚点。
- A01：ConfirmedGameData.initial_inventory_for_weapon成为活动链唯一DATA初始库存读取入口。Ammo.Initial_Inventory_rounds→allocation.initial_inventory→独立安装库存／合并通道；Weapons库存列仅保留追溯，不累加、不回退读取。GeneratedCombatCatalog和Prototype05DCatalog均使用同一入口。未配置、不适用、真实零分别报告；缺少Ammo关联不当作完整零库存。运行初始化复制allocation，初始待发不增加库存。
- A02：WeaponAmmoCompatibility显式表达武器ID／弹药ID关系及数组择弹顺序，默认从现有Ammo.Weapon_ID派生，现有14条Ammo性能记录不迁移或复制。configure_compatibility事务式替换内存关系，可接收JSON数组；未知引用、重复对、库存／性能覆盖字段明确拒绝。新增兼容不自动授予弹药，复用弹药须由具体配置明确选择库存。相同Ammo_ID仍取同一源记录，保持现有每次物化Resource的可修改隔离，未引入共享可变缓存。资格、费用、库存和性能不放入兼容关系；未建立正式多武器持久化表或阵营可用性系统。
- A09：按通道且逐弹种检查sum(source_remaining)==channel_remaining；pending／loaded包含在库存内，已发／在途弹丸已经扣库存，不另加。初始化、伤亡与岗位恢复在事件重算／待发夹取完成后检查；扣减沿用原来源顺序，来源额度不足显式报错并标记inventory_accounting_invalid。完整发射边界可调用inventory_issues／all_inventory_issues；中间扣减阶段不拿旧pending误判（check_pending=false）。没有每Tick扫描、第三库存权威、自动修正或额外扣弹；纯性能测试通过。
- A13：ConfirmedDataValidator在加载前检查来源标识、固定导出源哈希、可获得的实际工作簿哈希、必需表／列、所有稳定ID唯一性、Ammo→Weapon及必需Parameter引用、库存值及版本。拒绝后不发布部分records，提供字段路径／错误码／重复引用路径。JSON头新增data_schema_version=1、data_version=RTT_GAME_DATA-2026-10-06-40、rules_id=DB-2026-10-06-40；baseline_id保留并须与rules_id一致。结构版本、数据修订与规则版本分开，不沿用Replay指纹机制。旧无元数据导出及未知版本明确拒绝，不静默迁移。部署包不含工作簿时只验证固定源哈希元数据，有工作簿时再核验真实文件；此校验不声称逐单元格比对整个工作簿，也不证明单位完整合法。

A12实质未闭环：现有Schema仍不能完整表达／验证基体与配置身份引用、观察、重量／运输及能力资格，完整伤害等系统也未齐。因此完整现有战斗静态契约可通过，但COMPLETE正式认证继续返回unsupported_rule_coverage，full_combat_ready为false。P1通过未解除正式目录阻断，不得通过删阻断、补默认值或换来源标签声明全基线合法。后续模型补足与正式复用关系确认须有对应授权，不自行推进。

本轮实际验证：Godot 4.7.2无界面编辑器导入；P1新增86项、DATA55、P0 59、通道72、设计49、固定战斗53、活动弹丸60、当前性能53、05G5125、05E76、05F61全部零失败；冻结Replay 03A／03B／03C通过，共14组。日志及前后保护哈希在tmp/combat-contract-p1；退出码与脚本编译／运行错误一并检查，预期拒绝输出单独识别。git diff --check通过；自动结果不替代人工验收。

保护与兼容：去除新增的三个头部元数据后，JSON字节SHA256精确恢复本轮开始值C45BBB837C4BBC0E0EEF179E3DBB6C078A60800AB335221E9565F027ED10C55A，证明所有表值／ID及既有导出正文未改。Workbook SHA256仍为0113889F5046869610F5195D7751A31A76D4417C208BD9019C25D9892D8C9AC0；冻结v1仍为F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。现有合法库存、扣减顺序、弹丸性能、Replay结构保持；新增不合法DATA／关联／会计状态的诊断与拒绝。并行0.5G的先前DATA初速改动不归为P1。

P1实际修改：game/data/confirmed/db29.json（仅上述元数据）；game/scripts/combat/confirmed_game_data.gd、generated_combat_catalog.gd、prototype_05d_catalog.gd、squad_weapon_channels.gd；新增confirmed_data_validator.gd、weapon_ammo_compatibility.gd；新增game/tests/p1_schema_contracts_test.gd及对应Godot UID；本HANDOFF。P0源码及其他会话改动保留。本轮没有整体Schema重构、正式多武器DATA迁移或新增游戏机制。

## 当前实现

- 活动链已有固定30Hz时钟、弹丸池、发射时解算／一次散布、路径与移动碰撞、实际事件时间及C类工程边界。性能读正式DATA，非冻结活动单位／地图仍为TEST ONLY。完整伤害、防护结算、压制、模块、爆炸和击杀闭环未完成。
- G地面强制攻击已有每通道单次发射及未发射取消；G／T均有本地红色名义弹道与距离预览，只读己方私有武器快照、不预测命中。G／T左键确认，移动及Q／F／R右键确认，E退出选点；火力选点期间右键不发送开火或移动。接受开火后复用既有可靠停止消息清理旧路线，T需接近时按停止→新目标→新路线顺序发布。其余T模式、完整任务菜单、Shift队列、视野／自动选敌未完成。
- 公开弹丸向已绑定客户端发送白名单运动／终止，不公开来源、命中身份或单位私有状态。客户端已有插值、渐隐曳光、历史裁剪、晚加入保守处理与终止清理。参数和数据流在[表现说明](PROJECTILE_PRESENTATION_REVIEW.md)维护，协议见[公开载荷契约](../constraints/PROJECTILE_VISIBILITY_CONTRACT.md)。
- 极短尾迹裁剪与独立TEST ONLY相机修复已有自动证据；活动相机现对在场／已放置订单兵牌启用有下限的视角缩放，旧相机及冻结Replay保持原尺寸。临时客户端参数：marker_reference_distance=60米，minimum_marker_scale=0.6，缩放为clamp(sqrt(60/max(视距,60)),0.6,1)；用于减少高空遮挡并保留低空可读性，可按观感调整，不是正式DATA。修改文件、相机值和测量条件见[DB37复检](DB37_MANUAL_RECHECK.md)。
- M252已按散布后落点的距离／高度生成权威初速度，复用同一高抛矢量解和30Hz弹丸池。DATA仅将Ammo!I15由810 km/h改为“不适用”，同步JSON版本与源哈希；其余记录不变。现有11个真实T／FiringFrame／碰撞链测量100～1800米实际落弹4.64～19.73秒；活动地图不能容纳远距离，500米以上夹具仅内存扩展边界，不算真实客户端验收。20秒是发射策略边界，不是弹丸寿命或客户端播放时间。参考见[0.5G实现](PROTOTYPE_05G.md)。
- 冻结旧地图Replay v1仍有支持基础；新活动地图完整录制／播放不支持，当前Demo不开发Replay v2。未来架构要求见[弹丸正文](../constraints/design/PROJECTILES.md#section-18)。

## 验证与未完成验收

本轮指令／视觉修复13个相关脚本最终全部通过：输入33、客户端专项102、活动相机30、投影42、渲染67、裁剪39、05G5125、05F61、05C59、设计49项均零失败，冻结03A/B/C通过；日志tmp/05g-command-visuals，编辑器导入无脚本／解析错误，git diff --check通过，冻结v1哈希未变。按距离选速另有真实M252链104项、时间轴53、活动弹丸60及正式DATA55项通过。另运行工作区已有P0配置校验59项通过，仅说明共存检查，不归为本轮实现。日志为tmp/05g；编辑器导入与git diff --check通过。工作簿归档内容逐项比较，仅Ammo!I15改变；JSON仅该值／版本／源哈希改变。冻结v1哈希未变。

0.5F与0.5G按距离选速人工验证已由用户确认通过；本轮清单内的低速曳光亮度／长度、兵牌缩放、G预览、新键位、路线清理及双端表现已由用户人工确认全部通过。该确认不扩展为0.5E、0.5与0.4整体人工验收或旧0.3C播放通过。设备FPS专项、丢包／抖动、Linux、长期带宽／网格性能及终止ID长期容量等未单独提供证据的范围保持未验证。

## 限制与下一步

P01工程边界、P02移动瞄准、P03 APS口径集中在[第22节](../constraints/design/PENDING_DECISIONS.md#section-22)。保留有效条款与工程授权，不借合并裁决行为或回退代码。DATA缺项包括AT4准备／携带量、正式编制N与Carl-Gustaf HE初速；测试配置不能补成正式值。

当前下一步保存验收成果后进行0.6开发准备，核对结算接口、时序／去重、状态隐私及步兵减员前置设计；不重置已确认通过的0.5G弹道验收。低速公开运动≤200m/s采用80ms亮段／60ms淡尾、亮段下限2米、半宽0.07米及浅黄色；高速原参数保持，所有尾迹仍裁剪真实已知历史。相关10脚本最终通过，渲染67、裁剪39、05G5125项零失败，编辑器导入及diff检查通过，日志tmp/05g-readability。隔离微基准连续选速中位0.97191µs／次，旧固定解1.19446µs、参考十档1.23983µs；无需简化，详细范围与误差见05G记录。当前只授权0.6准备，不授权0.6战斗代码实现。后续火炮复用本轮选速方法前，必须核对射程、高度、散布和时间约束的物理可行性，不自动推广20秒承诺。未来版本次序和门槛只在[开发规划](../DEVELOPMENT_ROADMAP.md)维护。以后复检命令与项目参考直接回复用户，不新建或更新复检步骤文档。

`RTTGame_DESIGN_PRINCIPLES.md`与`DEVELOPMENT_CONTEXT.md`仍未找到，不重建内容或授权；旧CONTEXT_HANDOFF的暂停／地图未实现状态不替代本交接。历史阶段与自主复核清单保留各自时点与来源，不作为现行状态副本。
