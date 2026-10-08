# GreyLine Taskforce / 灰线战术群 当前交接

正式名称GreyLine Taskforce / 灰线战术群，内部代号GREYLINE / 灰线；仓库、资源路径／UID、类名及协议标识保持。见[命名约定](../PROJECT_NAMING.md)。

## 当前授权与实现

现行基线[DB-2026-10-08-45](../constraints/DESIGN_BASELINE.md)及其列出的正文为唯一游戏规则入口；正式实例DATA为docs/RTT_GAME_DATA.xlsx。RTTGame_DESIGN_PRINCIPLES.md未找到，不重建。来源与缺配置见[DATA provenance](../DATA_PROVENANCE.md)，临时配置见[DEVELOPMENT_CONTEXT](../DEVELOPMENT_CONTEXT.md)。

用户已授权正式推进0.7局内UI，并指定命令队列为0.7D、出生后常规／快速移动移入Esc设置。0.7A～D已有能力基础自动验收完成，整版未完成／未接受。窗口缩放此前已由用户人工确认；用户现已人工验收028／029本轮功能。030完成测试提示UI隔离及初版折叠菜单工程交付；其后031实现的全员KD／overview、个人击杀／被击杀及其余菜单功能也已由用户人工验收。最后两项修正为Esc在任一菜单页关闭并恢复游戏输入、所有菜单页底部居中加大“返回游戏”按钮；两项修正实现、import与独立增量审查PASS，用户已于2026-10-09确认通过。T／Y统一左键确认，兵牌从权威位置派生且不绑定模型；活动步兵无模型，装甲矩形指示保留。既有临时兵牌许可不是新的自主设计授权，不自动更新自主复核清单。

0.6A～E及G已完成已确认范围和自动验证，0.6整版未接受。F由028承接：死亡闭环、最终击杀归属（无助攻）及私有价值KD卡片范围已通过自动回归、ENet与独立审查并关闭；不代表0.6整版或人工验收完成。实际发现／失视、场景系统、补给与维修服务继续延期；UI／队列授权不自动启动它们。

历史项目精简与保存由[027](../tasks/TASK-2026-027.md)记录并关闭；该卡曾获的保存／推送授权不构成当前新提交或推送授权，也不包括历史改写或自主清单维护。

## 当前0.7能力与缺项

