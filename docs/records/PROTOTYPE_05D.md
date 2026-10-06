# 现行来源说明（DB33）

下文的“正式测试资源/配装/默认性能”仅记录当时原型，不是现行DATA授权。8人、6步枪/2班组武器为TEST ONLY；旧standard共享资源、400米/穿深12至5、PDW200米、旧机炮及火箭库存均仅保留历史兼容测试语境。现行武器关系、射程、装填、间隔与弹药性能由ConfirmedGameData读取DATA，current_performance专项验证实际发射。AT4上限不提供库存或准备时间。

# Prototype 0.5D：运行武器、攻击资格与实际瞄准

本轮依据为实际工作区 `docs/constraints/DESIGN_BASELINE.md`，标识 **DB-2026-10-04-17**，另采用用户明确确认的摩托化突击班／防守班测试配装。原 `DESIGN_BASELINE_DB17.md` 已按用户授权完整保存为默认路径，取代旧基线；随后仅第11节按追加授权同步已确认0.5A/B/C空间规则。两种班组配装没有写回基线，其他章节没有整理或重写。

## 实现与停止点

`AmmoDefinition → WeaponDefinition → WeaponAllocation → WeaponSlotState → RuntimeWeaponInstance → AttackTarget → AimingSimulation → actual orientation → is_aimed`。

AmmoDefinition／WeaponDefinition是共享资源；WeaponAllocation决定实际岗位、槽位及初始库存。每个实际槽位创建独立实例，标识为单位ID／节点类型／节点ID／槽位ID；实例以弱引用回指单位、节点、槽位，库存深复制。原已有显式Hull／Mount槽位也进入同一工厂。无后坐力炮占主＋副槽，配置验证拒绝岗位冲突；无分配的班组库存不生成实例。

UnitState保留Squad控制主体及真实Soldier位置／5HP／hitbox／formation。Soldier增加权威aim_yaw，不改人员位置或班组路径。Hull朝向只由MovementSimulation写入，静止时接收攻击朝向请求，移动请求优先；正式测试车辆非倒车先转后移，倒车保持朝向，使用道路／越野速度的10%。炮塔保存相对Hull yaw、派生世界yaw，通用最短角度限幅转向，不维护第二套权威角度。MainTurret／CommanderTurret无独立HP、hitbox或footprint。

MainTurret主炮与同轴共享节点，但目标、计时、库存和orientation_ready各自独立。手动目标优先；自动主炮优先；同等级使用稳定实例标识排序防抖，此排序是技术细节。车长炮塔独立。Hull武器没有独立旋转节点。

AttackTarget使用注册表＋弱引用验证权威单位，失效／死亡／移除／失视清理。当前单位目标为班组锚点或车辆本体；不实现目标部位选择。强制地面目标有独立种类，不伪装步兵。目标类型枚举保留五类，当前仅存在步兵／地面车辆实体，不新增航空或工事系统。服务器绑定接口检查peer与player身份、单位归属、敌我关系；E停止清理绑定目标，不改变武器停用／仅还击输入。

Eligibility提供可检查原因：owner_invalid、no_target、target_invalid、not_visible、friendly_target、type_not_allowed、out_of_range、path_blocked、disabled、sprinting、moving_prohibited、return_fire_locked、indoor_prohibited、ammunition_insufficient、configuration_missing。距离直接使用权威Vector3米制位置，不读UI或弹药曲线终点。可见性、路径、移动状态提供者缺失时拒绝资格；当前原型没有迷雾，生产提供者明确采用现有全图单位复制可见口径及原CombatSimulation静态LOS。测试的可见性／LOS桩显式配置，不代表实现完整探测或房屋系统。

机炮每次完整瞄准只采样一次2～3秒；同目标移动／车辆启停不重抽。换目标、失视、停用、冲刺、禁移动射击武器移动清零。瞄准计时与实际转向并行，状态时间倍率保留完成比例。恐慌／失能和仅还击使用服务器输入接口，本轮不生成压制、受伤触发或状态事件。其他资格暂时失败时不报告is_aimed；未新增追击、绕障射击阵地或额外移动任务。

`is_aimed = can_attack && aim_timer_complete && orientation_ready`，其中orientation_ready针对本武器自己的目标。没有can_fire、reload进度或下一次开火倒计时。

**没有开火、弹药消耗、reload推进、弹丸、命中、穿深求值、伤害、压制或模块破坏。** 生产server tick默认禁用旧自动伤害；旧代码保留，历史隔离测试显式启用`legacy_combat_fixture_enabled`，新运行武器单位另有旧战斗入口拒绝保护。

## 定义、配装与入口

