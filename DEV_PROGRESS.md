# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.8.91-dev`
- Current implementation commit: `81b94d372761a8a76a9c8716dcad4f9649e3c7b9`
- Current documentation checkpoint before this handoff: `64299fded994a81715c405c9c5f296b24e14df57`
- Last runtime-tested implementation: `252f6f3acb33f755b0c6d5c34dedc68e0538b15e` (`0.8.88-dev`; failed the layout/summon gate)
- Last runtime-cleared implementation: `ff9725d0336ded2f406661bf9863d88719322124` (`0.8.87-dev`)
- Stable `main`: `0.8.78` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested dev source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- `0.8.91-dev` is an untested implementation checkpoint, not the next acceptance candidate. It restored human raid-subgroup movement after an incorrect 0.8.90 interpretation, but the subsequent design review changed the intended implementation/test model again. Do not runtime-test or promote it as-is.
- Immediate goal: implement the agreed summon/rebuild identity model and combat-role validation semantics in the smallest coherent next version, then runtime-test that exact build. Do not start visualiser or unrelated maintenance/UI cleanup first.

## Architecture / ownership
- `SoloCraftBots.lua`: bootstrap/core/shared UI/primitives.
- `Presets.lua`: configured preset intent, editor, snapshots, validation.
- `Roster.lua`: observed party/raid reality, human/bot classification, Active Roster, spawn-assumption identity, combat-role evidence.
- `Spawn.lua`: sole owner of physical roster mutation through `SCB.botOperation`: summon/rebuild, add, subgroup moves, maintenance/refill, bootstrap/survivor handling.
- `Communication.lua`: PartyBot command transport, command semantics, incoming chat/system feedback, preset communications.
- `Options.lua`: settings/help/debug.
- Preserve one physical-operation coordinator. Do not add a second scheduler or let presentation code mutate roster state.

## Authoritative logical model
- A preset slot is **intent**, not a promise that Blizzard will display a human in that physical row.
- A human assigned to logical slot N **replaces/suppresses exactly that slot's bot class/role intent**. This is true in both 5-player parties and raids.
- Party physical order is client-relative: every player sees themself as `player` / first. Therefore party row can never be used as shared logical human identity and must not produce a row-mismatch warning.
- In raids, Blizzard subgroup membership can be changed with `SetRaidSubgroup()`, but exact row/order inside the subgroup is not controllable/reliable in Vanilla. SCB may place a human into the intended subgroup; it must not try to force the human's exact row.
- Human absolute row is therefore irrelevant to bot identity. Within a completed group, remove humans from consideration and reason about **bot-relative order** only.
- The pre-0.8.87 implementation at `6bcc9949222513d4f8e38a90d43071149f162f31` is the reference for the proven raid principle: move humans to intended subgroup, filter humans out, then bind remaining bots ordinally within that subgroup.
- 0.8.87 correctly introduced explicit exact human logical slots for editor/snapshot/suppression, but incorrectly removed the raid human-subgroup preparation step at the same time. That missing prerequisite caused the later raid-finalization hang.

## Full Summon / Rebuild contract
Full rebuilds deliberately operate **one logical group at a time**.

For each logical five-slot group:
1. Determine human-covered logical slots. Those bot intents are inactive and must never be spawned.
2. For raids, ensure the group's humans are in their intended Blizzard subgroup. Resolve raid indices by name immediately before each subgroup move because indices can change after `SetRaidSubgroup()`.
3. Build the burst from only the uncovered bot assignments for that logical group.
4. Send exactly that many bot commands using the established reverse-send/LIFO scheme.
5. Wait for that group/burst to settle before proceeding to the next logical group.
6. Observe the completed group, filter humans out, and map the remaining bot names in bot-relative Blizzard order to the uncovered logical bot assignments in ascending slot order.
7. Only then continue to the next logical group.

Example: if Group 5 contains two humans and three bot intents, Group 5 must summon exactly three bots, not five. Over-summoning and allowing unknown spill into the next subgroup risks corrupting ordinal role/name inference.

Do **not** optimise a full rebuild by packing bot intents from multiple logical groups merely to reduce burst count. With fewer than five humans this usually saves no burst at all; even with more humans the gain is roughly 1-2 seconds while substantially weakening deterministic inference. A suitable implementation comment is:
`-- Full rebuilds intentionally burst one logical group at a time; cross-group packing saves negligible time but weakens deterministic bot-order inference.`

