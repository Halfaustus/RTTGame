# RTTGame Development Instructions

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

## Current development phase

The current target is Prototype 0.4D: authoritative upkeep, economic lifecycle and
0.4 closure on the existing 0.4A/B/C deployment interfaces. Prototype 0.2 has
been manually accepted and saved.
Prototype 0.3A establishes state/event replay data; 0.3B adds full server recording.
Prototype 0.3C adds minimal offline 1x playback; its manual acceptance remains pending.
Further replay work (including seeking), reconnection and match-history features are deferred.
Preserve the existing results and interfaces; resume only after the user sets a new scope.
Recording success or automatic playback checks are not manual playback acceptance.
Preserve the existing test spawning entry. 0.4C executes ground countdown/search/waiting
and spawning; 0.4D adds authoritative upkeep and closes the economy loop. Blocked orders retain cost and reservation.
Use match player_id for accounts; peer IDs only authenticate connections. Economy and
orders replicate only to their owner. Do not append these domains to RTTReplay v1.
Deployment and value scores are independent non-negative integers divisible by five;
reject invalid values without rounding. Maintenance and account accumulation may be fractional.
While holding a deployment card, left click places it and right click/E cancels it;
ordinary selection/movement must not receive those inputs. Esc retains its existing behavior.
Only one card may be held; multiple placed orders are permitted. Ground countdown is
three seconds on server ticks; air six-second configuration is reserved only. Pickup
pauses eligibility and replacement restarts the full countdown. Deployment adjudication
and spawning run in session before movement commands to preserve frozen v1 spawn phases.
Do not add air units, transport, return-to-base refunds, replay extensions or reconnection in 0.4D.

Prototype 0.1 must demonstrate:

1. Headless dedicated server startup.
2. Two local clients connecting to the server.
3. Server-authoritative unit ownership.
4. Client unit selection.
5. Client movement command.
6. Server command validation.
7. Server-authoritative movement.
8. Replication of the resulting unit state to both clients.

Do not implement advanced combat systems until this networking and movement loop works reliably.

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

- docs/DESIGN_BASELINE.md is the only design authority. Read the actual local development file; never assemble design from other conversations.
- Before each major version, review that baseline and establish the stage scope. Minor versions inherit it. Read relevant changes whenever the user explicitly updates the baseline.
- Report missing or conflicting design; do not invent additions. HANDOFF.md records actual implementation and validation status.
- Minor versions require related automatic checks and necessary regressions only. Major closure requires frozen replay compatibility and a complete manual checklist with exact start/stop commands.
- Keep automatic verification separate from manual acceptance. A summary never authorizes Git commit or push.
