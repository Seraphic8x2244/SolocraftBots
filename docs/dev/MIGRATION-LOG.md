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

## 0.8.8-dev — observed roster absorbed into Raid

- Removed the separate `Roster.lua` file and moved its observed Live Roster, persistent Active Roster, session/bot tracking, auto-loot, auto-promote and base roster-change responsibilities into `Raid.lua` ahead of the existing role-identity layer.
- The order inside `Raid.lua` deliberately mirrors the former TOC order: roster/base functions are defined first, then the former RoleTracking/Raid wrappers are installed over them.
- This makes `Raid.lua` the real owner of both observed roster and Active Roster state instead of merely being the renamed RoleTracking layer.
- No intentional identity, human-slot, maintenance or summon-policy change in this step. `RaidIdentity.lua`, `RaidLayout.lua`, `RaidRefill.lua` and Detection remain transitional layers for later passes.

## Presets sizing decision

- Do not force `Location.lua` or `Comms.lua` into `Presets.lua` merely to reduce file count.
- Continue moving non-preset runtime responsibilities out of `Presets.lua`, then reassess the resulting size and cohesion.
- Merge Location and/or Comms into Presets only if the final ownership remains clear and the file stays reasonably sized.

## Next consolidation direction

- The exact logical human-slot model has now passed a three-human BWL runtime test; preserve that behaviour while removing remaining transitional wrappers.
- Continue absorbing identity, live layout and maintenance responsibilities into the established `Raid.lua` owner in small steps.
- Audit cross-version Comms handling for exact human slots before main promotion; do not silently degrade exact-slot intent.
- Absorb `PresetRebuild.lua` into `Spawn.lua` during the summon state-machine consolidation rather than merely concatenating files.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.
