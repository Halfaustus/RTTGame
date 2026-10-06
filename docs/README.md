# GreyLine Taskforce / 灰线战术群 文档入口

内部代号：GREYLINE / 灰线。正式名称与历史工程标识的边界见[项目命名约定](PROJECT_NAMING.md)；本地同步见[Codex 提示词](LOCAL_CODEX_NAMING_PROMPT.md)。

从[设计基线](constraints/DESIGN_BASELINE.md)、[当前交接](records/HANDOFF.md)与[开发规划](DEVELOPMENT_ROADMAP.md)进入。基线标识DB-2026-10-06-40，所属正文按领域拆分。根目录[AGENTS.md](../AGENTS.md)负责开发流程与实现约束。

## 文档职责

| 文件／目录 | 用途与边界 |
| --- | --- |
| [DESIGN_BASELINE.md](constraints/DESIGN_BASELINE.md) | 唯一规则入口、所属正文目录、原章号定位与优先关系 |
| [配置定义](constraints/design/UNIT_CONFIGURATION.md)／[局外作战群](constraints/design/OUT_OF_MATCH.md) | 基体、配置、武器／弹药、安装关联；专精、预算和单位卡 |
| [部署经济](constraints/design/DEPLOYMENT_ECONOMY.md)／[移动任务](constraints/design/MOVEMENT_COMMANDS.md) | 局内账户、出动、退款、生成；移动、队形、队列与占位 |
| [战斗](constraints/design/COMBAT_RULES.md)／[弹丸](constraints/design/PROJECTILES.md) | 伤亡、防护、武器、能力与炮击；弹道、碰撞、友伤与公开表现 |
| [运输后勤](constraints/design/TRANSPORT_LOGISTICS.md)／[场景隐蔽](constraints/design/WORLD_VISIBILITY.md) | 装卸、撤离、补给、修复；驻扎、掩体、观察与暴露 |
| [界面输入](constraints/design/UI_INPUT.md)／[合作任务](constraints/design/MATCH_MISSION.md) | 兵牌、HUD、键位；合作、掉线、25分钟任务与平衡目标 |
| [待定与冲突](constraints/design/PENDING_DECISIONS.md)／[长期PVP](constraints/design/FUTURE_PVP.md) | 缺失设计与冲突单一登记；PVP不影响当前PVE范围 |
| [RTT_GAME_DATA.xlsx](RTT_GAME_DATA.xlsx) | 已确认实例数据；具体性能不在设计另存表，本轮不修改工作簿 |
| [HANDOFF.md](records/HANDOFF.md)／[DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md) | 实际状态与下一步／未来版本依赖；规划不授权开工 |
| [AUTONOMOUS_DESIGN_REVIEW.md](AUTONOMOUS_DESIGN_REVIEW.md) | 独立人工授权复核，不是规则或执行来源，本轮不修改 |

有效规则在所属正文维护一次；具体正式配置在DATA，协议字段在技术契约，当前表现参数在表现说明。交接只保留必要结论和链接。历史阶段的测试值、授权来源、测量及当时结论保留原语境，不合并为现行规则。

## 技术契约

- [弹丸C类工程设计](constraints/PROJECTILE_SIMULATION_C_DESIGN.md)：已授权工程决定、误差与接口；未统一项见第22节。
- [公开载荷契约](constraints/PROJECTILE_VISIBILITY_CONTRACT.md)：字段白名单、权限、身份和生命周期；视觉值引用表现说明。
- [冻结回放格式](constraints/REPLAY_FORMAT_V1.md)、[录制](constraints/REPLAY_RECORDING.md)、[播放](constraints/REPLAY_PLAYBACK.md)：v1接口及兼容边界，不代替新活动战斗规则。

## 审查与验收记录

- [表现实现说明](records/PROJECTILE_PRESENTATION_REVIEW.md)：数据流与插值／曳光参数来源。
- [DB37复检](records/DB37_MANUAL_RECHECK.md)：近程裁剪、相机、M252测量和自动证据。
- [客户端验收](records/CLIENT_PROJECTILE_ACCEPTANCE.md)：当前双端步骤、预期、待验状态与精确启停命令。
- [玩家扩展检查](records/PLAYER_EXTENSIBILITY_REVIEW.md)：扩展基础与未来待办，不授权新模式。
- [DB33审查](records/DB33_IMPLEMENTATION_REVIEW.md)：历史预期纠正和接替验证。
- [0.5A](records/PROTOTYPE_05A.md)、[0.5B](records/PROTOTYPE_05B.md)、[0.5C](records/PROTOTYPE_05C.md)、[0.5D](records/PROTOTYPE_05D.md)、[0.5E](records/PROTOTYPE_05E.md)、[0.5F](records/PROTOTYPE_05F.md)：历史阶段与临时参数，不覆盖现行状态。
- [CONTEXT_HANDOFF](records/CONTEXT_HANDOFF.md)：旧会话归档，保留来源及中断语境。

原始测试日志在 `tmp/`。本轮未删除历史记录、源码、资产或夹具，未改写历史结论。文档检查不构成游戏或人工验收。

## 缺失与外部资料

- `RTTGame_DESIGN_PRINCIPLES.md`、`DEVELOPMENT_CONTEXT.md`缺失，不按职责说明补造内容。
- 旧文档仍含缺失阶段文件和 `RTT_WEAPON_BALANCE.xlsx` 的历史引用，不恢复已删除资料或改指不等价来源。
- `DataBaseCompiled-resources.assets-15820.json`为外部资源数据；第24节仅采纳明确列出的关联组织约束，其余性能／行为不进入本项目规则或正式DATA。
- 根目录[PROJECTILE_SIMULATION_C_DESIGN.md](PROJECTILE_SIMULATION_C_DESIGN.md)仅是旧链接导航，为未获维护授权的自主复核清单保留，不存设计副本。