Historical evidence supporting this model:
- The user previously tested full raids made from a repeated four-Druid-role pattern.
- Bear/cat/caster power bars provided an external role/spec clue (rage/energy/mana; resto vs moonkin still both mana).
- Repeated tests showed consistent preset order == final raid bot order.
- This is strong runtime evidence for the established reverse-send/LIFO + settled bot-relative-order mechanism, while not making chat join text itself an independent role oracle.

## Join-name assumptions vs final identity
- The system join line contains the bot **name only**, not class/role/slot.
- `SCB_BeginAssumedSpawnBurst()` queues logical intents in ascending assignment order; commands are sent in reverse order; `SCB_HandleAssumedRoleSystemMessage()` binds arriving names FIFO to those pending intents. This deliberately relies on SoloCraft's observed LIFO spawn behaviour.
- Roster-delta fallback can partially corroborate by class, but class cannot distinguish same-class different-role intents.
- Therefore join-derived name -> intent is an important **provisional/operational identity**, especially for mixed-group refill, but the full-rebuild final mapping should come from the completed group's bot-only order.
- Do not let later assumption reconciliation overwrite a settled, authoritative group-order mapping. Audit `SCB_PostFinalizeRaidRoleTracking()` / `SCB_ReconcileTrackerFromAssumedRoles()` during the next implementation slice.
- Class is only a partial checksum. Five same-class bots cannot be independently ordered by class; role-unique combat evidence is the useful later validator.

## Refill / maintenance contract
Refill is intentionally different from a full rebuild because mixed bursts save meaningful time.

Example: five missing/dead bots across five different raid groups can be one ~1-second five-bot burst instead of five separate group bursts.

Current maintenance already:
- sorts missing assignments;
- takes up to `SCB.MAINTENANCE_BURST_SIZE == 5` regardless of destination subgroup;
- records exact burst intents (`burstID`, `slotIndex`, `group`, class, role, extra);
- sends them in reverse order;
- resolves newly joined names through the explicit join-assumption mapping;
- moves/swaps those known new bots into their intended subgroups;
- then binds replacements to Active Roster slots.

That mixed-group optimisation is worth retaining. It necessarily relies more heavily on the established join-order identity assumption than full rebuild does. Combat-role validation should act as an independent watchdog for that assumption rather than forcing refill back to one-group-at-a-time behaviour.

## Combat-role validation
The combat sniffer is intentionally based on **role-unique spell evidence**. Do not describe confirmed mismatches as generic hybrid/off-role noise.

Desired semantics:
- Keep **intended/assumed role** separate from **combat-confirmed role**. Combat detection must not overwrite the logical slot/preset role it is validating.
- First indicator/tick: SCB has bound/inferred this bot name to this logical assignment.
- Second validation indicator: independent combat evidence has confirmed the intended role.
- Confirmed different role: show a clear cross/mismatch state and an active user warning; do not silently remap bots, rewrite the preset, or mutate intended role.
- Mismatch warning should identify bot name, logical group/slot, intended role, detected role and useful evidence. Avoid repeated popup spam for every spell; warn once per bot + current assignment disagreement and keep a persistent visible mismatch state until resolved/rebuilt/acknowledged as appropriate.
- Combat-role event registration is already lifecycle-based: it sleeps when no tracked bots need confirmation, filters by pending bot name, and UI refresh is debounced. Preserve this low-cost model.

Validation eligibility:
- `rogue`, `hunter`, and `warlock` have no alternate role/spec choice in SCB. They should never enter combat-role validation and should never receive the second validation tick or mismatch cross when combat validation is enabled.
- Prefer deriving role-validation eligibility from class capabilities rather than hardcoding unnecessary spell scans.
- Warrior, Paladin, Shaman, Druid and Priest have multiple distinct roles and are meaningful role-validation targets.
- Mage is a separate case to decide explicitly: SCB offers Fire/Frost choices but both are `rangedps`; the current combat-role detector only confirms `rangedps` and cannot validate Fire vs Frost. Do not pretend a second **role** tick validates mage spec unless spec-aware evidence is deliberately added.

## Layout-warning correction
The 0.8.88/0.8.89 yellow layout-warning work was based partly on an incorrect absolute-row model and must be re-audited before reuse:
- Party: never warn because a human is not in their logical absolute row; each client sees self first.
- Raid: do not warn merely because a human's within-subgroup row differs from their logical slot; row is uncontrollable and irrelevant to execution identity.
- A human being in the wrong raid **subgroup** is meaningful during rebuild and should be corrected by the Spawn-owned subgroup-preparation step before that group's bot burst.
- Any future passive layout warning should represent a genuinely actionable invariant (for example wrong subgroup after external/manual rearrangement), not uncontrollable human row order.

