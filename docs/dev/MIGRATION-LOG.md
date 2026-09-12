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

## Presets sizing decision

- Do not force `Location.lua` or `Comms.lua` into `Presets.lua` merely to reduce file count.
- Continue moving non-preset runtime responsibilities out of `Presets.lua`, then reassess the resulting size and cohesion.
- Merge Location and/or Comms into Presets only if the final ownership remains clear and the file stays reasonably sized.

## Next consolidation direction

- The exact logical human-slot model has now passed a three-human BWL runtime test; preserve that behaviour while removing remaining transitional wrappers.
- Continue absorbing observed roster, identity, live layout and maintenance responsibilities into the established `Raid.lua` owner in small steps.
- Audit cross-version Comms handling for exact human slots before main promotion; do not silently degrade exact-slot intent.
- ~~Absorb `PresetRebuild.lua` into `Spawn.lua` during the summon state-machine consolidation rather than merely concatenating files.~~ Completed in 0.8.11-dev with the existing rebuild state transition kept intact inside Spawn.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.
