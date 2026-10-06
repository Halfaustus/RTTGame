# Context Handoff：RTTGame 0.5F 弹丸续接

## 接管前先读

本文件为用户明确要求的会话归档，不是新增设计授权。最新指令是停止当前开发、保存上一轮成果并供下一Agent接管。代码已保存于工作树，未提交。**等待用户重新指示继续，不能自行开始下述待办。**

工作目录C:\Projects\RTTGame，PowerShell，Godot 4.7.2：C:\Dev\Godot\Godot_console.exe。依次读取根AGENTS.md、最新docs/constraints/DESIGN_BASELINE.md、docs/records/HANDOFF.md、本文件、正式DATA适配及实际代码。DB当前DB-2026-10-05-33，文件变化时以实际最新DB核对，不用旧阶段说明补设计。

## 有效授权和禁止事项

- 用户恢复0.5并授权继续弹丸系统；不是0.6或伤害阶段。非冻结测试全部使用生成TEST ONLY单位，现有参数类型内表达，不新增单位字段、类别、枚举或schema，不以正式单位未完整为阻塞。
- 用户明确授权自行设计三项C技术细节，上一轮已实现并写PROJECTILE_SIMULATION_C_DESIGN.md及独立AUTONOMOUS_DESIGN_REVIEW.md：未命中生命周期采用地图XZ边界退出；积压采用30Hz顺序整步、回调最多8步且保留债务；旋转／尺寸碰撞采用端点插值和局部保守细分、1毫米空间误差。继续实施不自动触发自主设计复核清单更新。
- 用户回答地面选弹：地面优先高爆；没有高爆时按武器配置顺序选择有库存弹种。已实现。
- 用户回答T范围：本轮也完成T单点炮击最小链，其余T模式后续推进。最小链已有代码和隔离测试。
- 用户最后回答地图：授权增加较大TEST ONLY活动地图配置。**尚未实施，是精确中断点。**保留冻结地图，接入导航和相机边界，使M252最小射程100米可在活动原型实际使用。尺寸／网格／相机参数尚未决定，不把下文候选误认成批准配置。
- 无commit、push、force、rebase、reset、删除分支权限；不得回滚未提交工作、恢复用户删除文件、修改冻结fixture或格式。系统工具的旧批准Git前缀不构成用户提交授权。
- 不启动窗口或无头客户端；默认编辑器导入和独立SceneTree模拟测试。无伤害、防护结算、压制、模块、爆炸、击杀、完整视野、自动选敌、Shift队列、航空或独立编辑器授权。
- 用户此次停止覆盖此前继续指令。此次只改交接文档。

## 工作区与来源

HEAD 9c05b93，最近前两个提交81f46c4、ec3af3f。大量修改未提交；git diff --stat不包含新文件，必须结合git status查看。根AGENTS、DB、自主设计清单的修改是此前工作，不由本次归档新增。

用户已有大量docs阶段文件删除，包括HANDOFF_HISTORY、旧02／03／04记录；不要恢复。BAMS.zip、BAMS汉化版、docs/DataBaseCompiled-resources.assets-15820.json等无关工作保持不动；不要因为缺少先前见过的文件自动重建。docs/RTT_GAME_DATA.xlsx及大量game新文件未跟踪也是已有成果，不能清理。

正式JSON game/data/confirmed/db29.json标签DB29表示数据副本版本，与现行DB33机制不同层。未配置／不适用不当0，不自动开启能力。正式三步兵／三车辆已确认部分保留，但本阶段活动测试不采用正式单位。AT4准备／实际携带、正式编制N、Carl-Gustaf HE初速保持缺项。docs/RTTGame_DESIGN_PRINCIPLES.md和DEVELOPMENT_CONTEXT.md未找到，不编造替代。

## 已完成代码及关系

