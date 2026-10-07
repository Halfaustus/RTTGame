# RTTGame 设计基线

基线标识：DB-2026-10-07-41。状态：已确认规则汇编。日期：2026-10-07（北京时间）。有效弹道与时序见第18节；直射最近存活成员规则见第9节。

## 0 文档职责与范围

本文件是唯一现行游戏规则基线入口。下表明确列入的正文是本基线组成部分，按所属职责维护一份有效规则；其他技术契约、记录、路线图及外部资料不成为独立游戏规则来源。阅读入口后必须读取本次工作涉及的正文，不能只按入口摘要实现。

显式用户指令优先；项目内适用开发约束优先于设计基线。开发流程、授权、验证与交付见根目录[AGENTS.md](../../AGENTS.md)。实际实现、暂停／恢复、验证与当前授权下一步见[HANDOFF.md](../records/HANDOFF.md)。设计已确认不等于功能已实现，规划版本不自动授权开工。

已确认实例配置数值统一见[RTT_GAME_DATA.xlsx](../RTT_GAME_DATA.xlsx)；基线正文规定机制、公式、机制常数与通用默认规则，不另存具体武器性能表。DATA的“未配置”表示适用但仍缺配置，“不适用”表示字段不适用；二者不等于0，不产生默认值或能力。测试值不得回写为正式DATA。

