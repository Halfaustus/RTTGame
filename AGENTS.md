## 长期开发授权与风险边界

### 默认授权

在用户提出的项目目标和任务范围内，agent 默认获得持续有效的开发授权，应自主完成读取、分析、规划、实现、验证、纠错和迭代，直到任务完成或遇到确实无法自行解决的阻塞。

授权涵盖项目源码、配置、资源、文档和测试的读取、创建、修改、重构、移动、替换与删除，以及依赖管理、构建、导入、测试、调试和常规开发命令。允许按验证需要启动、停止本任务的本地客户端和独立服务器，包括窗口及无窗口模式。

用户已专项授权今后为本项目人工验证启动客户端和必要的本地独立服务器，包括需要沙箱外执行的桌面窗口启动，无需重复取得项目授权。此授权不取消平台审批机制；优先复用针对固定项目启动脚本的持久批准规则，不申请通用 shell 执行权限，不扩大到其他沙箱外操作。

上述行为是示例，不是封闭白名单。完成任务合理必要的同类工程操作、跨文件修改及依赖修复，均包含在默认授权中，不得因未逐项列出而反复要求人工确认。

未经用户明确批准，不得创建 Git 提交。向既有开发仓库进行非强制推送的授权不免除提交审批要求，且不得触发生产部署、泄露敏感信息或覆盖他人工作。

### 自主执行要求

计划、架构说明、任务卡、就绪检查、进度汇报和测试报告用于记录与质量控制，不构成逐步骤审批门槛。

不得仅因文件数量较多、需要重构、需要删除可恢复的旧资源、需要启动测试进程、命令失败或需要重试而请求再次授权。

已有授权在相同目标和范围内持续有效，不因会话切换、任务状态变化或阶段性汇报而失效。必要工程选择由 agent 自主决定，并在交付时说明实质变化和验证结果。

保留项目架构、正式数据、接口契约、原创性、隐私及测试要求。不得将临时测试值自动转为正式数据，不得通过删除断言、重建冻结夹具或降低验收标准掩盖失败。

确实缺少玩法、正式数值或其他产品决策时，先完成可独立推进的工作，再集中提出缺失决策；不将普通工程选择包装为审批请求。明确暂停、延期和范围排除继续有效。

### 少数高风险操作

以下操作不属于默认授权，执行前必须取得针对具体目标、范围和影响的明确授权；已有同范围专项授权无需重复请求：

1. 可能造成不可恢复损失的操作，包括删除仓库、清空磁盘或数据库、丢弃无恢复副本的未提交成果。
2. 改写共享 Git 历史、强制推送或删除包含独有成果的分支。
3. 生产部署、正式公开发布、软件包发布、生产数据迁移。
4. 变更账户权限、访问控制、安全策略、计费设置，或对外部用户、服务及第三方产生重大影响的操作。

禁止将密码、令牌、私钥等敏感凭据写入代码、日志或公开内容。凭据向其预定服务的正常认证使用不需要逐次确认；向其他目的地转移敏感信息必须核实合法授权、接收方、用途和安全渠道，禁止的披露不得执行。

可恢复的项目文件删除、旧资源替换和任务自有临时文件清理，不等同于不可恢复破坏，应在核对引用和恢复方式后自主完成。

### 阻塞与环境权限

确需确认时，先完成安全且已授权的准备工作，提供具体操作、目标、影响和恢复限制，只暂停受影响部分。

用户已授权将封闭、可收窄的运行环境权限用于本项目开发。该授权以运行环境能够强制限定具体资源、操作和权限上限为前提；agent可在既定边界内派生更小权限，完成任务合理必要的操作，无需逐项重复取得项目授权。不得因权限错误、命令失败或重试扩大访问目标、操作范围或权限上限。

每次使用上述授权时，应核对环境实际提供的权限边界，采用完成任务所需的最小范围。AGENTS.md本身不授予操作系统或沙箱权限；以当前账户全部权限执行的普通“沙箱外执行”不能仅凭本文件认定为封闭授权，仍须遵循平台的审批机制。不能强制限定范围的操作，不自动纳入此项环境授权。

