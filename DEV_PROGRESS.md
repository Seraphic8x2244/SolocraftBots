# Development Progress

> Sole live handoff for SoloCraftBots development. Git history carries history; keep this file focused on current constraints, proven behaviour, unresolved questions and the next coherent step.

## Current
- Branch: `dev`
- TOC version: `0.8.110-dev`
- Current implementation head before this handoff update: `16231b8334d195b746d2e3c4e50db995a3afedfc`
- Runtime-tested baseline for the Request slice remains `0.8.105-dev` at handoff `7999592220cc3893153f1226513c6110058a6c6e`; friend/test peer is currently offline, so Request protocol 8 remains runtime-pending.
- Stable `main`: `0.8.78` at `87e61360ec36c2d9543b2e1bc8606b948b10d6bd`; tested dev source `0200cdb5ef59fc0cb4ef81016237d90ba16e22b9`
- Receiver-owned location-capacity guardrail remains explicitly accepted as correctness/state-integrity protection.
- Request protocol 8 carries no loot-setting behavior; Auto Loot remains addon-level state owned by the current group leader's SCB.
- `0.8.108-dev` side-drawer justification layout is **runtime-confirmed working** by the user.
- `0.8.109-dev` readability/palette pass was visually received positively by the user from runtime screenshot; exact Request runtime remains unrelated and pending.
- `0.8.110-dev` is a narrow header-homogeneity pass:
  - Preset Manager title centered.
  - Options title centered.
  - Both drawers now have matching top-right Lucide `X` close buttons using the existing global 14px chrome size.
  - Preset Manager's self player class/role controls are hidden from the visible header but their frames, saved-role logic and refresh code remain intact.
- Immediate goal: runtime-check only the 0.8.110 visual/header delta locally; Request protocol 8 can wait until a second SCB player is available.

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

## Requested preset ownership — current protocol 8
- No Request path transfers party or raid leadership.
- No leadership/conversion side effect occurs before Accept.
- **Execution capacity is receiver-owned.** On Accept, the requestee compares `snapshot.size` against `SCB_GetLocationMaxCapacity(SCB_GetLocationContext())` using the requestee's current location. The same check runs again immediately before execution.
- Canonical capacity model remains: world 5; normal dungeon 10; Blackrock Spire/UBRS 15; ZG/AQ20 20; MC/Onyxia/BWL/AQ40/Naxx 40.
- If requested size exceeds the requestee's local maximum, refuse before conversion/destructive work.
- For an accepted >5-player snapshot that is locally valid while still in a party, the **actual current party leader** receives `CONVERT` and automatically calls `ConvertToRaid()`.
- The receiving summoner does not require Raid Assistant or raid-leader authority to summon bots.
- **Loot settings are not part of Request.** No snapshot field, Request state, leader-control action or Request completion condition may carry/apply the requestee's Auto Loot preference.
- Auto Loot remains ordinary addon-level behavior: every client may hold its own preference, but `SCB_ApplyAutoLootMethod()` only mutates loot when that client is the current party/raid leader. Therefore the current leader's SCB and setting are authoritative, independent of who requested or accepted the preset.
- Request communications are protocol 8. Protocol 7 is intentionally incompatible because it still contained Request-specific loot negotiation/delegation.

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
- 0.8.103 separated Lucide texture size from button-frame size while preserving existing hitboxes.
- 0.8.104 shipped defaults are **12px for Command Buttons** and **10px for Preset Groups**. Existing profiles migrate untouched 14px baselines to those defaults; explicit user adjustments are preserved.
- Command Buttons -> `Icon Size` live-controls Focus/CC/Clear plus the Command/Assignments section chevrons and the Command Buttons options-subsection chevron.
- Preset Groups -> `Icon Size` live-controls Resummon Group, the Presets drawer and selector chevrons, the Preset Groups options-subsection chevron, and preset dropdown Delete/Rename/Move icons.
- Lucide chrome outside those two scoped areas remains fixed at the global 14px default. Non-Lucide Command Bots/gameplay/class/role artwork is unchanged.
- `artwork/LUCIDE_LICENSE.txt` carries the upstream Lucide/Feather license notice for the distributed artwork.