- HUD底部已有小地图／武器信息／单位摘要／固定命令区；DB-44新增小地图右侧编队手动选择区及“剩余N”弹药文案。032实现、导入与独立Medium审查已通过，真实点击、弹药实时消耗更新和视觉已获用户2026-10-09明确确认。DB-45的033扩展为装甲生命条及步兵／装甲主武器开火进度；实现、最终导入exit 0和独立review PASS；用户在235011会话后明确人工确认，本卡关闭。通用字段为`primary_weapon`；无显式标记且任一候选口径缺失时primary为空并隐藏，不能选择已知较小口径武器。只使用合法披露的authority健康状态，不加schema或冻结Replay v1字段。现有武器库存仅使用当前玩家合法权威投影，缺值不得补0。所属玩家私有结构不得向他人投影。缺名称／类别显示未配置，不从生命或武器推断。小地图仅使用当前已披露单位，无新发现或点击指挥。
- 数字0～9编组、Shift加入、连续按键定位、面板焦点／Tab及退出清理可用。正式类别缺项不猜；冻结回放保留原排序。Esc菜单隔离世界、订单、HUD和镜头输入，服务器继续运行。
- 右侧战场消息有去重、淡出、定位和最多100条本地历史。命令拒绝仅给原认证玩家，白名单command／reason／own IDs；发送再次核验peer，不广播内部结果。
- D服务器每单位独立移动／持续G／T单点队列：Shift追加、普通替换、E清空；交战／阻挡保留，T完成推进、缺弹保留剩余预算等待，失效任务私有提示，死亡／断线清理。后续路线／编号仅向所属玩家投影，执行重验。Esc设置默认常规，仅本次会话偏好并作用于后续放置请求。
- 专项XYZ单发／模块探针／自动攻击／结构观测面板由显式`--acceptance-controls`启用，供专门TEST ONLY验收保留；此前人工会话显式传入该开关，因此测试提示面板被打开。030已使普通启动不传该开关且同时隐藏测试面板与game_world兵牌TEST ONLY tooltip；专门验收仍可显式打开。
- 029已实现兵牌工作／行为／搭载与装甲下次开火等权威派生状态和受限投影；本卡自动回归、ENet及独立审查范围已通过并关闭，不代表0.7整版或人工验收完成。剩余缺口为单位目标攻击及运输队列／完成条件、武器开关、完整T菜单、正式名称／类别和完整目录，以及依赖真实能力接口的状态来源。不得通过UI模拟或授予未实现能力。见[022范围矩阵](../tasks/TASK-2026-022.md)及[026依赖](../tasks/TASK-2026-026.md)。
- 030测试UI隔离已实现并通过导入与独立审查；普通启动不传`--acceptance-controls`，测试面板与TEST ONLY tooltip隐藏，显式开关仍供专门验收。030初版折叠菜单布局已被后续需求取代。031菜单功能、全员KD／overview及个人击杀／被击杀已实现、通过此前独立High静态审查和导入，并由用户人工验收。该轮审查记录`tmp/current-gap-godot/menu-pages-review.txt`，R1 viewport收缩／KD横滚、R2 unknown显示未配置、R3输入隔离/reset恢复闭合。最新两项UI修改已实现、最终import exit 0及独立增量审查PASS；证据为tmp/current-gap-godot/menu-close-footer-import-engine.log及menu-close-footer-review.txt。新交互视觉仍待用户确认。未新增运行测试。
- 030测试UI隔离已实现并通过导入与独立审查；普通启动不传`--acceptance-controls`，测试面板与TEST ONLY tooltip隐藏，显式开关仍供专门验收。030初版折叠菜单布局已被后续需求取代。031菜单功能、全员KD／overview及个人击杀／被击杀已实现、通过此前独立High静态审查和导入，并由用户人工验收；最新两项Esc关闭菜单与底部加大“返回游戏”已实现、import和独立增量审查PASS，用户人工确认通过。032实现、最终import与独立Medium审查PASS；证据`tmp/current-gap-godot/hud-groups-ammo-import-engine.log`、`hud-groups-ammo-import-output.log`及`hud-groups-ammo-review.txt`。真实组队按钮点击、消耗后弹药实时更新及960px视觉待人工；未新增运行测试。
- 030测试UI隔离已实现并通过导入与独立审查；普通启动不传`--acceptance-controls`，测试面板与TEST ONLY tooltip隐藏，显式开关仍供专门验收。030初版折叠菜单布局已被后续需求取代。031菜单及统计功能由用户验收；两项Esc返回交互工程实现、导入与独立增量审查通过，用户人工确认通过。032实现、最终import与独立Medium审查PASS，证据`tmp/current-gap-godot/hud-groups-ammo-import-engine.log`、`hud-groups-ammo-output.log`及`hud-groups-ammo-review.txt`；真实组队点击、弹药实时更新及960px视觉待人工。033实现、最终导入与独立High review PASS，证据`tmp/current-gap-godot/marker-health-infantry-import-engine.log`、`marker-health-infantry-import-output.log`及`marker-health-infantry-review.txt`；装甲生命条及步兵进度已由用户人工确认；人员交接专项动态检查没有单独运行记录，保留独立代码审查覆盖。未运行tests。

## 当前0.6能力与边界

30Hz活动权威链在实际发射时解算、采样一次散布；弹丸集中复用，移动／碰撞和终止按事件顺序，来源退出后的合法在途弹丸独立存在。

