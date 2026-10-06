# GreyLine Taskforce Development Instructions

## Document responsibilities and priority

- Development constraints regulate workflow, authorization, verification, version control, change management and delivery. They must not contain unit configurations, balance values, game mechanics, UI layouts or stage feature design. Current stage and pause status belong in the actual repository HANDOFF.md; do not fix them in this file.
- docs/constraints/DESIGN_BASELINE.md is the sole entrypoint for current game rules; its explicitly listed normative modules form that baseline and are not independent authorities. docs/RTTGame_DESIGN_PRINCIPLES.md explains design intent, roles, balance targets and rationale; it does not independently authorize implementation or override the baseline. Read the actual working-tree file and its identifier; do not reconstruct missing design from chat summaries, historical implementation or old stage documents.
- docs/records/HANDOFF.md records actual implementation, verification, limitations and handoff. It is not a source of new design authorization. Historical records retain their original context and do not override the latest baseline.
- Within project documents, applicable development constraints take precedence over the design baseline. If they conflict, obey the constraints and report the conflict and impact. This does not permit inserting game design into constraints to override the baseline. Explicit user instructions govern the authorized task.
- Record the provenance, scope, limits and stage of autonomous choices. Distinguish formal values, explicitly authorized test configuration, temporary parameters and implementation details. Missing original authorization must be marked as not found; code existence, test success and handoff prose are not approval.
- The existing test-instance authorization does not authorize development during a pause, changing its framework or known formal values, or retroactively approving earlier decisions. Do not promote temporary values to formal design without explicit authorization.
- When a constraint contains a still-effective game-design decision, removing it from this file does not revoke that decision. If the user explicitly authorizes writing it into the baseline, do so and report the result. Otherwise report the decision and its current source, retain it as a current unresolved item, and request only the missing disposition when necessary. Do not implement the opposite behavior or classify an active rule as disposable history. A newer explicit user decision may supersede it.

## Autonomous design authorization review maintenance

docs/AUTONOMOUS_DESIGN_REVIEW.md is a separate checklist for manual review of autonomous design authorization.

Whenever the user explicitly states that Codex may design autonomously, automatically update the checklist to record the source, scope, limits and decisions made under that authorization. If no decisions have been made at the time of authorization, mark them as not yet designed; add decisions actually made within the same authorized task when delivering the task.

Except for checklist maintenance tasks explicitly authorized by the user, do not add, modify, delete, reorganize, archive or automatically refresh the checklist without new explicit authorization for autonomous design. Continued use of existing authorization, baseline updates, implementation changes, passing tests, routine handoffs and the absence of user objections do not trigger checklist updates.

The checklist is solely for the user's manual review. It is not a design baseline, development instruction, source of execution authorization or basis for automatic acceptance. Its records do not automatically formalize temporary designs, lift a pause or expand development scope.

Keep the checklist body separate; do not merge it into the baseline, HANDOFF or other files. Inspection tasks may read it, but must not modify it without update authorization.

## Current documents and history

- docs/constraints/DESIGN_BASELINE.md and docs/records/HANDOFF.md are current-state documents. Neither file is required or permitted to accumulate historical records: do not keep change logs, superseded rules, resolved-conflict histories, per-stage result ledgers, past handoff narratives or chronological work logs in them.
- Keep the baseline limited to current effective design, explicit pending decisions and unresolved conflicts. Replace superseded wording directly; remove resolved conflict entries after updating the effective rules. Keep its current identifier and applicable metadata without appending a version history.
- Keep HANDOFF limited to current implementation status, key verification conclusions, active limitations and blockers, current authorization boundaries, the authorized next step and necessary links. Remove resolved or superseded entries instead of adding another historical paragraph. Current unverified acceptance items are active status and must remain visible.
- No separate preservation of removed history is required: do not create or update history files, append archives, or migrate old narratives merely to retain them. Historical logs, superseded rules and resolved issues may be removed from these two current-state documents without another archival step. Existing Git history needs no additional copy.
- This cleanup does not authorize deleting separate files, frozen fixtures, source code or unrelated project data. Current effective rules, unresolved authorization evidence, active blockers and unverified acceptance obligations are not historical clutter; retain the information needed for current decisions.
- Update current summaries each round and keep them easy for a new agent to read; do not impose a mechanical word limit. Documentation checks do not constitute gameplay or manual acceptance.

