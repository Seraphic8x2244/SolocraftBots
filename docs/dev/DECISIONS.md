# SoloCraftBots Architectural Decisions

This log records decisions that are easy to lose if only discussed in chat. Keep entries short and factual. If a decision changes, add a new entry and explicitly state that it supersedes the old one.

## 2026-09-10 - 0.7.14 becomes behavioural reference for 0.8 consolidation

Decision:
- Treat 0.7.14 as the known-good behaviour baseline while restructuring 0.8.x.
- Audit and document before functional refactoring.
- Use the dev branch for audit documents and later 0.8.x implementation.

Reason:
- The addon has accumulated several late wrapper/override files and hidden TOC-order dependencies.
- The risk is no longer just individual bugs; it is losing track of which module actually owns behaviour.

## 2026-09-10 - Repository documentation is the project memory

Decision:
- Do not rely on ChatGPT conversation memory as the only source of architectural context.
- Maintain `ARCHITECTURE.md`, `CONSOLIDATION-0.8.md`, `BEHAVIOUR-BASELINE.md`, and this file in the repository.

Reason:
- A new conversation or developer must be able to recover the project state and reasoning directly from GitHub.

## 2026-09-10 - Preset group is intent; same-group Blizzard row is presentation

Decision:
- Human raid subgroup assignment is durable preset intent.
- Blizzard changing only the row/ordinal inside the same subgroup is transient live presentation.
- Same-group row reorder must not mark the preset Unsaved.
- The preset editor should display the live character in Blizzard's current row and signal the mismatch visually.
- 0.7.14 uses a pulsing green background and tooltip: `Not in preset location due to Blizzard raid handling`.
- A genuine subgroup change remains a semantic preset change.

Supersedes:
- Earlier behaviour where every Blizzard raid row permutation was written into the working preset and marked Unsaved.

Reason:
- Treating Blizzard presentation order as preset content conflated live UI ordering with user-authored raid composition.
- Trying to infer whether a particular reorder was manual or automatic is unreliable.

## 2026-09-10 - Combat role confirmation is optional validation

Decision:
- Assumed/requested role is sufficient for normal operation.
- Combat-derived role confirmation is an optional diagnostic feature and defaults OFF.
- When OFF, combat scanning should be unregistered rather than merely ignoring results.
- When ON, confirmed bots stop being scanned individually and the scanner sleeps when no unresolved tracked bots remain.

Supersedes:
- Earlier assumption that combat confirmation should be part of the normal always-on role-resolution path.

Reason:
- The summoner/identity system now provides enough role intent for normal behaviour, while high-volume combat-text scanning is expensive in large raids.

## 2026-09-10 - Identity should be explicit, not timestamp-derived

Decision:
- Same-burst identity/order comes from explicit burst plans.
- Do not use equal/near `GetTime()` values to infer summon ordering.
- Name-bound identity becomes authoritative after a bot is bound.

Reason:
- SoloCraft processes same-burst summon commands reverse/LIFO, and timestamp heuristics are too weak to establish exact identity reliably.

## 2026-09-10 - Cross-burst pending identity is a structural concern

Decision:
- The current global `pendingAssumedSpawns` queue is not accepted as the desired final 0.8 architecture.
- Audit exact current behaviour before replacing it.
- Target direction is per-burst identity isolation and failure-safe reconciliation rather than allowing leftover intents to spill into later bursts.

Reason:
- Immediate wrong-role pfUI tank icons after spawning indicate that wrong assumed-role/name binding is possible before combat evidence is involved.

## 2026-09-10 - Do not silently preserve questionable fallbacks during consolidation

Decision:
- Roster-delta identity binding, legacy command/group matching, old scheduler flags, and other compatibility paths must be audited and justified individually.
- Do not automatically carry them into 0.8 merely because they exist in 0.7.14.
- Equally, do not delete them until their current role is understood.

Reason:
- Some fallbacks may be protecting real Vanilla/SoloCraft races; others may be creating competing ownership and race conditions.

## 2026-09-10 - Consolidation before new feature growth

Decision:
- 0.8.x is primarily a structural consolidation line.
- Avoid meaningful new UX/features until core ownership and lifecycle consolidation are proven, unless specifically agreed.

Reason:
- Continuing to add isolated files/wrappers would increase fragmentation and make later debugging harder.