A结算输入／弹药快照／对局去重和失败永久停止；B非爆炸直击防护及最近存活成员独立生命；C逐成员／每车一次爆炸、友伤及每班一次完整压制输入；D真实伤亡后Q、10秒恢复、移动／瞄准／人工装填／散布倍率和剩余步采样；E模块资格、T=100量表、独立随机升级、四模块倍率及单级修复完成接口均已接入。服务器内部账本不进入公开弹丸或v1。死亡立即禁止行动并移除活动对象，对局来源身份快照保留至清场；F名额／维护清理、最终击杀及所属玩家私有价值KD由028实现并通过其卡片自动／ENet／独立审查验收，整版人工与验收边界不变。

G非爆炸动能连续过穿：步兵E≥2A后损耗A；车辆入口／出口两面检查，成功生命伤害为正常值10%，失败正常伤害并终止；同弹同单位一次，压制及模块不缩减。入口事件时权威姿态／瞬时切线近似，不宣称穿行期间旋转／重力精确。选弹名义评分沿确认范围调整，原始无伤害batch不启用G。

019修复攻击移动旧目标与停车判定不一致，普通白／快速蓝／攻击黄虚线路径已接入，实际表现待复核。已公开验收敌军最近目标自动攻击仅完整验收模式显式启用，Q自身开启接敌；全部射击走真实弹丸。友敌简要状态按可见性白名单过滤，Q／成员／武器／库存仍只给所属玩家。模块探针真实G射击会被友军截弹，需车体静止、射线清晰；每端7个TEST ONLY对象，总17个。

M252按散布后落点选速、g10高抛及有效射程20秒边界保留；20秒不是寿命或所有未来火炮承诺。完整T模式未接入。配置P0／P1及源哈希守卫保留；COMPLETE返回unsupported_rule_coverage，full_combat_ready=false，正式目录未解锁。AT4准备／携带量、正式编制N、Carl-Gustaf HE初速等缺项保持。

## 验证与人工义务

0.7D证据tmp/07d/：D37、A41、B24、C18、客户端105、接敌32、公开投影42、输入33、设计49均零失败；冻结03A/B/C及编辑器导入通过，退出码和脚本错误同时核对。0.6G证据tmp/06g/：G87及A55／B60／C69／D37／E30等相关回归、冻结回放及导入通过。其余A～E证据在tmp/06a～06e/。本轮清理后的复跑见027；旧失败日志不作通过证据。

既往窗口缩放／测试提示UI清理会话证据位于tmp/acceptance-06abc-20261008-000308：两端收到17单位、三端error为空。该旧会话恢复后查询已无Godot进程；此记录不表示当前会话状态。

用户已人工验收028／029本轮功能，也已验收031全员KD／overview、个人击杀／被击杀和其余菜单功能。Esc关闭菜单并恢复输入、底部加大返回游戏按钮两项收尾已实现、最终import及独立增量审查PASS，用户已于2026-10-09确认通过。194736启动会话用户主动关闭两客户端，server正常清理；该事实不代表新交互验收。此前窗口缩放已由用户确认。该次人工验收不自动恢复其他历史或未来人工义务。0.6攻击移动、状态渐变和模块表现仍未验；014／017的A精确同刻／去重及B非爆炸人工入口仍Blocked。0.7D及其他未完成项目继续按各自状态处理；自动／headless通过不代替人工观察或整版接受。

### 028／029卡片范围交付