## Side-drawer justification
- Account-wide option: `SoloCraftBotsDB.options.drawerJustification` = `"left"` or `"right"`; invalid/missing values default to `"right"`.
- Main-window top-left chevron displays the **current** justification: `<` for Left, `>` for Right.
- Preset Manager is always the inner side drawer next to Main when open.
- Options is always the outer drawer when Preset Manager is open; otherwise Options sits directly beside Main.
- Opening/closing Preset Manager or Options, or toggling justification, re-anchors visible drawers immediately.
- `0.8.108-dev` layout behavior is user-confirmed working.
- `0.8.109-dev` sizes the justification chevron from the live Command icon-size value so it matches the main vertical Command/Assignments section chevrons.

## UI text palette
- `Locale/Chat.lua` is the single editable source for the shared SCB/UI palette:
  - `COLOR_SCB = 88CCFF` — existing light-blue chat color and primary UI headers.
  - `COLOR_UI_GOLD = FFD100` — section/subsection headers.
  - `COLOR_UI_SILVER = C0C0C0` — ordinary descriptive/value text.
  - `COLOR_UI_WHITE = FFFFFF` — button and dropdown content.
- Main headers `SoloCraft Bots`, `Preset Manager`, and `Options` use SCB blue.
- Main sections and Options subsections (Presets, Command Bots, Assignments, Summon Bots, Misc, Chat Filtering, Layout, Command Buttons, Preset Groups, etc.) use gold.
- Ordinary text in the three primary windows uses silver.
- Text-button/dropdown content uses white.
- Semantic color remains allowed where it communicates state or identity, notably class-colored player names and red/green preset save/risk feedback.

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
- Preset protocol is now `SCBPRESET` protocol 8. Snapshot payload contents are unchanged and still carry logical composition/human slot intent, never generated bot names; protocol 8 keeps leadership fixed, enforces receiver-local execution capacity, uses leader-directed party->raid conversion where required, never gates summoning on assistant rank, and carries **no loot-setting behavior**.
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

## 0.8.110 implementation / static validation / next runtime test
1. **0.8.108 drawer layout: USER TESTED PASS.**
   - Left/right drawer anchoring and dynamic Options placement work.
   - No need to repeat unless the header-only change causes a visible regression.

2. **0.8.109 readability pass: RUNTIME VISUALLY POSITIVE.**
   - User supplied an in-game screenshot and described the result as looking really good.
   - Shared blue/gold/silver/white hierarchy remains unchanged in 0.8.110.

3. **Header homogeneity: IMPLEMENTED; runtime visual check pending.**
   - Preset Manager and Options titles now use the same centered top anchor as the main SCB title.
   - Preset Manager and Options each have a top-right 18x18 control with the existing 14px Lucide `X` glyph and Close tooltip.
   - Close buttons route through the existing `SCB_SetPresetPanelShown(false)` / `SCB_SetOptionsPanelShown(false)` owners.
   - Preset self class/role controls remain fully instantiated and refreshed but are hidden after creation; no underlying per-character role/default code was deleted.

4. **Checks performed.**
   - Verified starting handoff exactly matched `6800964a6917e9dc951ff4976075b4c071758e42` / `0.8.109-dev`.
   - Current implementation head before this handoff update is `16231b8334d195b746d2e3c4e50db995a3afedfc`; TOC is `0.8.110-dev`.
   - Static inspection confirms centered Preset/Options headings, both close buttons and existing visibility owners, hidden Preset self identity controls, and retained `SCB_RefreshCharacterPresetIdentity()` logic.
   - Canonical Lua 5.0.3 compiler check is **not run/unavailable** in the current executable environment; do not claim a compiler pass.

5. **Exact next runtime test.**
   - Confirm Preset Manager and Options titles visually align/center like the main `SoloCraft Bots` title.
   - Confirm each drawer's new `X` closes only that drawer and the remaining side-panel layout reflows correctly through existing logic.
   - Confirm the Preset Manager no longer visibly shows the player's class/role icons in its header.
   - No Request retest is required until a second SCB player is available.


## Deferred / later
- Audit remaining All-row/server target sensitivity.
- Remove only proven-dead legacy refill/compatibility code after runtime proof.
- Add neutral read-only activity/status surface, then visualiser as a presentation-only consumer.
- Historical regression debt: dungeon -> 10-player scope retest; Replace Dead focused smoke; investigate dead-state observation only if the old omitted-dead-bot case recurs.

## Release note
Do not promote the current dev line. Stable remains `0.8.78` on `main`. Release preparation must compare `main` and `dev` rather than overwrite main because histories have diverged.
