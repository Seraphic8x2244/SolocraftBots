# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.8.103-dev`
- Current implementation head before this handoff update: `c6c7deaed2b5b06664add387ece257681d336764`
- Runtime-tested baseline for this slice: `f9760a20c176f5d0123b9f7829fbc5b32e6b93c6` (`0.8.92-dev`; runtime files correspond to implementation `8bd3b38f64a17372b884bf5d58a6a701e45ec84b`)
- Stable `main`: `0.8.78` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested dev source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- `0.8.92-dev` passed the summon/logical-slot/subgroup gate. Do **not** ask the user to repeat the stuck-summon test; they explicitly tested two different 10-player presets and accepted it.
- `0.8.97-dev` direct Feral Bear/rage validation is runtime-confirmed.
- `0.8.101-dev` remains the latest Request/Resummon runtime result: receiver Auto Loot, refusal side effects, existing-raid transfer and already-leader Request paths passed; the old party requester -> receiver leadership transfer failed; Resummon Group worked but human-containing groups could lose combat-role ticks.
- `0.8.102-dev` contains the targeted human-group Resummon role-validation refresh fix, exact official Lucide raster artwork and the `Preset Manager` rename; those deltas remain runtime-pending.
- `0.8.103-dev` corrects the Request contract again: preset Request **never transfers party or raid leadership**. For >5 requests in a party, the actual party leader's SCB automatically calls `ConvertToRaid()`; after conversion the receiver proceeds as Raid Assistant, asking the actual raid leader to promote it only if assistant authority is missing. Receiver Auto Loot is delegated to the actual leader when leader-only authority is required, including assigning the receiver as Master Looter for the `master` setting.
- `0.8.103-dev` also formalizes Lucide rendering at a 14px default while preserving existing control hitboxes. Options -> Command Buttons and Options -> Preset Groups each have an `Icon Size` control (effective range 8-24, default 14) with immediate live updates for their scoped Lucide controls.
- Immediate goal: runtime-test the 0.8.103 no-leadership-transfer Request flow, the 0.8.102 human-containing Resummon validation fix, and the 14px/live Lucide sizing pass. Combat mismatch popup and Cat/energy validation remain opportunistic coverage, not blockers.

## Architecture / ownership
- `SoloCraftBots.lua`: bootstrap/core/shared UI/primitives.
- `Presets.lua`: configured preset intent, editor, snapshots, validation and raid-role tracker creation/finalization.
- `Roster.lua`: observed party/raid reality, human/bot classification, Active Roster, provisional spawn assumptions, combat-role evidence and passive layout classification.
- `Spawn.lua`: sole owner of physical roster mutation through `SCB.botOperation`: summon/rebuild, add, subgroup moves, maintenance/refill, bootstrap/survivor handling.
- `Communication.lua`: PartyBot command transport, command semantics, incoming chat/system feedback and preset communications.
- `Options.lua`: settings/help/debug.
- Preserve one physical-operation coordinator. Presentation code must not mutate roster state.

## Authoritative logical / physical model
- A preset slot is intent. A human assigned to logical slot N suppresses exactly that slot's bot class/role intent.
- Party physical order is client-relative and cannot represent shared logical identity. Never warn because a party human is not in their logical absolute row.
- Raid subgroup membership is enforceable with `SetRaidSubgroup()`; exact row/order inside a subgroup is not.
- During raid rebuild, configured humans must be moved to their intended subgroup by name before bot bursts continue. Re-resolve raid indices immediately before each move.
- Human absolute row is irrelevant to bot identity.
- Full rebuilds intentionally burst one logical group at a time. Human-covered assignments are omitted, so a group with two humans and three bot intents summons exactly three bots.
- Preserve the established reverse-send/LIFO behaviour and the existing per-group settle boundary. Do not pack full-rebuild assignments across groups merely to save a burst.
- Final identity is the settled subgroup's **bot-only ordinal order** mapped to uncovered logical assignments in ascending slot order. This is the proven pre-0.8.87 principle from `6bcc9949222513d4f8e38a90d43071149f162f31`.
- Join-line name -> intent binding is provisional/operational identity. It remains important for mixed-group refill, but it must not overwrite settled full-rebuild ordinal identity.