1. ConfirmedGameData、WeaponDefinition、AmmoDefinition适配正式武器与弹药、穿深曲线、预期伤害选弹。缺项NaN／-1保留，DATA不写入测试值。
2. SquadWeaponChannels在生成时按型号和合法共享定义建立身份，来源slot指向唯一RuntimeWeaponInstance；N取显式分配条数并固定，正式单武器间隔除N仅一次。SoldierState存活变化信号触发缓存候选／占用／依赖关系，局部重算受影响通道，不逐tick扫描接替。
3. GravityBallistics统一g10、1/30秒、低／高抛及移动三次截获。ProjectileUnitMotion由MovementSimulation.advance_sampled共享真实步前后位置／yaw／尺寸，以16米分区过滤，平移解析、旋转尺寸局部保守求交。步内线性端点插值不等于精确瞬时路径转角。
4. DB29ProjectileSimulation统一可复用槽位，真实发射时刻消费、步内残余推进、点碰撞、静态同刻优先、单位稳定ID仲裁，源死亡不取消飞行。查询失败halt整批不丢后续。无固定8秒寿命、弹丸球半径或单弹丸节点。active_spawns提供无Resource的当前状态；事件含重力加速度。
5. FixedStepClock每回调最多8整步，保留全部债务，失败不扣债务。DB29CombatTimeline协调移动采样、瞄准、固定发射和弹丸，共享时钟。
6. 新FiringFrame缓存步前后武器炮口／目标锚点／yaw／运动状态，提供真实发射时刻插值及瞄准／转向完成偏移。友军预检查读取该时刻共享盒体，G绕过预检查但实体碰撞仍有效。AimingSimulation移动禁火时暂停瞄准进度，不因开始移动清零。
7. FixedFireScheduler唯一计时、装填／准备与瞄准并行，actual emission采样姿态、DATA选弹、一次散布、三次移动截获。M252仅已注册T任务高抛，正式射程100–1800米。无frame隔离旧入口仍拒绝运动，实际协调链提供frame。移动源倍率来自已有inputs字典，活动测试1.5明确TEST ONLY。
8. 新ArtillerySimulation拥有活动任务，校验count1／3／-1、地面点、归属、存活、M252及射程，过远时沿现有移动链进入最大射程；选弹缓存、发射预算即时扣减，完成不重复发射、取消不清飞行弹丸。after_emissions只遍历活动任务。高抛解算失败不扣弹。其他T模式未实现。
9. AmmoSelection.ground_selection按用户高爆优先／库存配置顺序。UnitState.armor_direction可接实际采样位置yaw；DirectBallistics.sampled_muzzle复用旧几何偏移，不重新定义正式性能。
10. GeneratedCombatCatalog生成TEST ONLY班组4人（3M4A1+1M249，HP20）和迫击炮3人（1M252，N1，HP15）。正式性能来自DATA。缺项测试瞄准0.1、散布0.15、操作人数缺项1、资格列表／ignore0；M252缺项容量1、装填4秒。临时字段明确标记，未写DATA。保存资源game/data/units/db33_active_test_squad.tres、_mortar.tres由generated_test_*_definition.gd构造，不破坏部署保存资源身份规则。
11. NetworkManager非legacy活动链已用30Hz完整服务器步骤，统一采样／发射／消费／事件。购买及免费出生生成测试单位，追加test.mortar购买卡复用原测试经济参数，未改正式经济。显式legacy_combat_fixture_enabled保留冻结旧60Hz生命／shot测试。
12. NetworkManager ground／T RPC通过现有认证和队列，验证owner、有限坐标及实际map地面；停止／移动取消T。新ground／T命令未追加冻结v1 input语义。新弹丸／发射事件私人投影仍返回空，不擅自暴露敌方状态。client effects／完整新战斗回放尚未完成，不能声称网络播放验收。
13. PresentationFeed对含acceleration的新事件做重力解析插值；旧事件形状保留旧行为。GameWorld已有G／T单点输入、右键确认、Esc菜单、第一次E退出交互、随后E停止；Q／R／F退出该模式。未实现完整T菜单或队列。

## 已改测试及注意

05A／B／C活动断言改为读取生成定义人数／生命／metadata，不再默认8人；三秒步骤数按实际tick_hz维持原持续时间，经济断言未降低。05D旧移动清瞄准断言改为暂停保留，符合DB；历史独立8人等仍标测试fixture。design_review旧ProjectileState注入改为真实DB29发射消费，E不取消已发射弹丸的断言保留。movement_sampling禁移动源预期改为moving_prohibited。02G/H Esc和Q→Esc→E现行预期已纠正。

新db33_active_projectiles_test.gd继承时间链测试helper，目前50项零失败，覆盖实际移动源／目标发射时刻、瞄准步内完成、穿过炮线友军、地面选弹、M252 G拒绝／T最小射程／高抛／预算、40秒以上飞行无旧寿命、NetworkManager活动30Hz债务、资源事件边界、输入交互及表现重力插值。

**当前该测试手动用较大局部MovementSimulation替换network._movement**，范围(-200,-200)至(200,200)、网格5米，证明代码链而不是活动场景地图可用。source(20,0.5,100)、T点(20,0,-50)。完成独立地图后应改为实际新活动配置，新增导航／相机／消费者一致及冻结地图边界测试，不能继续用局部替代宣称场景完成。

## 真实中断点与恢复顺序（待重新授权）

