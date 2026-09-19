# SoloCraftBots 0.8 Migration Log

This file is append-only project memory for the consolidation. Existing audit/decision notes are not deleted as work completes; completed items are recorded here and may be struck through in planning documents later.

## 0.8.0-dev — location consolidation started

- Removed the separate `LocationZones.lua` correction layer.
- AQ40 runtime zone correction (`Ahn'Qiraj`) now lives with the current location implementation.
- `Location.lua` still exists temporarily; the approved target remains to absorb the complete location subsystem into `Presets.lua`.

## 0.8.1-dev — chat filter absorbed into Options

- Moved the complete presentation-only SoloCraft chat filtering implementation into `Options.lua`.
- Removed `ChatFilter.lua` from the TOC and repository.
- Behaviour intentionally unchanged: underlying `CHAT_MSG_SYSTEM` events still reach SCB; only chat-frame rendering is filtered.
- This is a structural consolidation step only.

## 0.8.2-dev — Shield Slam detection patch absorbed

- Moved `Shield Slam` into the Warrior tank evidence catalogue in `Detection.lua`.
- Removed the standalone `DetectionShieldSlam.lua` wrapper and its duplicate combat-source parsing/name-normalization code.
- Behaviour intentionally unchanged: Shield Slam remains Warrior tank evidence and uses the same two-observation confirmation threshold as the rest of the catalogue.
- `DetectionLifecycle.lua` remained temporarily separate at this point because it loaded after `Options.lua` and owned the optional scanner/event sleeping wrappers.

## 0.8.3-dev — role-detection lifecycle flattened

- Removed `DetectionLifecycle.lua` from the TOC and repository.
- Moved the optional combat-confirmation event lifecycle into `Detection.lua`, reusing Detection's existing combat-source/name parsing rather than maintaining a duplicate parser.
- Combat confirmation remains OFF by default.
- When enabled, only currently-unconfirmed tracked bot names are eligible for the expensive detector; confirmed bots stop being scanned and the combat listeners unregister when no relevant unconfirmed bots remain.
- Moved the role-confirmation option/UI bridge into `Options.lua`. Options now explicitly calls the Detection lifecycle when the checkbox changes instead of relying on a later file to wrap Options after load.
- The existing Options-local wrapper style is still transitional; final wrapper elimination belongs to the broader Raid/Options ownership cleanup rather than being mixed into this behaviour-preserving move.
- User smoke test passed: role ticks appeared to advance in step with observed spell use and the addon felt substantially more responsive. The exact all-confirmed listener sleep state was not directly instrumented, and 40-player performance remains untested at this checkpoint.

## 0.8.4-dev — preset rebuild removal settle

- Preset-over-preset rebuild now waits until the old bots are absent from Blizzard's roster and then waits the shared 3.0-second removal-settle interval before new summoning begins.
- This replaces the previous 1.0-second post-roster barrier in `PresetRebuild.lua`.
- This implements the approved rule that any remove-then-add operation must allow SoloCraft instance accounting to settle before issuing replacement summons.
- `PresetRebuild.lua` remains separate for now; absorption into `Spawn.lua` is still pending.

## 0.8.5-dev — exact logical human slots

- Raid humans now occupy explicit logical preset slots rather than being packed into the first free rows of their assigned subgroup.
- Present humans with no exact logical assignment remain in Other Players until assigned to a specific slot.
- Saved present humans snap to their saved logical slot on preset load; saved absent humans remain stored but do not suppress the underlying bot.
- Execution snapshots now carry each raid human's exact logical `slotIndex`; bot suppression uses that exact slot rather than group occupancy count.
- Exact player slot remains the source of the derived desired subgroup used by the existing raid arrangement code.
- Drag/drop now resolves the specific preset row under the cursor. Dropping onto a group background alone no longer assigns the player.
- Blizzard raid rows/subgroup positions remain observed as `current*` runtime fields and no longer permute tracker logical assignments or the working preset.
- Removed `RaidPresentation.lua` and its 0.7.14 green-pulse/live-row editor model; that design was explicitly superseded by the approved logical-slot model.
- Existing bot finalization still uses bot-only subgroup order, preserving the useful property that humans are ignored when resolving bot order inside a subgroup.
- Historical presets with stored `playerSlots` retain those values as logical assignments. Group-only legacy assignments without an exact slot now require explicit slot placement before a raid preset can summon.
- BWL runtime test passed with three humans total. Two humans deliberately occupied Mage logical slots and self occupied a Priest logical slot; Blizzard placed humans independently in the live raid rows while SCB still suppressed the intended logical bot slots.
- An apparent Priest-replacement failure was traced to cross-version preset communication involving an older client, not the local 0.8.5 summon path. The alternate request flow produced the correct result. Cross-version preset comms therefore remain a compatibility item to audit before 0.8 main promotion.

## 0.8.6-dev — snapshot layer absorbed into RaidPlayers