## 0.8.97 implementation
### Full summon / rebuild identity — accepted baseline from 0.8.92
- `SCB_ArrangePresetHumanGroups()` preserves the proven subgroup-preparation rule: humans are resolved by name, moved only between subgroups, then subgroup membership is freshly verified. No row forcing exists.
- Full rebuild queues uncovered assignments group-by-group and uses `PRESET_WAIT_GROUP` between groups.
- `SCB_TryFinalizeRaidRoleTracking()` filters humans, obtains bots by Blizzard subgroup, requires exact per-group bot counts, then maps bot-only ordinal order to assignment order.
- `SCB_PostFinalizeRaidRoleTracking()` does not reconcile settled ordinal identity back through provisional join assumptions.
- `SCB_ReconcileTrackerFromAssumedRoles()` remains defined but has no call sites. Keep cleanup deferred until later.
- Active Roster settled identity outranks provisional `assumedRolesByName`; combat evidence never rewrites intended `slot.role`.

### Passive layout warning
- Party absolute-row mismatch logic remains removed.
- Raid mismatch classification is subgroup-only.
- 0.8.92 runtime: manually moving the user to the wrong raid subgroup correctly produced a warning and the next full Summon put them back into the configured subgroup.
- 0.8.92 presentation problem: the whole-group yellow pulse was so subtle that the user initially thought the build was stale.
- 0.8.93+ presentation change: mismatch classification also returns the exact logical slot(s) whose known member is in the wrong subgroup. Only those character rows receive a stronger gold pulse; the whole group background no longer pulses. The group tooltip remains available.
- This is presentation only; it does not change subgroup correction or physical roster ownership.

### Combat-role validation semantics
- Intended role and combat-confirmed role remain separate state. Evidence never mutates the requested role/preset.
- Validation-eligible classes remain Warrior, Paladin, Shaman, Druid and Priest.
- Rogue/Hunter/Warlock remain excluded. Runtime 0.8.92 confirmed Rogue correctly receives no second validation indicator.
- Mage remains excluded because Fire/Frost are preset specs but both map to `rangedps`; the current role validator cannot honestly distinguish the spec.
- First green tick = SCB bound the bot to that logical assignment.
- Second-indicator semantics remain the user's intended red/yellow/green progression:
  - no role evidence yet: red check = not validated yet;
  - one recognised independent observation: yellow check;
  - two observations agreeing with intended role: green check;
  - confirmed different role: persistent red `X` plus active warning.
- 0.8.94 temporarily removed the red stage-0 tick and broadened the spell catalogue; both were explicitly rejected by the user and reverted in 0.8.95.
- A confirmed mismatch opens a real `StaticPopup` (unless the user has explicitly hidden SCB screen warnings) and also writes the chat warning. The transient 2.4-second centre message is no longer the primary mismatch alert.
- Do not broaden the role-specific spell catalogue without explicit agreement. The original role-spell set is retained.
- Feral Druid validation uses the live power bar directly and does not inspect `Faerie Fire (Feral)` to distinguish bear/cat:
  - rage power type = bear/tank evidence;
  - energy power type = cat/melee evidence;
  - mana power type = no Feral-role evidence, then normal spell evidence may still apply.
- 0.8.96 still sampled the power bar only after combat text identified that Druid as the source. Runtime proved this was the wrong trigger: two bots visibly entered Bear Form while their validation checks remained red outside combat.
- 0.8.97 removes that combat gate. While role validation has pending tracked bots, the existing detection frame directly samples pending Druid unit power every 0.35 seconds. The interval is intentionally just beyond the existing 0.30-second duplicate-observation guard, preserving the established two-observation red -> yellow -> green threshold without introducing a second lifecycle.
- Power evidence remains `Rage power` or `Energy power`; no intended-role value is consulted.
- Full rebuild still starts a fresh role-validation epoch by clearing prior evidence/recent-observation/mismatch-warning state.