## Current implementation state
- `0.8.91-dev` / `81b94d372761a8a76a9c8716dcad4f9649e3c7b9` restored human subgroup placement in `Spawn.lua` and reverted the incorrect 0.8.90 finalizer workaround.
- That change is directionally aligned with the corrected model, but it was written before the full group-by-group / bot-only-order / combat-validation review above. Treat it as an implementation checkpoint only.
- Do not simply resume the old planned 0.8.91 runtime gate. First audit current summon sequencing against pre-0.8.87 `6bcc994...`, especially where final bot mapping can be overwritten by join assumptions and where the yellow mismatch classifier still compares absolute rows.
- 0.8.89 and 0.8.90 were superseded before runtime test.
- Canonical Lua 5.0.2 compiler remains unavailable in the current execution shell because the checker lives in `VanillaTemplate` and cannot be materialized here; no compiler pass is claimed for 0.8.91.

## Runtime history relevant to this work
- `0.8.87-dev` / `ff9725d0336ded2f406661bf9863d88719322124`: user verified exact logical human-slot editing/suppression in 5-man, correct underlying bot replacement, raid summon regression at that point, and player logical location persistence across presets.
- `0.8.88-dev` / `252f6f3acb33f755b0c6d5c34dedc68e0538b15e`: failed. No expected yellow warning appeared; more importantly a 10-man resummon hung and later normal Summon attempts reported `Preset Summon is already in progress`.
- The screenshot/chat showed Revenga logically in Group 2 but physically in Blizzard Group 1. The strict finalizer then expected bot counts consistent with the logical groups while the missing human subgroup-preparation step made those counts impossible, stranding `PRESET_TRACK_ROSTER`.
- Ctrl-click resummon recovered from the stuck operation but did not resolve the underlying subgroup-model regression.
- Historical pre-0.8.87 raid handling and the user's repeated Druid-pattern tests are the behavioural reference for rebuilding the safe path.

## Other preserved invariants
- Active Roster keeps logical identity/expected state separate from observation. Human-covered bot slots remain dormant intents; if the human leaves before replacement they become missing; if the human returns before replacement they become covered again.
- After a missing human slot has been replaced by a bot, do not auto-kick/free capacity when the human returns.
- Capacity reuse remains: removal observed absent -> 3.0s settle -> dependent add.
- Bootstrap is continuity-only; reuse an existing bot when possible.
- Maintenance remains `botOperation(kind="maintenance")`; player combat is an absolute block and existing stale-remote-combat allowance remains.
- Manual Add remains coordinated through `botOperation(kind="manual-add")`.
- Raw user-typed `.partybot add ...` remains outside SCB coordinator ownership.
- Taxi safety remains action-time only through `SCB_CanOperateBots(showError)`.
- Never use `UnitHealth()==0` as a dead-state fallback.
- Preset protocol remains `SCBPRESET` protocol 2; snapshots carry logical composition/human slot intent, never generated bot names.
- Command semantics and the tested Ctrl-Come/Move/Stay behaviour are unchanged by this work.

## Planned next slice
1. Re-read this file and `dev_rulebook.md`; verify remote `dev` HEAD.
2. Audit current `0.8.91` summon/rebuild line-for-line against pre-0.8.87 `6bcc994...` for:
   - human subgroup preparation;
   - exact per-group uncovered-bot burst sizing;
   - group settle boundaries;
   - bot-only ordinal final mapping;
   - any later assumption reconciliation that can overwrite final mapping.
3. Audit/remove the invalid absolute human-row mismatch logic for party and raid.
4. Adjust combat-role validation without broad refactor:
   - never overwrite intended role with confirmed evidence;
   - skip validation lifecycle/second indicator for Rogue/Hunter/Warlock;
   - decide Mage spec-vs-role presentation explicitly;
   - add one active mismatch warning for confirmed intended-role disagreement.
5. Make this one coherent runtime slice with the next numeric TOC bump (expected `0.8.92-dev`), run every available static/compiler check, review the final diff, update this handoff, then give the user a focused runtime test.

Do not redesign refill into group-by-group bursts: its mixed five-assignment burst is intentional and provides a real speed benefit. Do not start visualiser work or unrelated cleanup before this identity/validation gate is resolved.

## Deferred / later
- Resummon Group through the existing maintenance/bot-operation lifecycle.
- Audit remaining All-row/server target sensitivity.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## Release note
Do not promote the current dev line. Stable remains `0.8.78` on `main`. Release preparation must compare `main` and `dev` rather than overwrite main because histories have diverged.
