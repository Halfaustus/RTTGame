# RTTGame Development Instructions

## Document responsibilities and priority

- Development constraints regulate workflow, authorization, verification, version control, change management and delivery. They must not contain unit configurations, balance values, game mechanics, UI layouts or stage feature design.
- docs/DESIGN_BASELINE.md is the sole authority for game design. Read the actual working-tree file and its identifier; do not reconstruct missing design from chat summaries, historical implementation or old stage documents.
- docs/HANDOFF.md records actual implementation, verification, limitations and handoff. It is not a source of new design authorization. Historical records retain their original context and do not override the latest baseline.
- Within project documents, applicable development constraints take precedence over the design baseline. If they conflict, obey the constraints and report the conflict and impact. This does not permit inserting game design into constraints to override the baseline. Explicit user instructions govern the authorized task.
- Record the provenance, scope, limits and stage of autonomous choices. Distinguish formal values, explicitly authorized test configuration, temporary parameters and implementation details. Missing original authorization must be marked as not found; code existence, test success and handoff prose are not approval.
- The baseline's test-instance authorization does not authorize development during a pause, changing its framework or known formal values, or retroactively approving earlier decisions. Do not promote temporary values to formal design without explicit authorization.
- Do not discard unique project content removed during cleanup or silently migrate it into the baseline. Record its source and disposition for user review. Audit details: docs/DEVELOPMENT_CONSTRAINT_REVIEW.md and docs/AUTONOMOUS_DESIGN_REVIEW.md.

## Handoff maintenance

- Keep docs/HANDOFF.md as the current handoff summary: actual baseline and stage, completion and key verification conclusions, active limitations and blockers, next step and authorization boundary, and links to detailed records.
- Update the relevant current summary each round instead of appending long historical discussions, tables or logs. Judge size by whether a new agent can quickly identify the current state and authorized next step; do not impose a mechanical word limit.
- Reuse existing topic records for constraint reviews, conformity checks, authorization inventories and stage evidence. Before removing unique uncommitted detail from HANDOFF, migrate it into the appropriate record and verify preservation. Committed history may be traced through Git; do not assume uncommitted information is recoverable that way.
- Remove resolved issues from the current summary while preserving worthwhile historical evidence separately. Documentation checks do not constitute gameplay or manual acceptance.

## Project

RTTGame is a real-time tactics game built with Godot 4.7.2.

Primary language: GDScript.

Target platforms:
- Windows client
- Linux dedicated server

The project is designed around multiplayer from the beginning.

## Architecture

Use an authoritative dedicated-server architecture.

The server owns authoritative simulation state.

Clients send commands and requests to the server.

Clients must never directly determine authoritative:
- damage
- unit health
- armor state
- suppression state
- module damage
- ammunition
- supply
- repair state
- unit ownership

The server validates commands, advances simulation, and replicates results.

Do not assume the server is also a player.

The same Godot project must support both client and headless dedicated-server modes.

## Code separation

Keep simulation logic separate from presentation logic.

Simulation code must not depend on:
- camera
- HUD
- visual effects
- audio
- local player input

Do not place unrelated systems into one large Unit script.

Prefer composition and dedicated systems.

Major gameplay domains include:

- units
- movement
- combat
- armor
- suppression
- module damage
- logistics
- repair
- networking

## Networking

Use Godot MultiplayerAPI.

Initial transport:
ENet.

Clients issue commands.

Server validates and executes commands.

Replicate authoritative results back to clients.

Network messages should use explicit and stable data structures.

## Gameplay data

Prefer data-driven definitions over hard-coded unit statistics.

Unit, weapon, armor and faction definitions should be stored separately from runtime behavior.

Do not hard-code balance values throughout gameplay scripts.

## Development process

Before implementing a non-trivial feature:

1. Inspect the existing implementation.
2. Explain the proposed architecture.
3. Identify affected files.
4. Implement the smallest functional version.
5. Run relevant tests.
6. Report what changed and any remaining limitations.

Prefer small, reviewable changes.

Do not launch windowed or headless clients for testing unless the user explicitly requests client tests.
Use static checks, editor imports, and isolated simulation tests by default.

Do not perform broad refactors unless required.

Do not modify unrelated files.

Do not delete assets or project data without explicit instruction.

## Git

Do not rewrite Git history.

Do not force push.

Do not delete branches.

Do not commit generated build artifacts.

Keep commits focused on one logical change where practical.