## Requested preset ownership — current protocol 5
- A Request no longer requires the requester to create a raid before sending a >5-player preset.
- No Request path may transfer party or raid leadership. `PromoteToLeader` is not part of the protocol.
- No leadership/conversion side effect occurs before Accept.
- For an accepted >5-player snapshot while still in a party, the **actual current party leader** receives the SCB `CONVERT` control action and automatically calls `ConvertToRaid()`. There is no popup or manual confirmation.
- After raid formation is authoritative, the receiver continues as its existing raid rank. If it is still rank 0, it sends `ASSIST` to the actual current raid leader; that leader calls `PromoteToAssistant(receiver)`. Existing Auto Promote Humans may make this unnecessary.
- Subgroup movement/removal authority is therefore obtained through Raid Assistant, never raid leadership.
- The receiver's configured Auto Loot Method remains authoritative for a Request. If the receiver is not raid leader and the method is not `off`, it sends `LOOT_<method>` to the actual raid leader; the leader applies that method. `master` assigns the receiving summoner as Master Looter.
- `SCB_ApplyAutoLootMethod(methodOverride, masterName)` supports this delegated leader execution while preserving existing no-argument local behaviour.
- Vanilla parties have no assistant rank. For a <=5 Request that remains a party, a non-leader receiver is refused rather than transferring leadership; supporting that case later would require explicit delegation of party-leader-only destructive operations.
- If the required current leader is not running compatible SCB, the accepted operation fails/times out safely rather than changing leadership.
- Request communications are protocol 5. Older protocol peers fail the normal offer handshake rather than mixing authority semantics.

## Refill / maintenance contract
- Refill intentionally differs from full rebuild: up to five missing/dead assignments may be mixed across destination groups in one burst.
- Keep exact burst intent records, reverse send, join-assumption identity, subgroup movement and Active Roster replacement binding.
- Do not redesign refill into group-by-group bursts; mixed-group refill saves meaningful time.
- Combat-role validation is an independent watchdog for mistaken mixed-burst identity assumptions, not a reason to remove that optimisation.
- 0.8.99 added **Resummon Group** as another `kind="maintenance"` action rather than a new physical-operation path; 0.8.101 keeps that physical backend and removes the rejected target-selection presentation layer.
- **Implemented authoritative Resummon Group UX:** each visible preset group owns a mini `RotateCcw` button inside the `Group N` title/header, justified right. Clicking it passes that logical group directly into the maintenance action. No target selection or target-dependent enablement remains.
- The provisional full-width Command Bots Resummon Group button, target-as-group-selector helpers and target-driven refresh path are removed.
- The action should rebuild every expected tracked bot assignment in the chosen logical group, including already-missing tracked assignments. Humans and unbound/manual bots remain untouched.
- If any tracked assignment in the selected group cannot produce a valid replacement record, the action aborts before kicking anything; no partial destructive resummon.
- Destination capacity remains preflighted before any kick. Humans, manual/unbound bots and other non-removed occupants count against the five-player destination capacity; if the complete tracked group cannot fit, the action refuses unchanged rather than failing mid-rebuild.
- Live tracked bots in the selected group remain routed through the shared paced kick queue, existing 3-second capacity settle, combat wait, assumed-spawn burst identity, subgroup placement and Active Roster binding paths.
- If the selected group contains every live bot and survivor safety is required, preserve the existing retained-survivor lifecycle. A lone required survivor must be left in place rather than risking instance removal.
- Runtime 0.8.101: direct group rebuild works and humans remain untouched, but a group containing humans can return without combat-role validation ticks. 0.8.102 targets the identified post-bind refresh gap: replacement binding now clears recycled per-name role evidence/live confirmation and queues the existing preset-indicator + role-detection lifecycle refresh. Runtime confirmation is pending; Resummon Group itself remains the same maintenance operation.

## Mini-button visual system — finalized design; 0.8.102 exact artwork implemented
Lucide is used only for the **small utility/chrome controls**. This is not a global artwork redesign. Use the exact official/free Lucide glyph geometry, rasterized directly to Vanilla-compatible TGA; do not redraw, stylize or AI-reinterpret it. The source TGAs remain 32x32, but Lucide textures now render centred at a **14px default** inside the existing control hitboxes.

