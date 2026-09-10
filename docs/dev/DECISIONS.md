# SoloCraftBots Architectural Decisions

This log records decisions that are easy to lose if only discussed in chat. Keep entries factual. If a decision changes, add a new entry and explicitly state what it supersedes.

## 2026-09-10 - 0.7.14 is the behavioural reference for 0.8 consolidation

Decision:
- Treat 0.7.14 as the known-good behaviour reference while restructuring 0.8.x.
- Audit/document before functional refactoring.
- Use `dev` for audit documents and later 0.8.x implementation.

Reason:
- The addon accumulated late wrappers/overrides and hidden TOC-order dependencies.

## 2026-09-10 - Repository documentation is project memory

Decision:
- Do not rely on ChatGPT conversation memory as the only architectural record.
- Maintain `ARCHITECTURE.md`, `CONSOLIDATION-0.8.md`, `BEHAVIOUR-BASELINE.md`, and this file in GitHub.
- Update documents as architecture changes, not retrospectively at the end.

Reason:
- A fresh conversation/developer must be able to recover the project directly from the repository.

## 2026-09-10 - Preset group is intent; same-group Blizzard row is presentation

Decision:
- Human raid subgroup assignment is durable preset intent.
- Blizzard changing only row/ordinal inside the same subgroup is transient presentation.
- Same-group row reorder must not make the preset Unsaved.
- Editor displays the player at Blizzard's live row and signals the mismatch.
- 0.7.14 signal: pulsing green background with tooltip `Not in preset location due to Blizzard raid handling`.
- Genuine subgroup change remains semantic.

Supersedes:
- Earlier behaviour where every Blizzard raid row permutation was written into the working preset and marked Unsaved.

Reason:
- Live Blizzard ordering and user-authored raid composition are different concepts; inferring whether Blizzard movement was automatic/manual is unreliable.

## 2026-09-10 - Combat role confirmation is optional validation

Decision:
- Requested/assumed role is sufficient for normal operation.
- Combat-derived confirmation is optional and defaults OFF.
- OFF means scanner events should be unregistered.
- ON means confirmed bots stop being scanned and the scanner sleeps when no unresolved tracked bots remain.

Supersedes:
- Earlier assumption that combat confirmation belonged in the normal always-on role path.

Reason:
- Reliable summon intent already provides role information; high-volume Vanilla combat text scanning is costly in raids.

## 2026-09-10 - Identity ordering is explicit, not timestamp-derived

Decision:
- Same-burst identity/order comes from explicit burst plans.
- Do not use equal/near `GetTime()` values to infer summon order.
- Name-bound identity is authoritative after successful binding.

Reason:
- SoloCraft processes same-burst summon commands reverse/LIFO and timestamps do not encode exact identity.

## 2026-09-10 - Global cross-burst pending identity is not accepted as final architecture

Decision:
- `pendingAssumedSpawns` global FIFO is a 0.7.14 implementation detail, not desired 0.8 architecture.
- Target direction is per-burst identity isolation and explicit completion/failure.
- Do not allow leftover intents to silently spill into later bursts.

Reason:
- Static audit confirms system-message and roster-delta paths can consume the same global pending set, and immediate wrong-role icons are consistent with bad assumed identity occurring before combat confirmation.

## 2026-09-10 - Do not silently preserve questionable fallbacks

Decision:
- Roster-delta identity binding, command/group legacy matching, old scheduler flags and compatibility shims must be justified individually before carrying them into 0.8.
- Do not delete them solely because they look old; prove their runtime role during the migration stage.

Reason:
- Some may protect real Vanilla/SoloCraft races; others may cause competing ownership.

## 2026-09-10 - Consolidation before feature growth

Decision:
- 0.8.x is primarily structural consolidation.
- Avoid meaningful new UX/features until core ownership/lifecycles are proven, unless specifically agreed.

Reason:
- More patch-layer growth would increase debugging and recovery risk.

## 2026-09-10 - Source audit is complete before first 0.8 functional change

Decision:
- The source-level 0.7.14 audit recorded in `ARCHITECTURE.md` is sufficient to move from audit into architecture agreement.
- No functional code was intentionally changed by the audit.
- Runtime testing remains mandatory as proof during each migration; static deductions about dead/superseded code are not sufficient grounds for deletion by themselves.

Reason:
- The current authoritative summon path, identity consumers, roster models, layout/presentation layering, detection lifecycle, event pump and major wrapper chains are now documented in-repo.

## 2026-09-10 - Proposed 0.8 ownership is not yet approved merely by being documented

Decision:
- Module boundaries in `CONSOLIDATION-0.8.md` are a proposal for review, not silently adopted design.
- Before functional work begins, resolve the listed Phase B semantic questions with the user.

Reason:
- Consolidation must not turn an implementation preference into an architectural decision without explicit agreement.

## Open decisions requiring user agreement before/while implementing relevant phase

These are deliberately **not decisions yet**:

1. Exact human row: only live presentation, or optionally a distinct user-authored `preferredSlot`?
2. Combat-confirmed role: pure diagnostic, or permitted to alter the role used by replacement?
3. Roster-delta identity fallback: remove, or retain strictly as reconciliation for the one active burst without competing consumption?
4. Final naming: `RaidSpawn.lua`, `RaidMaintenance.lua`, `RoleDetection.lua`, and whether `RaidSnapshot.lua` remains separately named.
5. Shared 3-second removal settle for preset-over-preset rebuild: desired by user, but still an intentional behaviour change from 0.7.14 and should be implemented/documented deliberately.

## Change-control rule for 0.8

When any open decision is resolved:
- add a dated entry here;
- state what 0.7.14 did;
- state the new canonical behaviour/state ownership;
- state whether it is behavioural or structural only;
- update baseline/architecture/consolidation docs in the same development sequence.