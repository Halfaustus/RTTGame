# 正式 DATA provenance 与历史截止点

生效依据：项目所有者2026-10-07明确指令；整理任务 TASK-2026-013。此文维护来源与变更审计，不定义游戏数值，也不替代设计基线。

## 当前权威与已知历史

唯一现行正式实例数据权威是 `docs/RTT_GAME_DATA.xlsx`。当前SHA256：`0113889F5046869610F5195D7751A31A76D4417C208BD9019C25D9892D8C9AC0`；关联规则DB-2026-10-06-40。`game/data/confirmed/db29.json`为运行快照，不能反向覆盖工作簿；其source／source_sha256、data_version、rules_id、baseline_id沿用现有校验机制。TASK_TEMPLATE的 DATA Reference 与 Source Revision继续作为任务引用，不另建竞争版本系统。

项目所有者说明：部分初始参数通过与ChatGPT对话，按设计规则、估算、推算及人工调整形成；原始对话已归档，不能逐字段审计。该说明是2026-10-07的来源声明，不是恢复出的历史计算凭证。此前已核对5表43记录515单元格与JSON一致；本次不重复无差别性能核验。

截止点为上述工作簿摘要与本次用户指令。所有此前采用、无法逐项恢复的现有数据统一登记：

| 字段 | 值 |
| --- | --- |
| Origin | Legacy derived baseline |
| Original derivation | ChatGPT-assisted estimation / project-owner design |
| Current authority | RTT_GAME_DATA.xlsx |
| Status | Adopted project baseline |
| Attribution evidence | 项目所有者2026-10-07声明；历史逐字段对话／推导不可审计 |
| DATA Reference | 工作簿路径＋工作表＋对象ID／单元格＋上述SHA256 |
| Source Revision | f38e68cb51122e54713adc894277400719e14a09；本来源整理为未提交工作树 |

逐字段定位沿用 [FORMAL_DATA_SOURCE_AUDIT.csv](reviews/FORMAL_DATA_SOURCE_AUDIT.csv)，不复制数值到第二套正式表。其Derivation列统一记录上述历史身份；不把旧代码可计算结果写成历史推导证据。未知原始计算、输入事实、人工调整顺序及日期不补造。此身份不声称完全独立，也不把缺口本身视为第三方复制证据。未配置／不适用标记保持原义。

## 从截止点起的修改审计

任何正式DATA修改须由实际任务卡使用既有 DATA Reference／Source Revision记录，并新增一张“DATA Change Audit”表；TASK_TEMPLATE已提供字段。未改数值的本次来源整理不伪造before／after记录。

每个改动必须包含：文件、工作表、对象／行ID、字段／单元格、修改前值、修改后值、原因、来源类型、来源证据、Source Revision／版本。记录工作簿修改前后摘要及导出版本；提交后用真实commit补充Source Revision，未提交时明确写未提交，不编造commit。修改前后原样保留数值及缺失标记；批量变更须逐项或以可逐项还原的附件记录，不能只写“整体平衡”。

来源类型至少为：`Project design decision`（明确项目决定）、`Formula-derived`（已确认公式及可追溯输入）、`Playtest/balance adjustment`（测试条件、观察与选择理由）、`External verified reference`（可核验事实出处及适用范围）、`Legacy derived baseline`（截止点以前已采用数据）。新修改不能用legacy类型掩盖无来源变更。禁止用旧聊天、旧代码、第三方游戏数据或未经确认机制补缺。外部事实参考不自动授权复制游戏参数组合。

工作流程：确认修改授权与现行规则→记录before及来源→执行获准改动→记录after与版本／摘要→同步既有JSON和校验机制→按影响做定向一致性检查→同步任务、TASKS和HANDOFF。发现与现行规则、正式DATA、明确外部事实或权威项目文件冲突时，登记冲突并阻塞受影响修改／使用，等待明确裁决；不能选择旧聊天或旧代码的值。来源整理不要求修改旧快照元数据或放宽验证器。

## 选择性重新确认候选

以下是候选，不是已发现复制、错误或自动返工；不改当前值，不开展全面重标定。

| 候选 | 高影响原因／建议核验范围 |
| --- | --- |
| Ammo的基础伤害、穿深锚点、爆炸半径及模块参数 | 直接改变致死性及装甲对抗；未来平衡任务核对项目目标、单位含义及交互边界 |
| ArmoredVehicles的生命及各向防护 | 成组影响存活和方向选择；按获准测试场景确认预期，不猜测匿名型号对应 |
| Weapons的有效射速、聚合、间隔、库存及携弹上限 | 影响事件数量和持续火力；仅核验现行公式／库存权威是否一致，不能据代码反推未配置值 |
| Parameters的压制额度／阈值／衰减及操作人数 | 影响未来0.6D和后续资格；在阶段DoR核对有效规则与DATA，不自动启动D |
| 正式编制、AT4准备／携带量、相关初速等已缺配置 | 是现存配置缺项，legacy身份不填空或赋予能力；受影响完整目录保持既有阻塞 |

本轮没有确认新增数值冲突；既有完整目录能力覆盖与未配置阻塞不因provenance整理解除。历史截止点使现有数据可按采用身份维护，不要求为每个数值恢复旧对话。

## 整改结果与边界

已建立权威来源、历史截止点、统一legacy登记和后续审计字段；沿用现有版本与源哈希体系。无法恢复范围是截止点前逐字段原始推导链，不是工作簿／JSON定位缺失。未修改正式数值、工作簿结构、运行快照、代码、基线或自主复核清单；未提交／推送。详细schema历史发布隔离另见 [关联性复核](reviews/DATA_ORGANIZATION_PUBLICATION_REVIEW.md)，来源整理不消除那项风险。