- Removed `RaidSnapshot.lua` from the TOC and repository.
- Moved its authoritative execution-snapshot builder, validation extension, exact-slot occupancy compatibility handling, and tracker preset-reference wrapper into `RaidPlayers.lua`.
- Removed the now-redundant earlier `SCB_BuildPresetExecutionSnapshot` wrapper from `RaidPlayers.lua`; there is now one final snapshot builder in this transitional owner.
- No intended runtime behaviour change from the tested 0.8.5 exact-slot model. This is a structural flattening step before final Presets/Raid ownership is chosen.
- User smoke test passed: addon/preset summon still behaved normally after the snapshot merge.

## 0.8.7-dev — establish final Raid owner

- Renamed the transitional `RoleTracking.lua` owner to `Raid.lua` without changing its load position or implementation.
- This deliberately preserves runtime behaviour while establishing the final coarse Raid owner before larger roster/identity/layout/maintenance merges.
- `RoleTracking.lua` is removed from the TOC/repository; its former code now loads from `Raid.lua`.
- No wrapper-chain cleanup was attempted in this step. Subsequent Raid consolidation can absorb neighbouring responsibilities into this stable owner in smaller, testable changes.

## 0.8.8-dev — roster absorbed into Raid

- Removed `Roster.lua` from the TOC and repository.
- Folded observed Live Roster, persistent Active Roster, session bot tracking, auto-loot/auto-promote and the base roster-change handler into `Raid.lua`.
- Preserved the old runtime ordering inside the combined file: base roster implementation first, then the former RoleTracking role/identity wrappers.
- User runtime test passed for a normal 5-player group and Replace Missing.

## 0.8.9-dev — late identity/layout layer combined

- Removed standalone `RaidLayout.lua`.
- Folded its live Blizzard raid-position observation and late roster/finalization wrappers into `RaidIdentity.lua`.
- Moved `RaidIdentity.lua` to the former late `RaidLayout.lua` TOC position, after `Spawn.lua`, preserving the reason those wrappers existed late in load order while removing one separate patch file.
- Exact identity remains based on explicit burst plans and join-message order. Blizzard layout remains observational only and continues to update `current*` live fields without changing logical preset slots.
- Scheduler-state cleanup wrappers remain temporary and are explicitly deferred to Spawn consolidation; this build does not pretend the wrapper chain is fully solved.
- This is a structural step toward the final `Raid.lua` owner, not the final identity architecture. The global pending FIFO and roster-delta competition still need the planned hardening pass.
- Regression found in 5-player testing: moving `RaidIdentity.lua` after `Spawn.lua` also moved an obsolete duplicate `SCB_SendSpawnCommand` definition after Spawn's authoritative validated sender. That duplicate returned nil, causing Spawn to interpret every attempted command as an invalid scheduler item.

## 0.8.10-dev — restore authoritative Spawn sender

- Removed the obsolete `SCB_SendSpawnCommand` definition from late-loaded `RaidIdentity.lua`.
- `Spawn.lua` is again the sole owner of the validated outbound spawn sender and its boolean success contract.
- The reported failure was therefore not caused by changing Holy Paladin to Retribution or by unsaved preset semantics; the role edit merely exposed the 0.8.9 load-order regression on the next summon attempt.
- User repeated the same unsaved Holy-to-Retribution preset test and confirmed summoning worked again.

## 0.8.11-dev — preset rebuild absorbed into Spawn

- Removed `PresetRebuild.lua` from the TOC and repository.
- Moved the preset-over-preset rebuild transition barrier into `Spawn.lua`, next to the authoritative summon scheduler that consumes it.
- Preserved the existing rebuild behaviour: wait for old bots to disappear down to the allowed survivor state, perform party-to-raid conversion when required, then wait the shared 3.0-second post-roster settle before beginning the new summon.
- No intentional summon behaviour change in this step; this is ownership consolidation so teardown, conversion, settle and summon handoff now live in the same final Spawn owner.
- Runtime verification pending: preset-over-preset in a 5-player group should remove the old bots, pause for approximately 3 seconds after roster disappearance, then summon the replacement preset normally.

## 0.8.12-dev — preset rebuild absorption rolled back after runtime hang

- Runtime testing of 0.8.11 exposed a client hang during preset-over-preset rebuilding.
- Restored `PresetRebuild.lua` as a separate live transition barrier and restored its TOC position before the location/raid/spawn layers.
- The 0.8.11 absorption remains preserved above as historical migration record, but it is no longer the current Git architecture.
- Also restored the missing scheduler queue consumption that had been lost during the 0.8.11 move.
- User runtime test confirmed the client hang was fixed.
- Further consolidation of `PresetRebuild.lua` is blocked until the separate barrier's full handoff behaviour is proven again.

## 0.8.13-dev — preserve queue identity across rebuild handoff

- Found that `Spawn.lua` captures `SCB.presetSpawnQueue` in a frame-local variable before calling the rebuild updater.
- Starting the replacement snapshot from `PresetRebuild.lua` creates a new queue table. The first 0.8.13 fix copied that new queue back into the scheduler's already-captured table so the same OnUpdate could continue.
- Runtime test improved the failure: the summoner no longer became endlessly paused.
- However preset-over-preset in a 5-man still kicked the old bots and reported loading the new preset without the replacement bots appearing.
- A second normal Summon click then worked; Ctrl override was not required. This shows the first automatic operation was no longer stuck busy, but the same-frame rebuild handoff still was not a valid replacement-summon boundary.
- Therefore the queue-table transplant is superseded by the 0.8.14 next-frame handoff below rather than treated as a final fix.

