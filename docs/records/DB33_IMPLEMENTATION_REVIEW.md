# DB33历史预期与接替约束落实

实际依据：DB-2026-10-05-33，SHA256 99998341B7D0EE136E5878323514B78A47BE4DE04AC403021EF695C7F40C70BC。用户本轮授权纠正历史预期、实现明确约束，并全部使用生成的非冻结测试单位；不新增单位参数类型，不补未决设计，不进行伤害阶段、0.6或Git提交。

## 历史预期的处理

- 02G改为Esc打开菜单且保留右键交互，释放后正常提交；新增菜单可见和无提前命令断言，保留释放结束检查。
- 02H分开验证Q→Esc仍保持交互、第一次E只退出、第二次非交互E停止；不恢复旧Esc取消规则。
- 05E移除60秒advance最多一发作为当前要求的断言，替换为当前时刻就绪发射原子扣弹及零dt不得绕过间隔；固定步多发仍由49项时间轴专项验证。没有定义积压策略。
- 05A/B人数断言改标TEST ONLY；02C的“S stop”标签改为接口stop，不改变快捷键。
- 05D/E/F仍执行原有效接口回归，其旧数值、球体、常速、寿命是明确标记的legacy fixture。五份05A/B/D/E/F阶段记录前置现行来源说明，保留原文供追溯，旧“正式”声明不能覆盖DATA。当前性能验收改由DATA适配专项与新实际发射专项负责，未删除旧覆盖或跳过套件。
- 新53项当前性能专项验证生成单位实际运行M4A1、M249、车载M249、M242、Mk44；单武器间隔、容量、装填直接读DATA，测试实际选中弹药、初速、原子扣弹和第二次实际时刻。步枪P0=9/500mP6、MP7参数及独立Ammo关联也验证；旧1.5秒/旧机炮数值不是现行验收。
- AT4正式容量、准备时间继续空缺；共享活动防守测试配置不补旧5具库存，不生成未配置发射器。旧隔离火箭fixture仅解释旧接口行为，不作为当前AT4性能。正式单位不生成；正式DATA记录存在性/缺项测试只是读取，不等同生成正式单位。

## 接替实现

SoldierState.health现有属性在存活状态跨越时发出内部living_changed信号。普通非致死生命变化和重复赋值不发事件。SquadWeaponChannels生成时建立稳定优先级索引、每岗位有序候选、当前槽位占用、候选依赖及携弹来源索引。阵亡仅通知当前操作/原岗位，补员通知缓存依赖；槽位变化沿依赖队列更新关联岗位。队列只处理稳定整数索引，不在战斗中重新比较/排序配置。

无事件时没有人员扫描或接替计算；从AimingSimulation、FireSimulation及FixedFireScheduler删除持续刷新调用。原refresh接口保留为空的兼容入口，已有直接health赋值也能正确触发，不要求调用方额外扫描。事件仅汇总实际受影响的型号通道，N、计时、来源身份不重建。配置整体替换沿已有UnitState.configure重建该配置，先断开旧成员信号；没有新增局内任意换装或配置补全接口。

20项专项直接检查计数：1000空闲调用、实际瞄准/两种射击更新不增加工作；普通步枪阵亡只更新一个通道；机枪接替占用主槽时只连带更新步枪，独立副槽不更新；补员只更新关联两通道。另验证最低操作人数、候选缓存不重建、计时及N保留、弹药不补回、旧配置成员事件不能污染新配置。旧72项功能回归同时通过。

新增信号、索引、队列和profile是运行时实现状态，不是单位参数。UnitDefinition、WeaponAllocation及其他配置定义本轮没有新增export字段、枚举、类别或schema；不修改DATA、网络/Replay格式。非冻结测试使用现有生成原型/新生成fixture；冻结v1独立保留。

## 测试前提及未决冻结

新测试使用4人混合主/副槽、2人M2操作班、单通道步兵/车载安装。生命按现有步兵规则，车辆测试10生命；配置身份均test_only。武器性能来自DATA；仅在资格缺项局部使用操作人数1、瞄准0.1秒、静止开火资格、步兵目标、减伤无视0、精确路径散布0。这些不是生产默认、正式配置或平衡设计，未创建新的参数类型。具体授权及决定已补入AUTONOMOUS_DESIGN_REVIEW，等待人工复核。

继续冻结：AT4准备与单位携带量、正式编制/N、未明确的推进/制导表达、散布及资格。用户随后明确将积压、未命中生命周期及旋转／尺寸变化三项授权为C类自主技术设计，已实现，来源及规则见[PROJECTILE_SIMULATION_C_DESIGN.md](../constraints/PROJECTILE_SIMULATION_C_DESIGN.md)。不把统一g=10、30Hz、点检测、合法步内多发和DATA已确认参数归为未决。

活动NetworkManager非legacy链已接入30Hz重力点检测、共享平移／旋转／尺寸变化、8步回调预算、显式地图XZ退出及FiringFrame实际发射时刻采样。活动地图采用独立TEST ONLY配置，真实地图上的T最小链已自动验证；客户端弹丸公开投影已按DB34契约实现，真实ENet双端效果尚未验收；完整新战斗回放仍未交付。当前最新结果以HANDOFF及tmp/db33-active-map为准，下表仅为历史预期纠正轮证据。

## 实际验证

日志：tmp/db33-corrections/*-final.log。

|套件|结果|
|---|---|
|db33_operator_events / db33_current_performance|20 / 53项，零失败|
|squad_weapon_channels / confirmed_game_data|72 / 55项，零失败|
|05A/B/C/D/E/F|39 / 52 / 59 / 108 / 76 / 61项，零失败；D/E/F旧fixture非当前机制验收|
|gravity / db29_projectile / db29_timeline / unit_motion / movement_sampling|50 / 39 / 49 / 42 / 47项，零失败|
|04A/B/C/D|49 / 47 / 84 / 32项，零失败|
|movement_performance / design_review|99 / 48项，零失败|
|02C/G/H、command_input|PASS，不输出独立总数|
|03A/B/C冻结回放|PASS；读取/拒绝/round-trip/checkpoint/event及表现边界保留|
|编辑器导入/脚本解析|import-final.log，退出0，无Parse/SCRIPT ERROR|

独立测试有既有user日志写入/根证书环境ERROR；03B拒绝注入有预期REPLAY FAILED，不是失败断言。试验日志保留，早期解析、fixture共享定义及缺移动资格修正不作为通过证据。编辑器首次沙箱不能保存设置，按权限机制重新导入通过。

冻结v1 SHA256仍F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15；Excel仍4E794F4CB3BFAFD4214C3D012EB4EC2044A7CB426EECE6FA3CFBD0B625A70598，JSON仍B66FBFFECD48EF6DC48085BDAF58377D61D9BAB07917643456F27DA4E5A2F54D。没有客户端/人工验收、独立编辑器修改或Git commit/push。完整0.5及旧未完成人工验收仍未通过。