本文及所属正文只维护现行规则、明确待定项和未解决冲突。冲突与缺失设计统一见[第22节](design/PENDING_DECISIONS.md#section-22)，不靠另一份正文、历史记录或通过的测试自动裁决。术语与状态隔离统一见[第24节](design/UNIT_CONFIGURATION.md#section-24)。

`docs/RTTGame_DESIGN_PRINCIPLES.md`当前未找到，不重建其内容或授权。[DEVELOPMENT_CONTEXT.md](../DEVELOPMENT_CONTEXT.md)已获用户授权创建，仅记录核验的当前临时配置，不重建缺失历史或充当规则／授权来源。现存自主设计复核清单仅供人工查证，不能替代本基线或HANDOFF；本轮没有新增自主游戏设计授权，不修改清单。

## 正文目录

| 领域 | 正文 | 原章节 | 职责 |
| --- | --- | --- | --- |
| 共用 | [共用：单位、武器与配置定义](design/UNIT_CONFIGURATION.md) | 24 | 局外编辑、组卡和局内生成共用；只定义对象及合法关联。 |
| 局外 | [局外：阵营、专精与作战群](design/OUT_OF_MATCH.md) | 1、2 | 战前单位池、类别预算、单位卡和关联组卡。 |
| 局内 | [局内：经济、出动与部署](design/DEPLOYMENT_ECONOMY.md) | 3、4、17 | 账户、名额、订单、生成、返基地退款和统计。 |
| 局内 | [局内：移动与任务队列](design/MOVEMENT_COMMANDS.md) | 11 | 路径、队形、空间占位、任务队列及场景障碍关系。 |
| 局内 | [局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md) | 9、10、12、13、19、20、24A | 伤亡、防护、压制、模块、选敌、火力流程、火炮任务、烟雾及镭射。 |
| 局内 | [局内：弹道、碰撞与公开表现](design/PROJECTILES.md) | 18 | 统一权威弹道、时序、碰撞、友伤及客户端表现边界。 |
| 局内 | [局内：运输、撤离与补给](design/TRANSPORT_LOGISTICS.md) | 5、6、7、8 | 运输容量、装卸、损失、撤离人员、补给服务、修复及殉爆。 |
| 局内 | [局内：场景、驻扎与隐蔽](design/WORLD_VISIBILITY.md) | 23 | 树林、房屋、障碍物、掩体、隐蔽、暴露与消音；选敌资格见战斗正文。 |
| 局内 | [局内：界面、兵牌与输入](design/UI_INPUT.md) | 14、15 | 信息架构、兵牌派生状态、选择、指令交互、键位及互斥。 |
| 局内 | [局内：合作、任务节奏与平衡目标](design/MATCH_MISSION.md) | 16、25 | 权限、掉线、25分钟PVE任务、战术寿命与弹药窗口；平衡目标不是强制损耗计时器。 |
| 跨系统 | [跨系统：待定设计与冲突](design/PENDING_DECISIONS.md) | 22 | 当前缺失设计、未解决条款与已确认编辑器功能边界；不授予待定内容实现权限。 |
| 长期愿景 | [长期愿景：PVP](design/FUTURE_PVP.md) | 21 | 仅供未来阶段讨论，不影响当前PVE开发与验收。 |

## 按开发范围阅读

- 局外配置／编辑器：配置定义、局外作战群、界面输入、待定设计；部署生成仍核对经济与出动正文。
- 局内战斗：配置定义、战斗、弹丸、场景隐蔽、任务平衡目标与待定设计。
- 移动／指挥／UI：移动任务、界面输入、战斗能力和部署正文。
- 运输／后勤：运输补给、经济部署、移动、战斗伤亡、合作权限与待定设计。
- 任务／合作：任务节奏、局外作战群、经济部署、场景规则与待定设计。
- 任何兼容敏感改动：同时核对[冻结Replay v1](REPLAY_FORMAT_V1.md)和AGENTS回放约束。新活动地图完整回放不在当前Demo范围。

## 技术契约与规划

技术接口仍分别维护：[弹丸C类工程契约](PROJECTILE_SIMULATION_C_DESIGN.md)、[弹丸公开载荷](PROJECTILE_VISIBILITY_CONTRACT.md)、[回放格式](REPLAY_FORMAT_V1.md)、[录制](REPLAY_RECORDING.md)、[播放](REPLAY_PLAYBACK.md)。其中工程授权与通用规则的未统一项列于第22节，不能因移动文档而撤销既有授权。

[未来开发规划](../../DEVELOPMENT_ROADMAP.md)组织工作依赖、范围和交付门槛，不定义新玩法，不替代当前阶段授权。

## 原章节定位

保留原章节编号供现有记录查找。入口下方锚点仅导航，不重复保存正文。

<a id="section-24"></a>

## 24 统一单位、武器与配置约束

见[共用：单位、武器与配置定义](design/UNIT_CONFIGURATION.md#section-24)。

<a id="section-1"></a>

## 1 阵营专精与单位分类

见[局外：阵营、专精与作战群](design/OUT_OF_MATCH.md#section-1)。

<a id="section-2"></a>

## 2 作战群预算与单位卡

见[局外：阵营、专精与作战群](design/OUT_OF_MATCH.md#section-2)。

<a id="section-3"></a>

## 3 出动分维护与退款

见[局内：经济、出动与部署](design/DEPLOYMENT_ECONOMY.md#section-3)。

<a id="section-4"></a>

## 4 购买与出动订单

见[局内：经济、出动与部署](design/DEPLOYMENT_ECONOMY.md#section-4)。

<a id="section-17"></a>

## 17 部署受阻

见[局内：经济、出动与部署](design/DEPLOYMENT_ECONOMY.md#section-17)。

<a id="section-11"></a>

## 11 移动队形与任务队列

见[局内：移动与任务队列](design/MOVEMENT_COMMANDS.md#section-11)。

<a id="section-9"></a>

## 9 生命伤亡与压制

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-9)。

<a id="section-10"></a>

## 10 防护弹道与装甲模块

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-10)。

<a id="section-12"></a>

## 12 视野目标与开火

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-12)。

<a id="section-13"></a>

## 13 武器瞄准弹药与烟雾

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-13)。

<a id="section-19"></a>

## 19 火炮T菜单与炮击任务

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-19)。

<a id="section-20"></a>

## 20 镭射指示

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-20)。

<a id="section-24a"></a>

## 24A 通用武器机制与配置引用

见[局内：伤亡、武器与战斗能力](design/COMBAT_RULES.md#section-24a)。

<a id="section-18"></a>

## 18 统一弹丸运动、碰撞与友伤

见[局内：弹道、碰撞与公开表现](design/PROJECTILES.md#section-18)。

<a id="section-5"></a>

## 5 运输容量与装卸

见[局内：运输、撤离与补给](design/TRANSPORT_LOGISTICS.md#section-5)。

<a id="section-6"></a>

## 6 主动放弃与撤离人员

见[局内：运输、撤离与补给](design/TRANSPORT_LOGISTICS.md#section-6)。

<a id="section-7"></a>

## 7 补给来源与服务

见[局内：运输、撤离与补给](design/TRANSPORT_LOGISTICS.md#section-7)。

<a id="section-8"></a>

## 8 补给消耗与殉爆

见[局内：运输、撤离与补给](design/TRANSPORT_LOGISTICS.md#section-8)。

<a id="section-23"></a>

## 23 场景实体、驻扎与比例减伤

见[局内：场景、驻扎与隐蔽](design/WORLD_VISIBILITY.md#section-23)。

<a id="section-14"></a>

## 14 兵牌、详细信息面板与鼠标交互

见[局内：界面、兵牌与输入](design/UI_INPUT.md#section-14)。

<a id="section-15"></a>

## 15 键位与共键互斥

见[局内：界面、兵牌与输入](design/UI_INPUT.md#section-15)。

<a id="section-16"></a>

## 16 合作权限与掉线撤退

见[局内：合作、任务节奏与平衡目标](design/MATCH_MISSION.md#section-16)。

<a id="section-25"></a>

## 25 战斗节奏与单位生存性

见[局内：合作、任务节奏与平衡目标](design/MATCH_MISSION.md#section-25)。

<a id="section-22"></a>

## 22 待定事项与冲突登记

见[跨系统：待定设计与冲突](design/PENDING_DECISIONS.md#section-22)。

<a id="section-21"></a>

## 21 长期愿景：后续PVP专用规则

见[长期愿景：PVP](design/FUTURE_PVP.md#section-21)。
