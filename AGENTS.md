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

## Performance

Do not prematurely optimize.

Use Godot Profiler before introducing complex optimizations.

Avoid unnecessary per-frame work.

Systems expected to scale with unit count should be designed with profiling and batching in mind.

## Current development phase

The current target is Prototype 0.1.

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

## Acceptance output contract

From now on, final acceptance output must contain only these three sections:

1. 人工验证清单: concrete operation steps, expected results, and actual status.
2. 验证证据: necessary log or screenshot locations, with unverified items stated explicitly.
3. 准确的启动／停止命令: copyable commands using the actual saved scripts and parameters.

Do not append development history, change summaries, or unrelated environment information.
Put issues that affect acceptance in the relevant checklist item and supporting evidence.
Keep script/automated verification separate from user-performed gameplay acceptance;
never label successful script verification as manual gameplay acceptance.