Agreed Lucide mapping:
- Main Close: `X`.
- Options / Config: `Cog`.
- Section expand/collapse: `ChevronDown` / `ChevronUp` (**plain Candidate 1**, separate icon assets).
- Presets drawer open/close: `ChevronLeft` / `ChevronRight` (separate icon assets).
- Dropdown indicator: `ChevronDown`.
- Preset Delete: `Trash`.
- Preset Rename: `Pencil`.
- Preset Move Up: `ArrowUp`.
- Preset Move Down: `ArrowDown`.
- Resummon Group: `RotateCcw`.
- Spawn Near/Far: `Telescope`; retain state treatment rather than using different semantic glyphs.
- Clear Focus/CC assignments: `Eraser`.
- Assignment mode Focus: `Crosshair`.
- Assignment mode CC: `WandSparkles` (chosen specifically for WoW sheep/polymorph/magic-CC semantics).
- Layout Increase: `Plus`.
- Layout Decrease: `Minus`.
- Checkbox Off/On: `Square` / `SquareCheckBig`.
- Debug Close: reuse `X`.

Explicitly **unchanged**:
- all Command Bots button artwork;
- preset and Summon Bots class/role icons;
- player role icons;
- blessing/totem icons;
- raid-mark icons;
- other gameplay/identity artwork.

Implementation intent:
- use the Lucide pass to unify only the mini-control layer;
- preserve current tooltips, state semantics and click behaviour unless separately specified;
- do not substitute Lucide icons into the Command Bots matrix or role/class systems.
- 0.8.102 uses direct rasterizations of the official Lucide SVG geometry for all 20 existing `artwork/lucide_*.tga` files. Telescope retains separate silver/off and gold/on state treatment.
- 0.8.103 separates Lucide texture size from button-frame size: all Lucide controls default to 14px without shrinking their existing hitboxes.
- Options -> Command Buttons -> `Icon Size` live-controls the scoped Assignment utility Lucides (Focus/CC and Clear); Options -> Preset Groups -> `Icon Size` live-controls the per-group Resummon Lucide. Both default to 14 and update immediately.
- Other Lucide chrome remains fixed at 14px. Non-Lucide Command Bots/gameplay/class/role artwork is unchanged.
- `artwork/LUCIDE_LICENSE.txt` carries the upstream Lucide/Feather license notice for the distributed artwork.

## Other preserved invariants
- Active Roster keeps logical identity/expected state separate from observation. Human-covered bot slots remain dormant intents; if the human leaves before replacement they become missing; if the human returns before replacement they become covered again.
- After a missing human slot has been replaced by a bot, do not auto-kick/free capacity when the human returns.
- Capacity reuse remains: removal observed absent -> 3.0s settle -> dependent add.
- Bootstrap is continuity-only; reuse an existing bot when possible.
- Maintenance remains `botOperation(kind="maintenance")`; player combat is an absolute block and the existing stale-remote-combat allowance remains.
- Manual Add remains coordinated through `botOperation(kind="manual-add")`.
- Raw user-typed `.partybot add ...` remains outside SCB coordinator ownership.
- Taxi safety remains action-time only through `SCB_CanOperateBots(showError)`.
- Never use `UnitHealth()==0` as a dead-state fallback.
- Preset protocol is now `SCBPRESET` protocol 5. Snapshot payload contents are unchanged and still carry logical composition/human slot intent, never generated bot names; protocol 5 keeps leadership fixed while adding leader-directed party->raid conversion, assistant promotion when required and delegated receiver-selected loot setup.
- Command semantics and tested Ctrl-Come/Move/Stay behaviour are unchanged.

## Runtime results
Exact `0.8.92-dev` baseline:
1. **5-player logical-slot regression: PASS.**
   - User confirmed non-first logical player placement suppresses/replaces the correct underlying bot intent.
   - No invalid party row warning reported.
2. **10-player subgroup + deterministic summon: PASS.**
   - User tested two separate 10-player presets with the player in Group 1 in one preset and Group 2 in the other.
   - No stuck `Preset Summon is already in progress` state.
   - User explicitly does not want this re-tested.
3. **Passive subgroup detection/correction: PASS through 0.8.96.**
   - Manual wrong-subgroup move was detected.
   - Full Summon restored the configured subgroup.
   - 0.8.92 whole-group pulse was too subtle.
   - User runtime-tested the targeted character-box pulse in 0.8.96 and confirmed it is working.