集中配置：`game/scripts/combat/prototype_05d_catalog.gd`。正式测试资源：`game/data/05d/{assault,defense,vehicle_a,vehicle_b,vehicle_c}.tres`；共享装配入口：UnitState.configure。免费测试生成A车辆＋突击班＋防守班；敌军测试生成突击班；既有临时购买卡test.armored／test.rifle分别使用A／突击班定义，购买、倒计时及生成仍走既有经济链。B/C通过资源及隔离场景验证；防守班可由免费入口生成。原未武装测试卡和历史资源保留。

| 配置 | 实例／库存 |
| --- | --- |
| 突击班 | 8人40HP；2门无后坐力炮（每门破甲4＋高爆4，占主副槽、不加步枪）；6支步枪，各150，共900 |
| 防守班 | 8人40HP；2挺轻机枪，各750，共1500；6支步枪共900；全班火箭弹库存5，个人岗位及并行发射器数量未定义，无5个推导实例 |
| A／B车辆 | 主机炮＋2门车载机枪；主炮塔主炮／同轴，独立车长炮塔机枪；无Hull机枪 |
| C车辆 | 主机炮＋3门车载机枪；另有Hull机枪 |

PDW200m／30容量／150库存／标伤0.8；步枪400m／30／150／标伤1；轻机枪600m／150／750／标伤1，和步枪共享标准弹药资源（400m达到穿深5，不把600m范围归一化）。车载机枪600m／450／2250。容量、库存、待发分别保存，总库存不另加已装填弹药。枪械0.5秒实际／三发合一／1.5秒抽象／人工准备3秒均只登记。霰弹枪保留10容量、50库存、1秒间隔，其他性能未定义。

无后坐力炮600m／2秒／禁移动／允许室内，准备6秒；火箭弹400m／1秒／禁移动／禁止室内，准备3秒，均只登记已确认弹药静态数据。A10容量、穿甲10＋高爆40；B/C30容量、穿甲30＋高爆120，均2～3秒、移动瞄准；B/C1000m正式，A射程仅临时测试值。所有弹药只保存正式锚点、下限、曲线描述；没有对数系数或求值器，枪械不套用机炮临时公式。

旧8m武器仅通过明确命名的历史兼容夹具读取，不是WeaponDefinition默认值。默认range／aim为-1，未知移动资格-1、类型列表空；未知瞄准不会默认为0。

观察入口：RuntimeWeaponInstance.observation（单位、实例、定义、槽位、节点、目标、资格原因、距离、desired／actual yaw、progress、sample、ready）。UnitState.weapon_summary按型号汇总数量和弹种库存，不暴露空间层级；unassigned_weapon_stock明确count=null，不能把5库存伪装5个发射器。没有正式HUD重做、状态图标或烟雾武器卡。

## 基线单位／标签／命令资格核查

- 原unit_mobile／stationary／unarmed为旧原型：移动／HP／8m武器不是正式默认；新正式测试预设取代默认免费、敌军及对应购买生成定义，旧资源留作回放指纹和兼容夹具。
- UnitType为属性；Mount类型为内部结构分类，不是游戏能力标签。新A/B/C为smoke_1，C另有mobile_supply；无冲刺、镭射或APS。摩托化测试班记录sprint／smoke_1。smoke_1／smoke_4不同时出现。
- 现有玩家UI没有完整冲刺、烟雾、镭射、补给能力按钮及执行循环，本轮不新增、不为无标签单位授权能力、不冒称能力已完成。标签门控长期约束补入AGENTS.md。具体能力循环、余量、运输／供给／重量校验不属于0.5D。
- 新配装不再依赖旧definition.weapon字段：服务器单位和私有购买目录均正确报告armed资格；选择、E停止、订单放置／取消和兵牌沿用原实现。
- 正式配装价格、装备重量、火箭弹个人岗位未知，不虚构。既有购买卡价格仍明确为历史测试参数，不认作正式配装定价。

## 本版本自行补充的未定义参数

| 参数 | 当前值／用途 | 最小方案理由／后续调整 |
| --- | --- | --- |
| gun/vehicle MG test aim | 固定1秒 | 显式隔离测试与原型测试预设，验证计时链；正式瞄准性能未定，须替换 |
| gun/vehicle MG moving aim | 测试允许 | 仅temporary_fields中明确标记，不由机炮资格继承；正式资格待定 |
| attack type test lists | 步兵、地面载具 | 显式测试列表；不根据伤害扩大类型，正式各型号名单待定 |
| A test range | 1000m | 明确临时值，方便同场景比较，非由1000m穿深锚点推导；正式待定 |
| aim angular tolerance | 1° | 集中技术容差，避免浮点误差造成永不就绪；可后续调整 |
| range epsilon | 0.00001m | 仅射程边界数值容差，非增加玩法射程 |
| random seed | 50504 | 本轮可重现采样；不是永久随机规则 |
| slot local position | (0,0,0) | 未定义安装锚点时采用所属节点原点；待正式空间位置替换 |
| initial relative yaw | 0 | 沿用0.5B最小初始化，与Hull初始方向一致；之后独立转向 |
| default runtime enabled | true | 生成后可验证资格，实际停用由服务器状态输入；不是射击授权 |
| equal priority arbitration | 稳定实例ID | 仅技术防抖，同等级正式策略仍未新增 |
| isolated rocket fixture stock | 1 | 验证单个武器链的最小库存，不决定防守班岗位或齐射数量 |
| benchmark | 8/64/128单位，各半班组与C车，120tick／60Hz | 测量参数，非正式规模承诺 |

