# GREYLINE / 灰线：项目命名与品牌讨论

整理日期：2026-10-07\
来源：本次提供的项目命名讨论。本文为结构化整理，非逐字聊天记录。

## 1. 当前结论与适用范围

正式名称现为 **GreyLine Taskforce / 灰线战术群**，内部代号为 **GREYLINE / 灰线**，以[项目命名约定](../../PROJECT_NAMING.md)为准。下文保留此前讨论的候选与建议语境；仓库名、命名空间、系统术语、副标题和视觉方向均不因命名确认而获得实施授权。

原项目称为 RTTGame。讨论所依据的项目形态为现代战术作战、单位／武器／弹药配置体系，以及后续 PVE 防守、专精和单位池等方向。本文不替代项目设计基线或正式数据来源。

## 2. 名称与核心含义

推荐采用：

> **Project GREYLINE**\
> **《灰线》**\
> *A Real-Time Tactical Combat Game*

- **Grey**：对应战场信息不完全、交战规则、侦察与判断。
- **Line**：对应战线、视线、射界、防线及单位间的战术关系。
- 名称简短，便于作为游戏标题、开发代号和代码命名基础。
- 不预先绑定某一国家、战争或具体世界观，可容纳现代、近未来及架空背景。

概念核心：**信息、火力和战线之间不断变化的边界。**

项目特色可由单位配置、观察、射界、武器—弹药关系、能力与专精共同形成的战场决策来表达。

## 3. 曾讨论的备选名称

| 英文名 | 中文名 | 定位 |
| --- | --- | --- |
| Greyline | 灰线 | 已认可；克制、现代、偏战术 |
| Greyline Protocol | 灰线协议 | 偏近现代军事系统感 |
| Contact Line | 接触线 | 强调发现、接敌、交战 |
| Tactical Vector | 战术矢量 | 强调机动、射界与方向 |
| Fire Control | 火力控制 | 强调武器、弹药和交战系统 |
| Broken Front | 破碎战线 | 战争感较强 |
| Forward Line | 前沿线 | 直观易懂 |
| Steel Doctrine | 钢铁条令 | 强调单位体系、专精与作战学说 |

## 4. 三层命名体系建议

分为对外品牌名、开发工程名、游戏内系统名。

| 层级 | 推荐名称 | 用途 |
| --- | --- | --- |
| 正式英文名 | GreyLine Taskforce | 对外展示、启动界面 |
| 正式中文名 | 灰线战术群 | 中文宣传与游戏标题 |
| 开发代号 | Project GREYLINE | 文档、路线图、内部交流 |
| 仓库名 | `greyline` | Git 主仓库 |
| 根命名空间 | `Greyline` | 代码命名空间 |
| 核心数据 | `Greyline.Data` | 单位、武器、弹药等 |
| 战斗系统 | `Greyline.Combat` | 伤害、射击、交战逻辑 |
| 单位系统 | `Greyline.Units` | 单位、班组、成员 |
| 武器系统 | `Greyline.Weapons` | 武器、炮塔、弹药 |
| 感知系统 | `Greyline.Sensor` | 观察、探测、视野 |
| 行动系统 | `Greyline.Mobility` | 移动、地形、机动 |
| 能力系统 | `Greyline.Abilities` | 主动与被动能力 |
| 专精系统 | `Greyline.Doctrine` | 专精、阵营配置、单位可用性 |
| 改装系统 | `Greyline.Loadout` | 改装与候选配置 |
| AI 系统 | `Greyline.AI` | 战术 AI、行为决策 |
| 用户界面 | `Greyline.UI` | HUD、菜单、战术界面 |
| 工具链 | `Greyline.Tools` | 数据导入、验证、编辑器 |

以上是职责与名称映射，不要求立即拆分为独立工程或程序集。实际迁移需结合现有代码结构另行实施。

## 5. 关键系统术语

### 5.1 Doctrine：专精／作战学说

建议以 `Doctrine` 表达军事语境下的专精，未来可覆盖编制、单位池、能力倾向、战术加成以及战斗群编成。

示例：`Greyline.Doctrine`、`DoctrineConfig`、`DoctrineUnitAvailability`。

### 5.2 Loadout：单位改装／配置

建议以 `Loadout` 表达武器、弹药、设备及候选配置的组合。

示例：`UnitLoadout`、`LoadoutOption`、`WeaponMount`、`AmmunitionLoad`。

### 5.3 Sensor / Detection：感知与探测

如果未来包含光学、热成像、雷达、声学探测和隐蔽度等机制，建议采用 `Sensor` / `Detection` 术语。

候选概念：`SensorProfile`、`DetectionProfile`、`ObservationRange`、`SignatureProfile`、`ContactState`。

### 5.4 Contact：接触目标

可以考虑让玩家通过接触信息认识敌方对象。此前讨论的概念顺序为：

1. `Unknown Contact`：未知接触。
2. `Detected Contact`：已探测接触。
3. `Identified Contact`：已识别接触。
4. `Confirmed Target`：已确认目标。

这是待验证的机制构想，尚非正式状态机。实现前需明确未知接触与已探测接触的区别，以及目标识别、目标确认和交战许可是否属于不同维度。

品牌关联：玩家持续处理“已知与未知之间的灰线”。

## 6. 副标题与口号候选

| 文案 | 方向 |
| --- | --- |
| A Real-Time Tactical Combat Game | 项目类型描述 |
| Real-Time Tactical Warfare | 简洁的类型表达 |
| Beyond the Contact Line | 偏宣传副标题 |
| See. Decide. Engage. | 推荐口号候选，体现决策过程 |

推荐组合：

> **GREYLINE**\
> **See. Decide. Engage.**

含义映射：

| 词语 | 对应行为 |
| --- | --- |
| See | 观察、侦察、目标识别 |
| Decide | 战术判断、单位调度、武器选择 |
| Engage | 射击、火力控制、交战 |

此前建议的中文宣传表达：**看见战场，作出判断，决定交战。**

口号可以作为设计原则候选，但尚未确认采用；副标题暂不锁定。

## 7. 下一阶段

继续形成视觉识别体系：Logo 构成、主色调、字体气质、启动画面，以及“灰线”概念的视觉表达。

优先形成可评审的设计方向，再决定最终图形与工程迁移。当前文档仅记录命名讨论，不表示已完成 Logo、代码重命名、仓库迁移或品牌可用性检索。