4. **Combat validation: PARTIAL; 0.8.97 Feral power path PASS.**
   - Rogue exclusion passed.
   - Two feral Druids and one DPS Warrior did not accumulate evidence at a reasonable rate while clearing roughly 25% of Stockades at level 60; one feral reached yellow, the others remained stage 0.
   - User observed repeated Feral Faerie Fire, which 0.8.92 ignored because the spell is shared by bear/cat.
   - User also clarified that a genuine mismatch must produce an obvious popup rather than relying on a passive icon/transient centre message.
   - 0.8.96 direct power inference was runtime-tested with two bear Druids: both visibly entered Bear Form but remained red because the read was still combat-text-triggered.
   - 0.8.97 direct-power rebuild is runtime-confirmed: a preset-bound Druid validated as soon as Bear Form/rage appeared, without requiring combat.
   - User also manually joined an unbound Cat Druid after kicking a Rogue. Preset Manager correctly did not show that Druid, a role-validation tick, or a subgroup-warning highlight because it had no preset/logical-slot binding. This is expected behaviour, not a regression.

## Static validation for 0.8.97
- Verified `dev` was still exactly at the 0.8.96 handoff before the write; the implementation update was fast-forward only.
- Reviewed the 0.8.97 diff.
- Confirmed the combat handler no longer performs the Feral power inference.
- Confirmed a single direct scanner now reads pending Druid live unit power through the existing role-detection lifecycle.
- Confirmed the scanner retains the existing two-observation threshold and uses a 0.35-second sample interval, just beyond the existing 0.30-second duplicate guard.
- Confirmed there are zero `Faerie Fire (Feral)` references in `Roster.lua`.
- Confirmed the red stage-0 validation tick remains restored and the unrequested extra Warrior/Druid spells remain absent.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.99
- Verified `dev` still matched the documented 0.8.97 handoff before writing; implementation commit was a fast-forward.
- Reviewed the Resummon Group implementation diff `0785bca9cade18ca7aca798f41791b1b666e5ad8` plus the destination-capacity guard `20ee998a730cd9afd9b6524713a4d57066fabc11`.
- Confirmed Resummon Group starts `SCB_BeginBotOperation("maintenance", ...)` and stores its state in `operation.maintenance`.
- Confirmed removals route through `SCB_KickBots("all", { names=..., manageSafety=false, silent=true })`; no new uninvite scheduler exists.
- Confirmed replacement bursts still use `SCB_0826BeginMaintenanceBurst()`, the existing assumed-spawn burst identity path and `SCB_BindReplacementToActiveSlot()`.
- Confirmed humans/unbound bots are not added to the removal-name set.
- Confirmed invalid/unbuildable selected-group records abort before any kick.
- Confirmed destination occupancy is checked before removal so an unbound/manual bot cannot make the rebuilt tracked group overfill a party/raid subgroup after destructive work has started.
- Historical note only: 0.8.99 statically confirmed target-driven button refresh, but that UX is now rejected and must be removed during the Resummon Group redesign.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.100
- Verified `dev` matched the documented 0.8.99 handoff before the implementation write; update was fast-forward only.
- Reviewed implementation diff `bc77a914da0c11e15939216abcb0bf51925d5d94`.
- Confirmed the old sender-side “create a raid before requesting” and Raid Assistant preconditions are gone.
- Confirmed leadership transfer is receiver-initiated only after Accept, not when the prompt is merely received.
- Confirmed the receiver waits for local leader authority before conversion/rebuild and waits for raid formation before continuing a >5 request.
- Confirmed receiver-side Auto Loot is applied immediately before the accepted rebuild and queued for retry using the existing auto-loot path.
- Confirmed raid loot authority now checks local raid rank 2 instead of depending only on `IsPartyLeader()`.
- Confirmed communication protocol is 3 on both serialized snapshots and offer handshakes.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment.