- 最终回归31/31 suites PASS；28项有数值明细的suite合计1330 checks。03A/B/C计入suite结果但无数值summary，不虚增checks。F专项57／0，marker专项35／0。报告：tmp/current-gap-regressions/final/report.json、report.txt。03B预期negative REPLAY FAILED按分类记录；日志另有known rootcert噪声，不声称零ERROR。
- 最终ENet三角色server/client-a/client-b均exit 0且issues=[]，证据：tmp/06f-07states/enet-run-report.json及enet-*.json。覆盖source先死亡后合法在途弹击杀、最终source顺序／归属、名额释放但不改另一玩家容量、每目标仅死亡一次、ownerstats／H私有投影与清理；不是人工视觉验收。
- 最终Godot导入exit 0：tmp/current-gap-godot/import-engine.log及import-output.log。编辑器设置写入项目内workspace/editor_data，无个人AppData写错误；仅known rootcert噪声，newtest gd.uid已生成。
- 独立只读审查Reviewer PASS，R1～R4及专项均闭合；记录：tmp/current-gap-regressions/independent-review.txt。覆盖禁火时保留有效任务的engaged状态、目标失效清除状态、死亡退场不误清共享width-key导航缓存、未知统计显示、整班爆炸价值去重、同刻finalsource及source断线前已发弹丸归属，并按真实命令顺序验证。
- 028／029已完成用户人工功能验收，且各自自动验证／独立审查交付关闭；这不代表0.6／0.7整版验收。两项UI反馈另由030处理；其他人工义务及整版边界不变。

冻结旧地图Replay v1支持读取／校验／往返、checkpoint／event边界及离线表现，未知版本／内容不匹配明确拒绝；活动地图完整录制／播放和v2不支持。旧0.3C播放、0.4／0.5整体、0.5E及未完成联合复核仍不能由0.5F/G专项确认代替。设备FPS、丢包／抖动、Linux、长期带宽／性能及账本容量无独立证据，仍未验证。

旧会话`tmp/acceptance-06abc-20261008-192721`已正常停止并有receipt，旧客户端已由用户关闭；其菜单布局属于031实现前，不作为新设计验证证据。031新会话记录：`tmp/acceptance-06abc-20261008-194736/session.json`。启动器exit 0，server PID 14448，client A PID 1436／peer 1453359540，client B PID 31880／peer 2056745788；三端启动／连接PASS，两客户端各初始化17 units，server Dedicated监听localhost:7777、clients Connected，三端error日志0字节、engine无ERROR／SCRIPT／Parse。用户主动关闭两客户端后，主协调者正常清理server；stop exit 0且receipt `normal_shutdown=true`，本会话进程均已结束，端口7777可重新启动。该会话只证明启动／连接，不证明菜单、动态overview或视觉验收。停止旧会话命令：`scripts/stop-06abc-acceptance.ps1 -SessionDirectory C:\Projects\RTTGame\tmp\acceptance-06abc-20261008-192721`。启动入口`tmp/start-current-manual.ps1`。保留双真实客户端＋独立权威服务器要求及现有脚本，不以隔离测试替代。

032联机启动记录：`tmp/acceptance-06abc-20261008-200112/session.json`，server PID 3216、client A PID 31964、client B PID 7036。启动／双端连接成功，三端error日志0字节；后续检查发现client进程已退出，退出原因不推断，server随后stop exit 0且receipt `normal_shutdown=true`，本会话进程均已结束。该启动证据不表示032功能完成或已验收；当前没有新会话运行，不为本卡强制重开窗口。

033关联启动记录：`tmp/acceptance-06abc-20261008-201325/session.json`，server PID 34460、client A PID 2228、client B PID 33208。启动及双端连接PASS，error日志为0；之后两客户端退出，原因不作推断。server由协调者正常停止，当前全部进程已结束。本次启动仅记录环境状态，不作为033生命条GUI验收，也不推断用户主动关闭客户端。

## 保护与发布边界

工作簿SHA256：0113889F5046869610F5195D7751A31A76D4417C208BD9019C25D9892D8C9AC0；冻结v1：F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15。正式DATA、运行快照、冻结夹具及自主清单正文保护；公开弹丸隐私白名单、域玩家身份和私有状态边界保持。

GitHub仓库Halfaustus/RTTGame已核验为public。旧751b748／f38e68c历史含详细第三方关系映射，既有暴露处置未完成；本轮清理当前原字段引用，不复制映射、不改写历史。来源事实和独立性限制见[发布复核](../reviews/DATA_ORGANIZATION_PUBLICATION_REVIEW.md)。已删除原始资料不得恢复，外部JSON不上传；项目自有正式快照、测试配置与冻结fixture可保留。

