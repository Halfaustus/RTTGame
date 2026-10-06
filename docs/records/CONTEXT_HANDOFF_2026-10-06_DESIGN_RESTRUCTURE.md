# Context Handoff：设计文档整理与开发规划

归档日期：2026-10-06（北京时间）。工作区：`C:\Projects\RTTGame`。本次任务已完成，用户明确要求生成会话归档。本文件只保存本次会话的工作语境，不是游戏规则、开发授权或当前状态来源；后续状态以实际工作树、最新用户指令和[HANDOFF.md](HANDOFF.md)为准。

## 用户任务与结果

用户先要求阅读目前所有设计文档并报告重复内容，随后授权合并重复内容、按局外／局内或更细领域拆分，并重新规划未来开发进度。审查覆盖22份Markdown设计／相关记录、根目录AGENTS以及5页签正式DATA工作簿；后续整理依据实际DB-2026-10-06-39，而非此前审查时的旧标识。

已完成34处重复表述合并，以及文档职责、参数引用和工作流程表述的集中维护。保留独有条件和原章号定位；没有把设计冲突自动裁决为新规则。正式武器性能引用DATA，机制与通用默认值留在基线，协议字段留在技术契约，视觉参数留在表现说明。

## 文档交付与阅读顺序

1. 根目录[AGENTS.md](../../AGENTS.md)：实际适用开发约束。唯一基线入口的表述已适配模块化正文，重复流程表述改为引用。
2. [DESIGN_BASELINE.md](../constraints/DESIGN_BASELINE.md)：仍为DB-2026-10-06-39的唯一游戏规则入口；明确列出的12份正文共同组成基线，不是12个独立授权来源。
3. `docs/constraints/design/`：UNIT_CONFIGURATION、OUT_OF_MATCH、DEPLOYMENT_ECONOMY、MOVEMENT_COMMANDS、COMBAT_RULES、PROJECTILES、TRANSPORT_LOGISTICS、WORLD_VISIBILITY、UI_INPUT、MATCH_MISSION、PENDING_DECISIONS、FUTURE_PVP。保留原节号与显式锚点，按本次任务范围读取正文。
4. [DEVELOPMENT_ROADMAP.md](../DEVELOPMENT_ROADMAP.md)：版本依赖、前置设计与交付门槛。
5. [HANDOFF.md](HANDOFF.md)：整理后的实际实现、验证、限制与授权下一步。
6. [README.md](../README.md)：完整文档导航；[公开载荷契约](../constraints/PROJECTILE_VISIBILITY_CONTRACT.md)与[表现说明](PROJECTILE_PRESENTATION_REVIEW.md)已减少重复参数与状态副本。

本轮没有修改AUTONOMOUS_DESIGN_REVIEW.md。允许拆分文档和安排版本不是新的自主游戏设计授权。正式DATA、源码、冻结夹具以及已有无关修改／删除均保留；没有Git commit或push。

## 规划结论与执行边界

规划顺序：0.5收尾 → 0.6伤亡与战斗结果 → 0.7观察与场景 → 0.8指挥、能力与UI → 0.9运输后勤 → 0.10局外编辑与作战群 → 0.11标准PVE任务 → 0.12正式Demo整合与标定。小版本划分及设计门槛仅在路线图维护，不在此重复。

归档时实际阶段仍为0.5F弹丸人工复检／收尾，0.6未开工。路线图不解除暂停、不启动未来版本。下一设计准备优先步兵班减员模型，但本轮未选择成员抽样方案、随机记录策略或新的标定参数。当前客户端验收是否执行须遵守最新明确授权与AGENTS客户端测试约束，归档本身不授权启动客户端。

DB39已确认25分钟任务、四阶段、生存性目标、8分钟弹药窗口和无经验成长；这些集中在MATCH_MISSION正文，尚未形成完整任务及伤害闭环。平衡目标不是强制减员或寿命倒计时。PVP为长期愿景，不阻塞当前PVE。

## 未决问题与验收义务

当前冲突集中在[PENDING_DECISIONS第22节](../constraints/design/PENDING_DECISIONS.md#section-22)：P01通用弹丸待定表述与已授权C类工程边界未统一；P02禁移动射击武器移动清零与开始／停止移动不重置瞄准的适用范围冲突；P03 APS机制描述与仅定义标签、未启用的状态需澄清。没有修改实现或撤销既有工程授权。

M252正式初速225m/s、g10与高支路下测量约44–45秒；约10秒体验目标仍待取舍。不得为目标自行更改正式速度、分支、profile、装药或客户端时间。正式DATA仍有AT4准备／携带量、正式编制N及Carl-Gustaf HE初速等缺项；测试值不能自动转正式。

0.5E/F双端复验、0.5与0.4整体人工验收及旧0.3C播放义务仍未完成。既有自动通过不代表这些项目通过。活动地图完整回放不支持，当前Demo不开发Replay v2；冻结v1兼容边界仍有效。

## 本轮验证与辅助文件

文档检查通过：19份当前文档的本地链接及锚点、12份正文原章节定位、关键合并条件，以及4份受保护文件哈希检查；`git diff --check`无空白错误，仅提示既有换行转换。保护对象为自主复核清单、DATA工作簿、confirmed/db29.json及冻结replay_v1.json。未重跑游戏测试、启动客户端或进行人工验收。

忽略目录`tmp/`有辅助审查文件：`design-restructure-audit.json`记录来源哈希、模块映射、合并理由与保护哈希；`check_design_docs.py`用于本轮静态检查。`restructure_design_docs.py`、`update_current_docs.py`、`finalize_design_docs.py`是已执行的一次性整理脚本，不能盲目重跑，尤其前者的单体源文档现已变为入口。这些文件不是正式规则或可依赖的长期证据，后续以实际文档为准。

工作树原本已有大量修改、删除和未跟踪文件。不要将全部Git差异归因于本轮，不要清理、恢复或提交无关工作。旧CONTEXT_HANDOFF保留原时点，不用其暂停／地图未实现陈述覆盖当前HANDOFF。RTTGame_DESIGN_PRINCIPLES.md与DEVELOPMENT_CONTEXT.md当前缺失，不重建其内容或推断授权。

## 后续Agent接手

先读取实际AGENTS、基线入口、相关模块及HANDOFF，再按用户新指令行动。本次整理已结束，不需要继续合并或开始路线图阶段。新的实现、设计裁决、客户端测试、正式DATA变更和Git提交分别检查其明确授权，不从本次归档推断。