## Static validation for 0.8.101
- Verified `dev` was exactly at handoff `8f344391dfcb68cf2e5ba13549de82ff49e4e3fa` before the implementation write; the update was fast-forward only.
- Reviewed implementation diff `56b7a19a7d9a0df59d23e717112d2e918c233900`.
- Confirmed the provisional full-width Command Bots Resummon button and all target-as-group-selector helpers/refresh identifiers are absent.
- Confirmed each visible preset group creates a right-justified `RotateCcw` mini button carrying `scbGroupIndex`, and the maintenance backend now accepts the logical group directly.
- Confirmed the existing maintenance preflight/capacity/survivor/removal/spawn plumbing remains the physical execution path.
- Confirmed all 20 Lucide TGA assets are present as 32x32 32-bit assets; the Telescope keeps separate near/far state treatment while using the same semantic glyph.
- Confirmed stock `UICheckButtonTemplate` usage is removed from the mini-control layer and Command Bots/class/role/gameplay artwork was not replaced.
- Canonical Lua 5.0.2 compiler pass is **not claimed** in this environment; no Lua executable/project compiler is available in the current tool environment.

## 0.8.103 implementation / static validation / next runtime test
1. **Requested preset authority: IMPLEMENTED; runtime pending.**
   - Protocol bumped to 5.
   - Removed all `PromoteToLeader` use from preset communications. A legacy `L:...:REQUEST` control action is explicitly rejected rather than transferring leadership.
   - Accepted >5 party Requests send `CONVERT` to the actual current party leader; that leader automatically calls `ConvertToRaid()`.
   - Once the raid exists, the receiver uses Raid Assistant authority. If its rank is still 0, `ASSIST` is sent to the actual current raid leader, who calls `PromoteToAssistant(receiver)`.
   - If receiver Auto Loot is not `off` and the receiver is not raid leader, `LOOT_<method>` is sent to the actual leader. For Master Looter, the receiver's name is passed as the master target.
   - <=5 non-leader party Requests now fail safely instead of transferring leadership; no party-assistant equivalent exists.

2. **Lucide sizing: IMPLEMENTED; runtime visual check pending.**
   - All Lucide textures use a shared 14px default renderer while button/check hitboxes retain their existing dimensions.
   - Direct-texture Lucides (dropdowns, preset delete/rename, check states and arrows) were moved onto the same 14px geometry.
   - Command Buttons -> `Icon Size` and Preset Groups -> `Icon Size` were added with effective values 8-24 and default 14.
   - Changes apply immediately through the existing layout refresh path. Command scope updates Focus/CC/Clear; Preset scope updates Resummon Group.
   - The 32x32 source TGA assets are unchanged.

3. **Resummon Group validation: still implemented from 0.8.102; runtime pending.**
   - Replacement binding starts a fresh role-validation epoch for the final bound name and refreshes preset indicators/detection lifecycle.
   - The per-group `RotateCcw` UX and shared maintenance backend remain unchanged; no target-based Command Bots Resummon UI returned.

4. **Checks performed.**
   - Reconciled from branch head `65bb1706c4ef7e6df1346a54f7f1cf901a7d5af2` before this revision.
   - Reviewed all current Lucide call sites after implementation; global chrome routes to 14px rendering and the two agreed scoped controls use live layout values.
   - Confirmed `Communication.lua` contains zero `PromoteToLeader` references and protocol is 5.
   - Confirmed TOC version is `0.8.103-dev`.
   - Canonical Lua 5.0.3 compiler check is **not run/unavailable**: no mounted VanillaTemplate `tools/lua50/` checker and no system Lua/luac are available in this execution environment.

5. **Exact next runtime test.**
   - On `0.8.103-dev`, accept a >5 Request while still in a party with another human as actual party leader. Confirm that leader stays leader, their SCB converts automatically, the receiver becomes/remains Raid Assistant rather than raid leader, and the requested preset begins.
   - With receiver Auto Loot enabled, confirm the actual raid leader applies the receiver-selected loot method without leadership transfer; if practical, include Master Looter once.
   - Re-test an accepted Request that begins in an existing raid and confirm leadership remains unchanged.
   - Resummon a preset group containing at least one human and confirm rebuilt bots' combat-role ticks return.
   - Visually confirm global Lucides default to 14px, then change Command Buttons -> Icon Size and Preset Groups -> Icon Size and confirm each scoped icon set updates immediately and independently.
   - If a third SCB-capable human leader is available, exercise that path; otherwise keep it explicitly untested.

## Deferred / later
- Audit remaining All-row/server target sensitivity.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## Release note
Do not promote the current dev line. Stable remains `0.8.78` on `main`. Release preparation must compare `main` and `dev` rather than overwrite main because histories have diverged.