## 0.8.14-dev — defer rebuild scheduler release one frame

- Replaced the 0.8.13 queue-table transplant with an explicit two-frame handoff in `PresetRebuild.lua`.
- After the old bots are observed gone and the shared 3.0-second settle completes, the rebuild updater constructs the replacement snapshot/queue but suppresses `scbExplicitPresetOperation` for the remainder of that already-running scheduler frame.
- On the following OnUpdate, the rebuild updater releases the explicit operation and clears its transition state. `Spawn.lua` therefore captures and consumes the replacement queue normally from the start of that frame rather than inheriting a queue created halfway through the previous frame.
- This keeps the approved 3.0-second removal-settle rule intact while adding only a frame-boundary handoff; no consolidation was attempted.
- Runtime verification passed: clean 5-man summon, 5-man preset-over-preset, 5-man -> 10-man overwrite with survivor/conversion, and repeated A -> B -> C overwrite all completed automatically without a second Summon click or Ctrl override.
- During that verification the survivor was observed waiting before being parked in Group 8. Review showed the rebuild settle was delaying non-add work, while the later parked-survivor removal path did not itself wait 3 seconds before another burst. That sequencing is corrected in 0.8.15 below.

## 0.8.15-dev — place removal settle at the next-add boundary

- Refined the shared removal-settle rule: the 3.0-second safety delay gates the next bot add, not harmless conversion, subgroup movement or final roster observation.
- In preset rebuilds the settle clock now starts as soon as the removed bots are actually absent. Party-to-raid conversion and parking the retained survivor in Group 8 can happen during that clock, so the survivor no longer waits unnecessarily before being moved.
- The Group-8 parking helper now accepts an explicit safety-bot name, allowing the rebuild barrier to park the survivor before the replacement snapshot is released.
- When a parked survivor/bootstrap is later removed after a real Group 1 bot joins, SCB now observes that safety bot leave and waits the shared 3.0 seconds before a following summon burst.
- If no add follows and the only remaining work is final roster tracking, no artificial 3-second delay is added.
- The existing bootstrap-from-empty path still cannot park until raid conversion is visible, but once Blizzard exposes the raid roster it requests Group 8 immediately; it is not intentionally held behind the removal settle.
- Runtime verification passed: in the 5-man -> 10-man overwrite, raid conversion and Group-8 parking occurred promptly during the original teardown settle, G1 began when that settle expired, and after the parked survivor was removed the following burst respected the removal -> next-add delay. No second click or Ctrl override was required.

## 0.8.16-dev — move Spawn cleanup out of late RaidIdentity

- Removed `RaidIdentity.lua`'s late wrappers around `SCB_AbortBotSpawnOperations` and `SCB_ResetSessionState`; those wrappers existed only to clear Spawn-owned scheduler state after Spawn had loaded.
- `Spawn.lua` now owns that cleanup directly. Abort preserves the previous effective ordering by clearing Spawn runtime state before the inherited abort chain and again afterward, then clearing pending assumed-spawn identity state as before.
- Session reset now clears Spawn runtime state in Spawn before delegating to the existing Raid/session reset chain.
- No identity matching, Blizzard live-layout observation, preset execution, rebuild timing or maintenance behaviour was intentionally changed.
- `RaidIdentity.lua` remains live because its identity and layout wrappers are still being kept at their proven late load position until surrounding runtime gates are clear.
- Runtime test: normal 5-man summon passed, and 5-man -> 5-man overwrite passed. `/reload` was not a valid addon-update test because WoW reloads the UI but does not reload changed addon files from disk.
- Ctrl-abort test failed when four add commands had already left the client but the bots had not joined yet. The second preset reported that summoning had begun, but the original four bots later appeared on their original schedule and the replacement did not take over. This exposed an in-flight server-command race rather than a failure of the moved cleanup itself: client-side abort can clear SCB's local queue but cannot recall PartyBot add requests already accepted by the server.
- Recommendation changed: do not proceed to RaidIdentity removal yet. Fix and prove the in-flight abort/rebuild boundary first.

## 0.8.17-dev — recover aborted in-flight preset summons

- `PresetRebuild.lua` now recognises outstanding `pendingBotAdds` when a new preset starts after the previous local operation has been aborted.
- If add commands from the old operation are still in flight, the replacement snapshot is held in the rebuild barrier instead of being released against an apparently empty roster.
- Existing roster handling remains responsible for consuming `pendingBotAdds` as bot names actually join. The rebuild barrier also honours the existing add-intent expiry so a lost/rejected request cannot park recovery forever if no later roster event fires.
- Once the old in-flight requests resolve, any bots that actually appeared are treated as the old group: SCB runs the normal Kick All/survivor policy, observes the resulting roster disappearance (or survivor-only state), then applies the existing shared 3.0-second remove -> next-add settle before releasing the replacement preset.
- If the aborted requests expire and no old bot ever materialises, no artificial removal settle is added because no removal occurred.
- This deliberately uses the already-existing physical add-intent counter instead of trying to cancel server-side commands that the client cannot recall.
- Runtime verification pending. Primary gate: start a 5-man summon, Ctrl-click a different preset after the four bot add commands have been sent but before they join, then verify the original bots are allowed to appear, are removed automatically, and the second preset starts only after the normal removal-settle boundary. No third click should be required.

