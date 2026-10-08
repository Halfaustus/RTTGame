# TASK-YYYY-NNN — 任务名称

模板版本：TW-2026-10-08-02。复制到docs/tasks/任务ID.md后填写；删除提示，不适用项说明理由。

## 元信息

| 字段 | 内容 |
| --- | --- |
| Type | FEATURE / FIX / REFACTOR / DATA / DESIGN / INFRA / TEST / SPIKE |
| Status | Draft |
| Priority / Risk | 待评估 |
| Systems | |
| Owner | |
| Created / Updated | 北京时间 |
| Baseline Revision | 标识＋相关章节/内容快照 |
| DATA Reference | 文件、工作表、对象/行ID、版本或摘要 |
| Source Revision | commit或明确未核验 |
| Authorization | 用户目标＋AGENTS默认授权/既有专项授权、范围、核验时间（代理核验，不逐步索批） |
| Pause State | 相关暂停及解除依据；未知时写未核验 |

## Goal

说明交付后新增或改变的可判定行为；文档/设计任务写具体产物。

## Source

- DESIGN_BASELINE：章节、相关规则内容。
- RTT_GAME_DATA：所需对象与字段。
- AGENTS / HANDOFF：相关执行约束与实际状态。
- 其他已确认补充：来源及其适用范围。

## Scope

列出本任务包含的行为和允许修改文件/系统。

## Out of Scope

列出相邻但不包含的行为、系统和数据迁移。

## Design Authority

| 类别 | 具体条目及来源 |
| --- | --- |
| Locked | |
| Parameterized | |
| Developer Discretion | |

## Requirements

| ID | 必须满足的规则 | 来源 | 对应AC |
| --- | --- | --- | --- |
| REQ-01 | | | AC-01 |

## Data Dependencies

| 对象/字段 | 来源与状态 | 值/约束 | 缺失时处理 |
| --- | --- | --- | --- |
| | 已确认/未配置/不适用/临时许可 | | |

临时值填写批准依据、用途、有效范围、退出条件及DEVELOPMENT_CONTEXT引用。

## DATA Change Audit（正式DATA修改必填）

无正式DATA修改写N/A；沿用DATA Reference／Source Revision，见[DATA provenance](docs/DATA_PROVENANCE.md)。

| 文件 | 工作表 | 对象／行ID | 字段／单元格 | 修改前值 | 修改后值 | 原因 | 来源类型 | 来源证据 | Source Revision／版本 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

记录工作簿前后摘要及导出版本；未提交明确登记，提交后补真实commit。来源类型至少区分Project design decision、Formula-derived、Playtest/balance adjustment、External verified reference、Legacy derived baseline；后者限已采用历史截止点，不掩盖新改动。

## Dependencies

| Depends On | 所需交付物 | 最低状态/证据 |
| --- | --- | --- |
| 无或真实任务ID | | |

Blocks只由索引反向汇总，不作为第二套依赖源。

## Work Packages（可选）

| WP | 内容 | 当前进度 | 是否受阻 |
| --- | --- | --- | --- |
| WP-01 | | | |

## Acceptance Criteria

| ID | 给定条件 | 触发动作 | 可判定预期 | 验证方式 |
| --- | --- | --- | --- | --- |
| AC-01 | | | | 自动/人工/文档检查 |

按需增加拒绝、边界、同刻事件和确定性场景；不编造尚未确认的预期。

## Regression Risks

记录受影响系统、原因、必要回归项，以及可说明理由的不适用检查。

## Implementation Notes

记录工程选择、兼容/迁移影响、允许改动边界、回滚方法。

## Ready Review

参照TASK_WORKFLOW §5逐项记录Pass/Fail/N/A及依据。

DoR结论：未评审。
执行授权结论：代理按用户目标、AGENTS默认授权及明确暂停核验；仅缺失产品决策或高风险专项授权时提问。

## Blockers / Discovered Issues

| ID | 类别 | 证据与影响 | 阻塞范围 | 解除条件 | 关联任务 |
| --- | --- | --- | --- | --- | --- |

## Change Requests / Impact Review

记录CR决定、基线/DATA变化、受影响内容、采用版本、返工与验证范围。

## Verification

人工审查形式：用户明确指定的形式及原指令；未指定时必须两个真实客户端＋独立权威服务端，不得简化。记录三端准备／启停、完整检查清单、各端证据与实际状态；缺失入口或观测能力标Blocked／Not Verified，不能以隔离检查器替代。

| AC/检查 | 环境与版本 | 命令或复现步骤 | 预期/实际 | 结果 | 证据及时间 |
| --- | --- | --- | --- | --- | --- |

未执行检查标Not Run，不能写成Pass。

## Result

实际完成内容、修改文件、commit、限制及回滚办法。未完成时保持真实进度。

## Documentation Changes

| 文件 | 是否需改 | 实际变化/不需改的理由 |
| --- | --- | --- |
| DESIGN_BASELINE | | |
| RTT_GAME_DATA | | |
| DEVELOPMENT_CONTEXT | | |
| HANDOFF | | |
| TASKS | | |

## Done Review / Next Step

参照TASK_WORKFLOW §6记录证据。关闭结论、关闭时间、未解决问题和下一步。

## History

| 时间 | 状态/范围变化 | 依据 |
| --- | --- | --- |