“提交小版本总结” means outputting a summary only. It does not authorize Git commit
or push; either operation requires explicit user authorization for that operation.

## Performance

Do not prematurely optimize.

Use Godot Profiler before introducing complex optimizations.

Avoid unnecessary per-frame work.

Systems expected to scale with unit count should be designed with profiling and batching in mind.

## Scope and authorization

- Take the current implementation stage and verification status from docs/HANDOFF.md and actual evidence; do not store stage progress or gameplay rules in this file.
- Start or resume implementation only within the user's current authorized scope. A later pause overrides earlier development authorization; do not choose the next stage automatically.
- Preserve existing results, interfaces and uncommitted work. Report incompatible design changes before changing code, configuration or tests; a documentation audit does not authorize implementation repair.
- Preserve authenticated ownership and private-state boundaries. Do not use connection identities as substitutes for domain identities or expose private state through unrelated replication or replay channels.
- When changing execution order or compatibility-sensitive interfaces, establish the existing contract and verify the affected frozen replay boundaries. Do not silently change those contracts.
- Historical acceptance criteria and unique project decisions removed from constraints remain review items in docs/DEVELOPMENT_CONSTRAINT_REVIEW.md; removal does not authorize deleting their implementation or treating them as newly approved design.

## Replay compatibility

Every major development release (including new Prototype 0.x stages) MUST run replay
compatibility validation before acceptance. Keep frozen fixtures for each supported
format version and run their read, validation, round-trip, checkpoint/event-boundary,
and presentation checks. Do not regenerate old fixtures to make a failing check pass.

Changes to replay structure or field semantics require an explicit format-version
decision, documented compatibility/migration policy, and a new fixture when needed.
Unknown format versions must fail clearly; never silently load them as the current version.
Map/rules identifiers and content fingerprints must be checked before a future player
loads presentation assets. State/event replay must never depend on input resimulation,
live connections, local AI, damage calculation, or authoritative spawning.

Report supported/unsupported versions, automatic results, and unverified manual items
separately. Successful serialization tests are not full replay recording or playback acceptance.

## 验证与汇报约定

以下约定替换旧的“每轮仅输出人工验证清单、验证证据、启动／停止命令”要求。
小版本指 0.4A、0.4B 等阶段；大版本指完整的 0.4、0.5 等版本。

- 小版本开发仅执行相关自动验证与必要回归，不要求人工验收；不输出人工验证清单或详细启动／停止命令。
- 人工验收统一安排在每个大版本结束时，届时提供完整人工验证清单（操作步骤、预期结果、实际状态）、验证证据及准确启动／停止命令。
- 小版本最终回复只需简要总结完成内容、自动验证结果、已知限制与下一步。
- 自动验证与人工验收分别记录。未执行人工验收时，不得宣称人工通过或整个大版本已验收；自动通过不等于人工通过。
- 每个大版本仍须执行现有冻结回放夹具兼容性检查，遵守上方 Replay compatibility 约束；小版本涉及兼容性时按相关自动回归验证。
- “提交小版本总结”仅指输出总结，不代表授权 Git commit 或 push。

## Design baseline

- Validate capabilities, command eligibility and configuration against the actual baseline and explicit authorization. Report missing implementations; do not silently grant unsupported capabilities.

- From 0.5B, fill missing non-principled implementation parameters with the
  smallest functional configuration. Never override formal values, invent
  mechanisms, change authority/economy/unit semantics or expand stage scope.
  Centralize parameters and report each name/value/purpose/rationale and whether
  adjustment is suggested at minor-version closure. Unopposed values may carry
  forward without asking again, but are not permanent design; later baseline
  values take precedence. Missing design decisions/conflicts must be reported. Explicit authorization for test instances may permit choices beyond numerical parameter completion, but only inside its stated framework, stage and limits; never infer that authorization from existing code or passing tests.
- docs/DESIGN_BASELINE.md is the only design authority. Read the actual local development file; never assemble design from other conversations.
- Before each major version, review that baseline and establish the stage scope. Minor versions inherit it. Read relevant changes whenever the user explicitly updates the baseline.
- Report missing or conflicting design; do not invent additions. HANDOFF.md records actual implementation and validation status.
- Minor versions require related automatic checks and necessary regressions only. Major closure requires frozen replay compatibility and a complete manual checklist with exact start/stop commands.
- Keep automatic verification separate from manual acceptance. A summary never authorizes Git commit or push.