## Presets sizing decision

- Do not force `Location.lua` or `Comms.lua` into `Presets.lua` merely to reduce file count.
- Continue moving non-preset runtime responsibilities out of `Presets.lua`, then reassess the resulting size and cohesion.
- Merge Location and/or Comms into Presets only if the final ownership remains clear and the file stays reasonably sized.

## Next consolidation direction

- The exact logical human-slot model has now passed a three-human BWL runtime test; preserve that behaviour while removing remaining transitional wrappers.
- Further RaidIdentity consolidation is paused until the 0.8.17 forced-retry recovery gate passes. The remaining explicit identity/live-layout responsibilities can then move into `Raid.lua` and `RaidIdentity.lua` can be removed in a separate small step.
- Continue absorbing maintenance responsibilities into the established `Raid.lua` owner after the identity/layout layer is flattened.
- Audit cross-version Comms handling for exact human slots before main promotion; do not silently degrade exact-slot intent.
- ~~Absorb `PresetRebuild.lua` into `Spawn.lua` during the summon state-machine consolidation rather than merely concatenating files.~~ Completed in 0.8.11-dev, then explicitly rolled back in 0.8.12-dev after the runtime hang. The ordinary separate rebuild handoff and corrected settle placement are proven through 0.8.15, but 0.8.17 now adds a further forced-retry recovery responsibility that must also be proven before any re-absorption is reconsidered.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.

## 0.8.18-dev — introduce one top-level bot operation

- Added transitional `SpawnOperation.lua` immediately after `Spawn.lua`.
- Introduced one explicit active operation object with begin / replace-intent / phase / complete / abort lifecycle helpers.
- Preset summon/rebuild requests now enter through that operation identity while the proven physical 0.8.17 sequencing remains underneath.
- Ctrl-forced preset replacement keeps the same operation identity and replaces its desired preset intent rather than creating a second top-level operation.
- Runtime verification passed: normal 5-man, 5-man -> 5-man, 5-man -> 10-man survivor/conversion, and an in-flight switch between two different 10-man presets all completed correctly. No Lua error or stuck state was reported.

## 0.8.19-dev — move preset rebuild state into the coordinator

- `botOperation.rebuild` became the authoritative owner of pending already-sent add recovery, old-bot teardown observation, party-to-raid conversion/parking during teardown, the shared 3.0-second remove -> next-add settle, and the proven next-frame replacement-queue handoff.
- `SCB.presetRebuildState` was reduced to an active-only compatibility sentinel so older busy checks cannot start another physical mutation in parallel; snapshot/timer/conversion/handoff state no longer lives there.
- Existing Spawn queue, burst identity and survivor/bootstrap execution remained unchanged.
- Runtime verification passed strongly. The user repeatedly interrupted 10-bot dungeon summon/rebuild operations with deliberately unreasonable Ctrl-click preset switches; the latest requested preset still won automatically and no Lua errors, permanent busy state, wrong final preset or extra click were reported.
- This result closes the rebuild-ownership gate. Further Ctrl/rebuild edge cases should be handled by the coordinator architecture rather than local patches to `PresetRebuild.lua`.

## 0.8.20-dev — move survivor/bootstrap handoff state into the coordinator

- `botOperation.safety` now persistently owns the safety-member name, bootstrap name, raid park/remove flags, survivor-removal wait/settle state, and five-player survivor handoff count/timestamp.
- The proven Spawn/RaidBurst physical sequencing is unchanged for this gate.
- A narrow compatibility bridge hydrates the historical global field names only while a scheduler frame executes, captures mutations back into `botOperation.safety`, then clears those globals. They are no longer persistent state owners between frames.
- Ctrl replacement, abort and operation completion clear the coordinator safety state so no later operation can inherit a stale survivor/bootstrap.
- An off-branch candidate was caught before publication because its outer frame capture could erase safety created by the nested rebuild -> replacement-queue handoff. The published candidate distinguishes pre-existing frame safety from newly-created same-frame safety and preserves the latter.
- Runtime verification pending. Primary checks are 5-man, 5 -> 5, 5 -> 10 survivor/Group-8 handoff and aggressive in-flight Ctrl switching. The special empty-group raid bootstrap path remains an explicit check before the compatibility bridge is removed.

## 0.8.21-dev — absorb coordinator into Spawn and prove 40-man bootstrap

- Removed temporary `SpawnOperation.lua` and appended its coordinator implementation to `Spawn.lua` at the same effective load position.
- Kept the 0.8.20 hydration/capture bridge unchanged in this gate so file absorption and state-model cleanup were not mixed into one runtime risk.
- Runtime verification passed the previously-tested survivor/rebuild paths and closed the outstanding 40-man bootstrap coverage gap.
- Fresh summon while completely solo inside Molten Core correctly created the temporary bootstrap bot, converted/formatted the raid and completed the 40-man preset.
- During that fresh bootstrap SoloCraft returned `Cannot add bots while any party member is in combat` five times. SCB recovered the rejected group automatically and completed the operation without losing burst identity, requiring a second click or remaining stuck.
- A subsequent destructive 40-man preset summon in the same saved raid-ID context correctly kicked the existing bots and rebuilt fresh without using the bootstrap path.