1. 已读prototype_movement.tres：XZ(-20,80)至(60,120)，80×40米、ground0、navcell0.5、speed4、spawn(-3,0.5,100)。旧地图必须保留。
2. 已读test_world.tscn：GameWorld、StaticMap的test_map_geometry.gd、Units下LocalCamera。下一步读取场景入口及地图几何构造、LocalCamera完整边界实现、ReplayContent指纹清单、冻结03测试的legacy初始化时序。
3. CameraConfig现有移动／旋转／zoom／pitch／ground字段，未见XZ边界字段；不能臆测已经支持边界。可优先复用MovementConfig做运行时地图配置绑定，严格不新增单位schema。GameWorld和NetworkManager多处仍直接引用旧MOVEMENT_CONFIG，部署initialize也用它；需要最小一致改造。消费者目前正确取network._movement._config边界，不能独立改消费者造成导航／表现不一致。
4. 选择独立TEST ONLY较大地图及既有配置资源；旧test_world及冻结资源避免编辑。独立active scene或运行时显式配置选择尚未决定，必须调查入口／replay模式选择后实施。800×600米等只是讨论候选，**不是已配置或确认值**。注意大地图网格成本，不照搬0.5米造成巨大导航格。
5. 审核GameWorld焦点／部署切换是否清空新增_fire_mode，当前尚未专门验证。DB29CombatTimeline顶部仍说迁移待办、拒绝移动目标等过时注释；设计文档和DB33_IMPLEMENTATION_REVIEW也待更新。当前HANDOFF已归档纠正状态，其他文件本次不改。
6. 对修改跑新活动专项、相关05D/E/F、输入及05A/B/C购买出生回归、03A/B/C冻结兼容等；最终编辑器导入、diff-check、hash核对，按实际证据更新记录。不得为了通过修改冻结夹具。
7. 完成本轮范围即交付停止，其他T模式、伤害阶段等不得自动推进。

## 已保存验证证据

目录tmp/db33-active-projectiles/，归档实际读取以下*-final.log结论；本次未重跑：

|脚本（不含_test.gd后缀）|实际结果|
|---|---|
|db33_active_projectiles|50项，0失败|
|db29_combat_timeline／db29_projectile|53／41项，0失败|
|gravity_ballistics／projectile_unit_motion／movement_sampling|50／43／52项，0失败|
|db33_projectile_c_design／db33_current_performance／db33_operator_events|21／53／20项，0失败|
|confirmed_game_data／squad_weapon_channels|55／72项，0失败|
|design_review|49项，0失败|
|prototype_05a／05b／05c／05d／05e／05f|39／52／59／108／76／61项，0失败|
|prototype_04a／04b／04c／04d|49／47／84／32项，0失败|
|prototype_03a／03b／03c|PASS|
|prototype_02g／02h／command_input|PASS|

28个脚本最终日志保存，但部分最新小修在批量运行之后；恢复后必要回归按最终改动再核实，不能把所有日志视为同一最终树的完整证明。日志中已有user日志写入／root certificate沙箱环境ERROR，03B预期拒绝注入错误应与失败区分；仍检查SCRIPT ERROR和断言失败，不能仅依赖退出码。

当前import-trial.log最后为无法保存用户目录editor_settings-4.7.tres；**最终编辑器验证未完成**。前轮tmp/db33-projectile-completion/import-c.log成功仅证明前轮。恢复后若重要导入因沙箱失败，按工具权限流程require_escalated重试，不启动客户端。

独立测试命令范式：PowerShell调用 & C:\Dev\Godot\Godot_console.exe --headless --path game --script res://tests/db33_active_projectiles_test.gd，日志重定向至tmp相应目录；导入用--headless --path game --editor --quit。自动测试不是客户端人工验收。

归档git diff --check退出0（换行提示）。DB／DATA／fixture归档再次核对SHA256：

- DB：99998341B7D0EE136E5878323514B78A47BE4DE04AC403021EF695C7F40C70BC。
- JSON：B66FBFFECD48EF6DC48085BDAF58377D61D9BAB07917643456F27DA4E5A2F54D。
- replay_v1.json：F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。
- Excel前轮读取SHA256：4E794F4CB3BFAFD4214C3D012EB4EC2044A7CB426EECE6FA3CFBD0B625A70598；此次未重算。若Excel占用，用允许共享的读取方式核实，别修改文件。

## 尚未验收

较大活动地图、当前最终编辑器导入与完整活动链交付未完成。0.5E/F人工复核、0.5大版本、0.4统一验收、0.3C人工播放、ENet/Linux、长期压力、完整新战斗录制播放均未验收。Replay仅冻结v1兼容保留，不升级格式。客户端私有投影不能因用户要求弹丸完成就默认为可公开。无提交、推送或客户端启动。

本会话归档只更新本文件及HANDOFF；既有实现完整留在工作树，下一Agent以实际代码和最新DB再次核实，遵守当前停止状态。