P01／P02／P03按[PENDING_DECISIONS](../constraints/design/PENDING_DECISIONS.md#section-22)处理，不自行更改积压、移动瞄准或启用APS。DEVELOPMENT_CONTEXT只记临时配置，不作为规则来源。

## 续接

项目精简及成果保存任务027已关闭：新增6文件删除、此前55文件清理及既有开发成果保存于f36853e并正常推送origin/main；30套自动、最终导入、现行链接／资源及保护哈希检查通过。用户现已明确授权当前缺口闭环后提交并非强制推送；本轮结果以实际Git记录为准。当前实现为Git实际HEAD加本轮未提交工作树；未创建本轮提交或推送。现行根目录布局及所有必要成果保留，日志／缓存／生成诊断留本地。任务状态见[TASKS](../../TASKS.md)，版本依赖见[路线图](../../DEVELOPMENT_ROADMAP.md)。028／029自动／ENet／独立审查与用户功能验收均已通过；030测试UI隔离工程交付已通过；031其余菜单功能及全员统计已由用户验收，两项返回交互工程实现、导入与独立增量审查PASS，用户人工确认通过；032实现、导入及独立Medium审查PASS，用户人工确认通过；033实现、最终导入与独立review PASS，并获用户人工确认，本卡关闭；不据此声称运行了人员交接专项动态测试。194736、200112及201325会话均已清理；201325客户端退出原因未推断。完整命令／T、指定攻击／运输队列、正式身份目录、发现／场景／后勤与活动地图Replay v2继续延期，不启动未来阶段；P01／P02／P03及正式DATA缺项保持待定。

## 235011人工确认与自动接敌观察

用户明确“我已确认”，033兵牌血条／步兵开火进度范围人工确认通过。最新会话tmp/acceptance-06abc-20261008-235011/session.json启动／连接通过，server PID 14564，A 11032／peer 650369707，B 22716／peer 341798835，三端error日志0字节。后续进程检查仅server仍运行，客户端退出原因未推断；2026-10-09已通过具名会话stop脚本正常关闭server，exit 0及normal_shutdown=true。

用户指出射程内敌军直到Q攻击移动才遭自动攻击。当时只读代码核对：_acceptance_nearest_target要求单位位于_acceptance_auto_units，初始未登记；Q会将单位登记，因此开启接敌。普通模式automatic_target_provider为空，常驻自动选敌入口尚未接入。当时仅解释及登记已确认结果，未修改自动选敌代码；后续034承接普通入口实现与验证，不启动延期的完整发现／选敌策略。

## 2026-10-09当前范围闭环与保存

用户明确当前人工验收均已通过，030～033关闭。034普通模式常驻自动选敌已实现并验证；独立初审发现Hull停驻转向阻塞，修复前46／1、修复后46／0，真实90°转向并发射，停驻无位移且失视恢复原路线。最终33／33 suites PASS、30套报告1428 checks，三端headless ENet均exit 0且issues=[]，最终import exit 0。独立GPT-6.1 Sol High增量复审PASS，证据tmp/standing-auto/independent-review.txt。正式DATA、冻结v1与自主清单保护哈希保持。根证书环境噪声及03B预期负路径错误如实保留。

普通模式的权威可见性接口已接通；没有发现服务时敌人保持不可见，不把单位存在或客户端显示当作发现。实际开火验证使用TEST ONLY显式权威可见目标；完整06专项场景仍保留显式自动开关。发现／失视、场景、后勤、完整命令与T菜单、正式目录和Replay v2等延期不启动，不宣称0.6／0.7整版或历史暂停范围完成。

GitHub origin/main有aa341f6文档更新；原远端TASK-2026-028与本地F任务重号，其文档原文保留于035并注明迁移。合并采用当前用户全局规则及项目限制：未经明确授权不创建提交，当前已有本次保存／非强制推送授权；运行环境审批仍有效。旧235011服务器已正常退出。日志／缓存留本地，最终保存／推送结果以Git实际记录补充。