## 0.8.22-dev — use coordinator safety state directly

- Removed the 0.8.20 per-frame survivor/bootstrap hydrate/capture bridge.
- `Spawn.lua` now creates and consumes the active preset operation's `botOperation.safety` table directly.
- Group-8 park/remove helpers in `RaidBurst.lua` use the same coordinator safety table directly; the superseded preset scheduler wrapper in `RaidRefill.lua` was updated as well so it no longer refers to the historical safety globals.
- Operation completion, abort and forced replacement clear coordinator safety state directly.
- Survivor queue markers that require handoff state now fail closed if the active operation has no safety table instead of silently interpreting missing state as nil/zero.
- Pending-add recovery, burst identity, combat retry, party-to-raid conversion, Group-8 sequencing and the shared 3.0-second remove -> next-add boundary are intentionally unchanged.
- Runtime verification pending. Primary regression checks are 5 -> 5 survivor handoff, 5 -> 10 conversion/Group-8 handoff, one aggressive in-flight Ctrl replacement, and a later fresh 40-man bootstrap direct-state check before main promotion.

## 0.8.23-dev — overlap raid-bootstrap settle with unrelated bursts

- Added transitional `SpawnBootstrap.lua` immediately after `Spawn.lua` as a one-gate refinement; it is not intended to become a permanent owner.
- Refined the removal-settle interpretation for the temporary raid bootstrap: disappearance + 3.0-second accounting protects reuse of the bootstrap's capacity, not unrelated earlier raid additions.
- Bootstrap remains parked in the proven G8 location. Once a genuine G1 bot exists and combat permits, bootstrap removal is requested.
- Bootstrap disappearance and its settle clock are polled during ordinary scheduler/group waits. Earlier preset bursts continue at the normal one-second cadence while they still fit without consuming the bootstrap's slot.
- The final capacity-filling preset bot burst, or final roster tracking when no later bot burst exists, remains blocked until bootstrap disappearance + 3.0 seconds is complete.
- Runtime verification passed in Molten Core: fresh solo 40-man bootstrap completed with no visible three-second pause between G1 and G2, normal later-group cadence continued, and the final requested 40-man roster was exact with no bootstrap left behind.
- The immediately preceding 0.8.22 stress also proved direct safety state under a completed-40 -> different-40 rebuild, a forced 40-man replacement while 34 old bots were already live, and a subsequent fresh bootstrap re-run.

## Bootstrap-continuity direction agreed after 0.8.23

- Long-term target terminology is `bootstrap`: a temporary bot occupant used to establish or preserve required party/raid/instance continuity. Fresh T3 bootstrap, retained raid survivor/anchor, saved-instance safety member and 5-man survivor are origin/policy variants of one lifecycle rather than separate permanent mechanisms.
- A bot bootstrap exists only when continuity requires one. If present humans already preserve required topology, do not retain an extra bot solely for topology.
- When a bot bootstrap is required, prefer reusing an existing bot over manufacturing a new one.
- Target preset topology is authoritative. Bootstrap state by itself must never imply raid conversion.
- For a 5-man target, remain party. Reserve one required final bot assignment while bootstrap occupies one slot; fill every other required bot assignment that fits beside the actual present humans; remove bootstrap; observe absent + wait 3.0 seconds; then fill the reserved assignment. Never hard-code the one-human case as “three then fourth”.
- For a raid-sized target with an existing raid, retain one existing bot bootstrap in G8 when needed, remove the other old bots, observe teardown + wait 3.0 seconds before new G1, then remove bootstrap after genuine G1 exists and overlap its settle using the proven 0.8.23 capacity rule.
- For a fresh raid start with no suitable existing member, manufacture a bootstrap only to establish the raid, then converge on the same raid-bootstrap lifecycle.
- This unified bootstrap lifecycle should be implemented and runtime-gated before further `PresetRebuild.lua` retirement or maintenance-scheduler migration.

## 0.8.24-dev — unify retained bootstrap continuity

- Unified existing-bot continuity with the bootstrap lifecycle rather than treating retained survivors/anchors as a separate mechanism.
- Raid rebuilds retain an existing bot when continuity requires it, park it in G8, tear down the remaining old bots, observe disappearance and wait the normal 3.0-second teardown settle before new G1.
- Once a genuine new G1 exists, the retained bootstrap is removed and its own capacity-reuse settle can overlap unrelated later raid bursts.
- Genuine 5-man rebuilds stay party, reserve exactly one final bot assignment, fill the others around the retained bootstrap, remove it, observe absence + wait 3.0 seconds, then summon the reserved final bot.
- Runtime verification passed strongly: completed 40-man -> different 40-man, Ctrl-forced replacement during retained 40-man rebuild, and completed 5-man -> different 5-man all converged correctly with no stale bootstrap or second click.
- Functional commit: `aa96f9136cee600cee0a09e50fe95fe6f606154f`.

## 0.8.25-dev — absorb bootstrap continuity into permanent owners