## Project

GreyLine Taskforce / 灰线战术群 (internal codename: GREYLINE / 灰线; historical repository identifier: RTTGame) is a real-time tactics game built with Godot 4.7.2.

Project naming is maintained in docs/PROJECT_NAMING.md. Branding does not authorize renaming compatibility-sensitive identifiers or changing gameplay.

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

Command authority and replication responsibilities follow "Architecture" above.

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

Commit and push require explicit user authorization for each operation. Summary and verification conventions are defined in "Verification and reporting conventions".

## Performance

Do not prematurely optimize.

Use Godot Profiler before introducing complex optimizations.

Avoid unnecessary per-frame work.

Systems expected to scale with unit count should be designed with profiling and batching in mind.

## Scope and authorization

- Take the current implementation stage and verification status from docs/records/HANDOFF.md and actual evidence; do not store stage progress or gameplay rules in this file.
- Start or resume implementation only within the user's current authorized scope. A later pause overrides earlier development authorization; do not choose the next stage automatically.
- Preserve existing results, interfaces and uncommitted work. Report incompatible design changes before changing code, configuration or tests; a documentation audit does not authorize implementation repair.
- Preserve authenticated ownership and private-state boundaries. Do not use connection identities as substitutes for domain identities or expose private state through unrelated replication or replay channels.
- When changing execution order or compatibility-sensitive interfaces, establish the existing contract and verify the affected frozen replay boundaries. Do not silently change those contracts.
- Only still-effective acceptance obligations and unresolved project decisions remain current review items. Completed, superseded or resolved records do not require archival retention. Removing text does not by itself authorize deleting code, fixtures or changing the corresponding game behavior.

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

## Verification and reporting conventions

The following conventions replace the previous requirement to "output only a manual verification checklist, verification evidence and start/stop commands in each round."
Minor versions refer to stages such as 0.4A and 0.4B; major versions refer to complete versions such as 0.4 and 0.5.

- Minor-version development requires only relevant automatic verification and necessary regression checks. Manual acceptance is not required; do not output a manual verification checklist or detailed start/stop commands.
- Perform manual acceptance at the end of each major version. At that point, provide a complete manual verification checklist (steps, expected results and actual status), verification evidence and exact start/stop commands.
- The final response for a minor version only needs a brief summary of completed work, automatic verification results, known limitations and the next step.
- Record automatic verification and manual acceptance separately. If manual acceptance has not been performed, do not claim that it passed or that the entire major version has been accepted; passing automatic verification does not mean passing manual acceptance.
- Each major version must still undergo compatibility checks using the existing frozen replay fixtures and comply with the Replay compatibility constraints above. Minor versions that affect compatibility must undergo the relevant automatic regression checks.
- "Submit a minor-version summary" means outputting a summary only; it does not authorize Git commit or push.

## Design baseline

- Validate capabilities, command eligibility and configuration against the actual baseline and explicit authorization. Report missing implementations; do not silently grant unsupported capabilities.

- From 0.5B, fill missing non-principled implementation parameters with the
  smallest functional configuration. Never override formal values, invent
  mechanisms, change authority/economy/unit semantics or expand stage scope.
  Centralize parameters and report each name/value/purpose/rationale and whether
  adjustment is suggested at minor-version closure. Unopposed values may carry
  forward without asking again, but are not permanent design; later confirmed
  DATA values take precedence. Missing design decisions/conflicts must be reported. Explicit authorization for test instances may permit choices beyond numerical parameter completion, but only inside its stated framework, stage and limits; never infer that authorization from existing code or passing tests.
- Before each major version, read the actual baseline entrypoint and all modules relevant to the authorized stage, and establish its scope. Minor versions inherit it. Read relevant changes whenever the user explicitly updates the baseline; never assemble design from other conversations. A development roadmap proposes sequencing and does not authorize starting or resuming a stage.
- Report missing or conflicting design; do not invent additions. HANDOFF.md records actual implementation and validation status.