10Hz内部权威状态复制、formation spacing0.5m、人员跟随倍率1.25及动态堵塞重试1秒继续沿用，未调整。正式转速A/B Hull60、C100、主炮塔120、车长／Soldier360°/s不属自行补参。

## 自动验证、性能与回放

针对性场景：`game/tests/prototype_05d_test.gd`，**108项，0失败**。覆盖射程内／边界／外和LMG500m、共享资源与独立库存、正式配装、岗位冲突、所有生成入口、资格失效／室内桩、独立计时／采样／重置／状态倍率、转速／环绕／Hull移动优先／倒车／实际成员跟随、共享Mount目标冲突、只瞄准不射击、身份边界、armed目录、E取消目标和内部复制。

必要回归：0.5A39／0.5B54／0.5C59／移动性能99，0.4A50／0.4B47／0.4C72／0.4D32，均0失败；0.2A/B、0.3A/B/C隔离回归通过。0.5B朝向断言按本轮明确要求改为相对Hull合成，免费车辆断言采用已确认Mount配装，不降低覆盖。0.2A、0.3A及0.4C历史自动伤害场景显式标记legacy fixture；0.4C第一次回归有1项旧自动伤害依赖失败，隔离后72项通过。新增测试曾有typed Array调用错误，修正后最终日志无脚本错误。

证据：`tmp/05d/test.log`、各`prototype_*_test.log`、`movement_performance_test.log`和`import.log`。所有正式记录为实际运行结果，不包含人工推定。首次editor/import写默认AppData设置被环境限制，改用工作区临时APPDATA／LOCALAPPDATA后复验通过，没有改写用户全局编辑器设置。Godot根证书读取环境ERROR仍存在，不属于脚本失败；0.3B错误注入场景产生预期REPLAY FAILED日志并通过断言。没有启动窗口／网络客户端。editor/import与git diff --check完成。

固定指定目标，不做逐武器全图搜索。每tick资格检查恰为武器数；共享空间节点只转一次，瞄准系统路径查询0。最后独立测试测量（Windows Godot调试环境，120tick均值，不等同整机游戏帧率）：

| 混合单位数 | 运行武器数 | Aim.advance平均ms | 单次复制构建＋Variant编码ms | 数据bytes |
| --- | --- | --- | --- | --- |
| 8 | 48 | 0.785 | 0.398 | 30568 |
| 64 | 384 | 6.439 | 2.904 | 235416 |
| 128 | 768 | 18.440 | 10.309 | 469588 |

调用量线性，无逐武器全局索敌、无新增路径请求；时间并非严格等比，128单位成本明显。生产tick另有Hull请求预检，表中不是完整server tick预算；复制维持10Hz，数据体积线性增长但带宽／编码开销仍高，未测真实ENet压缩、Linux或客户端渲染。本轮没有无依据承诺大规模帧率。

RTTReplay v1 schema／spawn阶段／绝对HP和position表示未改；新Runtime、目标、Soldier aim、Mount状态只进入内部10Hz复制，不扩展冻结格式，也不能从v1恢复这些新增战斗细节。0.3A冻结读取、往返、事件／检查点边界与表现检查通过；0.3B当前生产记录、0.3C离线读取／时钟回归通过。旧资源与冻结fixture均未改，fixture SHA256仍为`F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15`。大版本最终仍需完整兼容性与人工验收。

## 人工状态与限制

用户已确认0.5B／0.5C没有问题，作为用户人工反馈记录，不重新要求检查。**0.5D人工复核按用户决定不执行**，不写为人工通过；不声称0.5大版本统一人工验收已完成。0.4大版本延期状态不改。

正式枪械瞄准／移动资格／攻击列表、A正式射程、火箭弹个人岗位仍待设计；固定世界散布半径与枪械对数参数未知。本轮只提供自动目标选择接口，未实现最高伤害效率算法，也未用最近目标冒充；旧nearest_enemy保留为历史兼容，正式运行武器通过服务器绑定目标／显式提供者瞄准，无新增自动全图搜索或追击。没有完整人员状态、迷雾、房屋、射击／伤害或新HUD系统。基线原共享班组弹丸碰撞条款没有借本轮弹丸尚未实现而改写；人员hitbox查询基础继续保留，未来实际弹丸接入须核对正式命中规则。

本小版本完成后停止。下一阶段仅保留已建立的定义／库存／槽位／目标／瞄准接口，等待用户指定范围；不自动进入开火、reload、弹丸或伤害，不提交Git。