- Removed transitional `SpawnBootstrap.lua`.
- Moved the retained-bootstrap decision into the existing command-side Kick All safety policy.
- Moved the proven retained-bootstrap classification and bootstrap removal-overlap lifecycle into `Spawn.lua`.
- Preserved the existing physical behaviour rather than redesigning it during file absorption.
- Raid rebuild and forced replacement runtime checks passed. The equivalent 5-man path was subsequently re-proven on the later 0.8.27 architecture.
- Functional commit: `b38acce40c3f6447acb878324dcd7859e74671d3`.

## 0.8.26-dev — route maintenance through the bot coordinator

- Moved user-facing Replace Missing / Replace Dead physical lifecycle onto `botOperation(kind="maintenance")`.
- `Raid.lua`/Active Roster remains responsible for deciding which logical slots need replacement and for class/role/group metadata; the coordinator owns remove -> observe -> settle -> add -> subgroup move -> identity bind -> complete/fail.
- Missing and Dead are collected together at click via the existing Active Roster maintenance scan.
- Dead removals observe actual Blizzard-roster departure before the exact 3.0-second capacity-reuse settle begins.
- Replacement bursts are group-scoped, use explicit assumed-spawn identity plans, and wait one second after final subgroup placement before binding authoritative order.
- Added bounded failure paths: 15-second removal timeout, 12-second replacement-arrival timeout, 15-second subgroup-move timeout.
- Local-player combat remains an absolute block. Extended remote-only combat state may permit a server-authoritative attempt after 10 seconds when the player is personally clear, avoiding an indefinite Vanilla stale-combat hang.
- Maintenance abort is isolated from the legacy global abort path so retry failure cannot destroy persistent preset tracker state.
- Later runtime verification in a 10-man dungeon raid passed with multiple dead bots replaced successfully across two raid groups.
- Functional commit: `2bf114e66f407ec9193287009e7db367693ac503`.

## 0.8.27-dev — retire superseded preset rebuild layer

- Removed `PresetRebuild.lua` from the TOC and repository after static inspection showed its pending-add recovery, teardown, conversion, G8 parking, 3.0-second settle and next-frame handoff responsibilities were all authoritatively owned by the later `Spawn.lua` coordinator implementation.
- No replacement runtime logic was added in this gate; it was a true retirement of superseded code.
- Runtime verification passed: completed 5-man -> different 5-man; fresh 10-man dungeon summon after zoning; completed 10-man -> different 10-man; and multiple dead replacements across two raid groups on the 0.8.26 maintenance coordinator.
- This is the latest fully runtime-proven point before the next structural move.
- Functional commit: `cbf370074edea2f4615e1cd97f93e5a019675fdc`.

## 0.8.28-dev — collapse refill bridge into the burst transition layer

- Removed `RaidRefill.lua` from the TOC and repository.
- Audited its contents and found the early refill/preset-scheduler wrappers were obsolete historical layers because later `Spawn.lua` definitions already owned the final scheduler behaviour.
- Preserved the live 0.8.26 maintenance coordinator and moved it into `RaidBurst.lua` at the same effective pre-Spawn load position rather than changing ownership and wrapper order simultaneously.
- Stripped a large amount of obsolete `RaidBurst.lua` wrapper archaeology, retaining only the survivor/bootstrap helpers still consumed by Spawn plus the proven maintenance coordinator.
- Net result was a substantial code reduction while preserving the known final runtime entry points.
- 0.8.28 is structural and has not yet received its own runtime pass; runtime behaviour directly beneath it is proven through 0.8.27.
- Functional commit: `d5934b484cff5f74c49ae57fd829d56a33af3eb4`.

## Final six-file architecture agreed after 0.8.28

This decision supersedes earlier cautious sizing notes where they conflict. The goal is not minimum file count for its own sake; the goal is six clear subsystem owners with transitional layers removed.

Final non-locale Lua target:

```text
SoloCraftBots.lua
Presets.lua
Roster.lua
Spawn.lua
Communication.lua
Options.lua
```

Approved collapses:
- `Raid.lua` + `RaidPlayers.lua` + `RaidIdentity.lua` + `Detection.lua` -> `Roster.lua`. `Roster` is preferred over `Raid` because the owner represents live party and raid state. Detection is roster evidence/classification, not a standalone subsystem.
- `RaidBurst.lua` -> `Spawn.lua`. Spawn is the final physical bot-lifecycle owner, including bootstrap/survivor mechanics and maintenance execution.
- `Comms.lua` + `Commands.lua` + `ChatFeedback.lua` -> `Communication.lua`. The final owner is deliberately bidirectional: outbound commands/comms and incoming feedback/parsing.
- `Debug.lua` -> `Options.lua` as a clearly separated Developer/Debug section at the end.
- Tutorial/onboarding/help code currently living in `Presets.lua` -> `Options.lua`; the user intends to expand this system later.
- `Location.lua` -> `Presets.lua`. Location is now treated as preset-selection/capacity policy: zone -> preset group, valid sizes and optional auto-swap.
- Remove legacy `refillState` / `replaceDeadState` physical scheduler compatibility machinery from `Presets.lua` once call-site audit proves it is no longer required.