## Existing test-instance authorization

Since DB-2026-10-04-21, unless the user explicitly revokes, prohibits or narrows it, Codex may autonomously create test units of any type, weapon squads and test configurations within the user's existing defined framework without individual approval. Within permitted fields, ranges and rules, this covers not-yet-determined instance parameters such as personnel count, protection, roles, weapons, ammunition, range, damage, penetration, suppression, dispersion, aiming, rate of fire and reload time.

This authorization does not permit changing, extending, deleting or reinterpreting the defined framework, including unit and weapon attributes, damage formulas, transport rules, capability tag categories, weapon slots or other confirmed mechanics. Test needs do not override formal rules, general values or confirmed independent weapon performance. Objects explicitly marked as test-only may be adjusted or removed within the same framework.

Every autonomously created object not formally confirmed by the user must be recognizably marked as test-only in data, documentation, prototype/handoff records or a test interface. Implementation, repeated use and successful verification do not formalize it. It may be removed during formal-release cleanup; only explicit user confirmation makes it formal design.

This section preserves existing authorization moved from DB-2026-10-05-27. The document split is not new autonomous-design authorization, does not trigger an update to AUTONOMOUS_DESIGN_REVIEW.md and does not lift any pause.

## Current task scope lookup

Read current scope, deferrals and pause/resume status from explicit user instructions and the actual repository HANDOFF.md. Carried source records in docs/DEVELOPMENT_CONTEXT.md preserve unresolved context for reconciliation; they are not a verified repository handoff and do not authorize resuming work. Do not remove an effective restriction merely because it was moved between documents.

## Baseline document maintenance details

Prompts specify the current task scope and new changes; do not duplicate the complete rules into another baseline. For unresolved baseline conflicts, record the conflicting clauses, reason, applicable scope, current handling and pending confirmation in the baseline's listed PENDING_DECISIONS.md section 22; do not duplicate the register in its entrypoint. After resolution, update effective rules and remove the current conflict entry without creating a history archive. Do not fabricate HANDOFF progress or claim a document change has been applied to an unknown repository.

## Confirmed DATA and missing configuration

Use docs/RTT_GAME_DATA.xlsx for confirmed instance data and the baseline for game mechanisms and mechanism constants. Preserve user-confirmed configurations and their recorded values even when some fields remain incomplete. Do not reclassify a confirmed object as a test fixture solely because it was previously used for validation.

"Unconfigured" (the workbook's first missing-value marker) means the field applies but still needs configuration. "Not applicable" (the workbook's second marker) means the field does not apply to that object. Neither means zero. Do not automatically supply values, treat missing configuration as an enabled capability or promote temporary test values to confirmed data. Keep authorized temporary/test configurations outside formal DATA, explicitly identified.

## Existing implementation constraints

Preserve the implementation constraints below that were moved from the baseline. Moving them does not authorize an implementation refactor, change gameplay rules or lift a pause.

- Precompute and cache kinetic decay coefficients at load/configuration initialization. Evaluate penetration on impact, not on every flight frame. Cache ammunition references and complete-step gravity increments; share unit motion information per step.
- For explosions, cache squared radius and inverse squared radius; reuse squared-distance queries. Restrict nearby-object queries and avoid duplicate queries or settlement. Preserve the confirmed squared-distance polynomial rather than changing it to save a multiplication.
- Manage projectiles centrally in compact reusable storage rather than creating a separate rigid-body/physics node per projectile. Clear source and ignore state on reuse, distinguish slot generations and never silently discard a legal shot because capacity is exhausted.
- Sample dispersion and solve firing conditions at actual firing time. Update motion, collision paths and distance during flight; calculate impact damage and explosion effects on impact. Use spatial filtering before precise tests; maintain event time order without sorting all live projectiles.
- Do not introduce ammunition-specific update frequencies, multilevel pools or penetration lookup tables under the existing scope. Do not run unused capability modules or retain unused state. Use the approved analytical vector solution without adding unnecessary angle trigonometry; verify actual weapon orientation through the firing system.