本说明不能覆盖操作系统、运行环境沙箱、网络策略、连接器权限或组织强制政策。遇到环境限制时使用正常授权机制或允许的替代方案，不得绕过访问控制。

如果仍需用户处理，应明确说明是项目决策缺失还是运行环境限制，并指出具体受阻操作，避免重复提出笼统授权请求。

# RTT Development Workflow

## Roles

- Main coordinator: GPT-6.1 Sol, Medium by default and High for complex tasks
- Implementation worker: GPT-6.1 Sol, Medium by default and High for complex tasks
- Independent reviewer: GPT-6 Luna with Medium for ordinary tasks; GPT-6.1 Sol with High for complex or high-risk tasks

The global setting `agents.max_concurrent_threads_per_session = 5` allows up
to five concurrent subagents, excluding the main coordinator (six agents in
total). These responsibilities do not require named custom-agent definitions
and do not impose an instance limit. Respect any lower runtime limit.
Only parallelize independent tasks with non-overlapping file scopes; prefer
sequential execution when tasks share files.

## Workflow

For development tasks, follow this process:

### Phase 1: Planning (Sol)

1. Inspect the relevant code and dependencies.
2. Identify requirements and constraints.
3. Prepare a minimal implementation plan.
4. Split work into small, independent tasks.
5. Define allowed files and acceptance criteria.

Do not delegate ambiguous tasks.

### Phase 2: Implementation (Sol)

1. Delegate suitable coding tasks to an implementation subagent.
2. Supply the relevant plan and file scope.
3. Require focused changes and tests.
4. Collect the implementation report.

Prefer sequential execution when tasks share files.

If the task involves complex architecture, networking,
or deterministic simulation, Sol may implement it directly.

### Phase 3: Independent Review (Luna / Sol)

1. Delegate the completed implementation to an independent review subagent.
2. Check changes against the plan.
3. Inspect tests and relevant regressions.
4. For CHANGES REQUIRED, send bounded corrections to the implementation subagent.
5. For BLOCKED, resolve the design conflict, missing decision or validation blocker before proceeding.
6. Perform incremental review after corrections.

Review conclusions follow the global AGENTS.md:
- PASS: the review passed; the coordinator checks acceptance conditions.
- CHANGES REQUIRED: bounded implementation corrections and incremental review are required.
- BLOCKED: a design conflict, missing decision or validation blocker requires coordinator resolution.

The main Sol coordinator makes the final decision.

## Project Constraints

- Preserve existing module boundaries.
- Avoid unrelated refactoring.
- Do not change save formats without approval.
- Do not introduce nondeterministic simulation behavior.
- Protect multiplayer synchronization compatibility.
- Do not delete user data or discard existing changes.
- Do not create Git commits without approval.

## Completion Requirements

A task is complete only after:
- Implementation is finished.
- Relevant tests pass, or test limitations are reported.
- The independent review required by the global AGENTS.md passes.
- Remaining risks are documented.

## Subagent Invocation

Use ordinary subagents with explicit responsibilities and bounded task context;
do not depend on named custom-agent configuration files. Multi-agent defaults
and the concurrent-subagent limit remain in the global `config.toml`.

When the runtime supports explicit model and reasoning-effort selection, use
`gpt-6.1-sol` for implementation, `gpt-6-luna` with Medium for ordinary
independent review, and `gpt-6.1-sol` with High for complex/high-risk review,
following the latest global AGENTS.md. Use Medium by default and High for
complex implementation. These instructions do not change the live model or
global config.toml; report the actual tool invocation rather than a target setting. Respect the runtime's context-forking
requirements when supplying overrides. A task name alone does not select a
model or load instructions. Provide the corresponding responsibility boundaries
explicitly. Use a fresh review context containing the plan, file scope,
acceptance criteria and validation evidence; the reviewer must independently
inspect actual changes, remain read-only, and return PASS, CHANGES REQUIRED
or BLOCKED.

If the required model or delegation tool is unavailable, report the limitation
and leave the independent-review requirement pending. Do not report coordinator
self-review as a passed independent review.