Ownership boundary to preserve:
- `Presets.lua` owns desired/configured group structure and location/preset policy.
- `Roster.lua` owns the real current party/raid roster, observed identities, subgroup positions, human/bot/dead/missing state and logical association.
- `Spawn.lua` owns physical mutation and timing.
- `Communication.lua` owns interaction with bots/server/addon peers and interpretation of feedback.
- `Options.lua` owns settings, tutorial/help and developer tools.
- `SoloCraftBots.lua` remains core/bootstrap/common plumbing.

Recommended migration order after 0.8.28:
1. absorb `RaidBurst.lua` into `Spawn.lua`, then smoke-test preset rebuild and multi-group maintenance;
2. fold `RaidPlayers.lua`, `RaidIdentity.lua` and `Detection.lua` into the current Raid owner, remove dead wrappers, then rename the stable merged owner to `Roster.lua`;
3. merge `Comms.lua`, `Commands.lua` and `ChatFeedback.lua` into `Communication.lua`;
4. fold `Debug.lua` and tutorials/onboarding into `Options.lua`;
5. fold `Location.lua` into `Presets.lua` and remove obsolete preset-local maintenance compatibility code after dependency audit;
6. run one consolidated regression pass before considering `main` promotion.

Do not rewrite historical entries above to make this final target appear preordained. The architecture changed as runtime evidence and user design decisions accumulated.

## 0.8.34-dev — six-owner structural consolidation complete

- Absorbed the exact `Location.lua` implementation into a scoped block at the end of `Presets.lua`, preserving its former post-Presets execution order and local namespace.
- Absorbed the exact `ChatFeedback.lua` implementation into a scoped block at the end of `Communication.lua`. Its only Options-side dependency (`SCB_DebugLog`) is runtime-resolved inside the server-rejection handler, so moving the presentation/event registration earlier does not require a late bridge.
- Removed standalone `Location.lua` and `ChatFeedback.lua` from the repository/TOC.
- TOC now loads the six agreed non-locale Lua owners: `SoloCraftBots.lua`, `Presets.lua`, `Roster.lua`, `Spawn.lua`, `Communication.lua`, and `Options.lua`.
- Behaviour is intentionally unchanged; this build completes structural ownership consolidation only. Post-consolidation slot-editor/UI cleanup and the full regression pass remain separate work.

## 0.8.35-dev — pace mass Kick All teardown

- Changed only non-dead `Kick All` teardown to issue at most five `UninviteByName` requests per 0.10 seconds.
- The first batch may fire immediately; later batches do not catch up after frame stalls, preventing a lag spike from collapsing several batches into one burst.
- Preset replacement inherits this pacing because its destructive rebuild path calls the same `SCB_KickBots(false)` entry point and already waits for live roster teardown before the existing removal-settle gate.
- `Kick Dead` / maintenance dead removal is intentionally unchanged in this A/B build so repeated disconnects during mass Kick All can be isolated.
- Survivor selection and Kick All anchor behaviour are unchanged.

## 0.8.36-dev — make pfUI tank marking event-driven

- Removed the `SCB_ApplyLivePfUITankRoles()` live-roster reconciliation path and its full `pfUI.uf:RefreshUnit(frame, "all")` sweep.
- SCB now sets a tank name once when an authoritative spawn intent is bound to that bot, including the roster-delta identity fallback.
- `SCB_ApplyTrackedPfUITankRoles()` remains only as an idempotent compatibility/fallback path for authoritative tracker names (including human tank assignments); it only sets previously-unset tank names and does not clear/rebuild the table or refresh every raid frame.
- Ordinary roster changes and combat-role evidence no longer cause pfUI tank-role reconciliation.
- Static follow-up audit found additional roster-event amplification: repeated Live Roster rebuilds, 40-row role-indicator refreshes, full live-layout scans, auto-promote scans and optional role-detection rebuilds. These are recorded separately for post-0.8.36 cleanup rather than bundled into this runtime gate.

## 0.8.37-dev — consolidated runtime tracking optimisation

- Combined the planned tracking/performance phases into one rollbackable runtime commit.
- The normal roster-event path now builds one canonical Live Roster observation and passes/reuses it for Active Roster and maintenance state instead of forcing repeated fresh roster builds.
- Roster deltas use the last handled Blizzard roster-event snapshot, so explicit safety/maintenance polls cannot corrupt change detection.
- Auto-promote work is limited to human membership/rank changes during roster handling; bot-only churn no longer causes a full promotion scan.
- Preset player rows no longer refresh for bot-only roster events.
- Preset role indicators, Replace Dead/Missing button state, optional role-detection lifecycle, and observational live-layout updates are debounced/coalesced during roster storms.
- Hidden preset role-indicator UI is left dirty for the next visible refresh rather than swept while off-screen.
- Combat-role evidence updates the cached Live Roster member directly instead of forcing a complete roster rebuild.
- The preset/spawn scheduler, communications timeout/chunk worker, and developer debug updater now sleep while idle and wake only when their timed work is active.
- Spawn/maintenance safety barriers that intentionally require fresh arrivals/departures/combat/subgroup/capacity observation are unchanged.
- Wrapper-chain flattening is deliberately deferred until this performance build is runtime-proven.

## 0.8.38-dev — flatten hot runtime wrapper chains

- Replaced the layered roster-change wrapper stack with one explicit `SCB_HandleRosterChange()` flow while preserving the 0.8.37 consumer order and debounce behaviour.
- The roster handler now captures group members once, binds pending identities against that raw snapshot, and builds the enriched Live Roster from the same snapshot instead of scanning the group twice.
- Folded RoleTracking and Detection Live Roster enrichment directly into `SCB_BuildLiveRoster`.
- Folded Active Roster tracker establishment, bootstrap exclusion and replacement role-reset semantics into their owner functions.
- Moved tracker post-finalization reconciliation/layout observation into one explicit finalization flow.
- Flattened the Spawn scheduler and preset-summon wrapper chains into public entry points around private cores.
- Flattened bot-operation presence/abort/reset handling and removed the historical Previous/Original closure chain from the active Spawn path.
- Preserved maintenance abort semantics, survivor/bootstrap handling, removal settle timing and 0.8.37 idle-worker behaviour.
- Mass Kick All pacing remains unchanged at 5 uninvites per 0.10s for this runtime gate.

## 0.8.39-dev — broad runtime efficiency pass

- Documented and preserved the SoloCraft combat-safety invariant: combat checks remain aggressive and independent of roster revisions.
- Removed repeated ready-tracker re-finalization and Active Roster reconstruction while preserving late identity-reconciliation retries.
- Added roster-event revision tracking plus a bounded 0.25s operation fallback observation for missed Vanilla roster events.
- Converted hot membership/count/anchor, refill-arrival, bootstrap-G1 and finalization-group checks to consume canonical Live Roster state.
- Pre-indexed tracker and Active Roster associations during Live Roster construction; removed per-member linear lookup amplification.
- Captured raid index/group-row in the canonical roster pass and reused it for live-layout tracking.
- Avoided healthy-slot replacement-record/spawn-command allocation during maintenance-state scans.
- Reused the delayed world-reconcile roster snapshot instead of immediately rebuilding it for downstream consumers.
- Developer-only combat/chat events are now registered only while developer debug is enabled.
- Consolidated CHAT_MSG_SYSTEM handling to the main SCB event dispatcher.
- Reduced hidden/duplicate preset UI work and role-detection allocations.
- Kick All pacing, combat gates, 3s removal settle and 1s arrival stabilization are unchanged for this runtime gate.


## 0.8.40-dev — combat-safe preset rebuild entry

- Added a root combat preflight before destructive preset teardown for normal clicks.
- Ctrl-click is now carried explicitly through the preset operation intent as the teardown override; add-time combat safety remains unchanged.
- Normal operations that enter combat while waiting for in-flight adds no longer kick until combat clears.
- Updated unresolved-human summon wording to identify the selected preset rather than one player.
- Runtime commit: `eb76b9e232d94169dd2c2403300bf83bc9b09d51`.
- Runtime test pending.


## 0.8.41-dev — same-frame Kick All A/B

- Replaced paced Kick All (5 uninvites per 0.10s) with same-frame removal requests from one stable roster snapshot.
- Survivor selection/anchor semantics and Kick Dead remain unchanged.
- Runtime commit: `204b0b305168bc421f05bdd8bfc63c219f0a4b59`.
- Runtime test pending; next build is mixed-group maintenance bursts.


## 0.8.42-dev — mixed-group maintenance bursts

- Maintenance replacement now batches the next up to five sorted missing/dead intents across destination groups.
- Replacement identity is resolved through the existing burst-ID/logical-slot assumption map instead of physical roster ordering.
- Each bot is moved/verified against its own intended subgroup; one subgroup mutation is issued per fresh observation, with `SwapRaidSubgroup` used for full-group exchanges when available.
- One common 1.0-second stabilization covers the whole mixed burst before the next batch.
- Combat safety, 3-second removal-capacity settle, survivor handling and server-authoritative rejection behaviour are unchanged.
- Runtime commit: `856a38c16e59a99d35462bd61a3f8e201f7fbcbf`.
- Runtime test pending.


## Combat-safe preset teardown runtime result — 2026-09-19

- The 0.8.40 root combat preflight passed runtime testing: a normal preset summon while already in combat blocks before any destructive bot teardown.
- Same-frame Kick All and mixed-group maintenance remain pending 40-player runtime coverage.


## 40-player Kick All A/B result — FAILED

- The 0.8.41 same-frame Kick All A/B disconnected the player/client during a 40-player raid test.
- Same-frame mass uninvite is rejected; restore the prior 5-per-0.10s removal pacing.
- Keep the 0.8.42 mixed-group maintenance implementation for separate runtime testing.


## 0.8.44-dev — unified bot removal

- Replaced the old boolean KickBots contract with explicit `"all"` / `"dead"` modes.
- Kick All, Kick Dead, preset teardown and maintenance now use the same paced physical removal path (5 per 0.10s).
- Maintenance filters dead removal to its exact tracked names; Replace Missing enters the same function as a filtered no-op when there is nothing live to remove.
- Retained maintenance survivor removal also uses the shared queue.
- 3-second removal settle, survivor lifecycle, mixed-group maintenance bursts and add-time combat safety are unchanged.
- Runtime commit: `8b26872df77c09e0a6e8b28b7211e46994ab70ab`.
- Runtime test pending.
