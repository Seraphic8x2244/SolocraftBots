# SoloCraftBots 0.7.14 Behaviour Baseline and 0.8 Approved Deviations

Purpose: preserve known-good 0.7.14 behaviour while clearly separating approved 0.8 changes. Items under **0.8 approved change** are intentional departures, not regressions.

## Presets and humans
0.7.14 supports preset sizes 5/10/15/20/40, stores bot class/role/extra intent, tracks Saved/Unsaved state and preserves underlying bot assignments when humans cover them.

**0.8 approved change:** human assignment becomes exact logical group + logical slot. A human explicitly suppresses that logical bot only while present. Saved present humans snap automatically when a preset loads/reloads; saved absent humans do not suppress the bot. Unsaved present humans remain in Other Players until assigned.

Blizzard raid row is not logical preset slot. Blizzard remains authoritative for live names, classes, subgroup and displayed order. SCB must not hard-code logical slot == Blizzard row. During formation humans can appear at the top of a subgroup while logically replacing lower/keyed slots. Bot ordering inside the subgroup is interpreted ignoring humans.

This supersedes the 0.7.14 presentation rule where same-group Blizzard movement could make the editor display the player in Blizzard's row with a green mismatch pulse. That 0.7.14 behaviour remains a historical regression reference only.

## Location/preset groups
- World: 5-man.
- Dungeons may run 10-man after entering an instance.
- Blackrock Spire supports 15.
- ZG/AQ20: 20.
- MC/Onyxia/BWL/AQ40/Naxx: 40.
- AQ40 runtime zone string is `Ahn'Qiraj`; display label may remain Temple of Ahn'Qiraj.
- Dirty preset must not be silently overwritten by location auto-swap.

**0.8 structural target:** canonical runtime location/capacity data moves into one coherent owner; localized labels must not act as runtime identifiers.

## Summoning
- Summoning sends validated `.partybot add ...` through SAY.
- Preset execution is snapshot-based.
- Same-burst SoloCraft processing is reverse/LIFO; SCB sends reverse command order so receive order matches logical plan.
- Normal logical burst is one subgroup, maximum five bot summons.
- Combat checks/retry and exact `Cannot add bots right now.` abort behaviour must survive consolidation.
- Final authoritative 0.7.14 scheduler is `Spawn.lua`; earlier scheduler layers are historical/compatibility code, not target ownership.

## Conversion / bootstrap continuity
- >5 compositions convert safely to raid where required.
- Ordinary solo >5 can use first real G1 bot to form party, convert, arrange humans, then continue.
- Solo T3 raid-zone starts may use temporary bootstrap membership before conversion.
- Existing-group rebuild may retain a temporary safety member until genuine requested membership is established.

**0.8 approved change:** treat those temporary safety-member cases as one `bootstrap` continuity concept. A bootstrap is a temporary bot occupant used to establish or preserve required party/raid/instance continuity. It may be newly created or retained from the old group.

A bot bootstrap is used only when continuity requires one. If existing humans already preserve the necessary party/raid topology, an extra bot is not required solely for topology. When a bot bootstrap is required, reuse an existing bot before manufacturing a new one.

Target preset size determines topology:

### 5-man target
- remain a party; bootstrap handling must never convert the group to raid;
- bootstrap stays in the party/G1;
- reserve one required final bot assignment while the bootstrap occupies one party slot;
- fill every other required bot assignment that fits with the actual present humans;
- remove bootstrap;
- observe it absent + wait 3.0 seconds;
- summon the reserved final assignment.

The number of bots summoned before bootstrap removal is dynamic. Do not hard-code the common one-human case as three-before/one-after; with multiple humans fewer bot assignments fit before removal. The stable rule is **one reserved final bot assignment**.

### Raid-sized target
- if an existing raid requires a bot bootstrap, retain one existing bot instead of manufacturing a new bootstrap;
- park it in G8 when possible;
- remove the other old bots and wait for their observed disappearance + 3.0-second capacity-reuse settle before starting the new G1;
- once a genuine new G1 bot exists, remove bootstrap;
- bootstrap disappearance/accounting may settle in parallel with later bursts while those bursts do not need the bootstrap's freed slot;
- gate the first capacity-dependent burst if bootstrap settle is still incomplete.

### Fresh raid start
If no suitable member exists to establish/preserve the raid, create a temporary bootstrap, form/convert the raid, then converge on the same raid-bootstrap lifecycle.

## Removal settle
**0.8 approved change/refinement:** the shared 3.0-second settle protects **capacity reuse**.

Capacity-dependent sequence:
1. request removal;
2. observe removed bot absent from Blizzard roster;
3. wait 3.0 seconds;
4. permit an addition that requires that freed slot/capacity.

Ordinary maintenance replacement, destructive rebuild and 5-man bootstrap final-slot replacement remain strict.

Raid-bootstrap removal may overlap unrelated earlier raid bursts because those additions do not yet reuse the bootstrap's slot. Final capacity fill/final tracking may not cross the unfinished bootstrap settle.

Pure removal with no later capacity reuse does not require an artificial delay.

## Live Roster / tracker / Active Roster
- Blizzard roster is live observation truth.
- Active Roster is sticky maintained bot-slot state independent of whichever preset is selected.
- Humans are not replaceable Active Roster bot slots.
- Tracker/name binding connects logical summon intent to live random bot names.
- Loading-screen continuity reconciliation remains a special boundary; do not casually adopt unrelated later random names into missing slots.

## Identity
0.7.14 uses explicit burst plans but still has a global pending assumed-spawn FIFO and overlapping system-message/roster-delta binding paths. This is a known defect candidate, not desired behaviour.

**0.8 approved change:** explicit burst + SoloCraft join-message order is primary identity. Blizzard roster reinforces/verifies name, class, subgroup and live order but does not independently consume the next pending assignment. Bursts are isolated; stale identities cannot spill into later groups. If evidence disagrees, fail/surface rather than silently offset later identities.

## Roles / combat confirmation
- `assumedRole` is requested role.
- `confirmedRole` is optional combat-derived role.
- Confirmation defaults OFF.
- OFF means high-volume combat listeners are unregistered.
- ON means confirmed bots are skipped and scanning sleeps when all relevant bots are confirmed; new unresolved bots can wake it.
- Threshold remains 2 observations unless separately changed.
- Paladin tank evidence remains strong-only (Righteous Fury/Holy Shield); Shield Slam remains Warrior tank evidence.

**0.8 approved change/clarification:** retain both roles and compute `resolvedRole = confirmedRole or assumedRole`. Maintenance may use resolved role after confirmation. Do not destructively overwrite assumed role.

## pfUI
- pfUI tank marks follow resolved role for exact named SCB-managed bots.
- SCB clears only tank marks it owns; unrelated manual pfUI marks survive.
- Bootstrap/safety identities are not genuine tracked tank assignments.

## Commands/comms/options
- Direct controls remain PARTY-capable while dead; summoning remains SAY.
- ONE/Target requires friendly bot target.
- Ctrl-click Come retains Move-then-Come behaviour.
- Preset comm protocol must not change accidentally while Comms is consolidated.
- Chat filtering behaviour must survive its structural move into Options.

## UX/safety
- Preserve player agency.
- Block impossible/unsupported operations, not unusual choices.
- Do not silently correct user data.
- No hidden TargetByName maintenance probing.
- Saved-instance continuity policy remains conservative when APIs are ambiguous.
- Target topology outranks bootstrap origin: a 5-man target must stay party even if the current transition uses a bootstrap.

## Regression matrix
1. Login/reload no Lua errors; options/presets/session state load.
2. Preset edit/save/reselect Saved/Unsaved works.
3. 5-man solo summon.
4. 10-man dungeon solo first-real conversion.
5. 10-man over existing 5-man with bootstrap/survivor handling.
6. 20/40 T3 solo bootstrap conversion.
7. >5 already-party start.
8. >5 already-raid start.
9. Consecutive bursts preserve name/logical-slot/class/role identity.
10. Repeated identical class/role commands in one burst bind correctly.
11. No G1 pending identity can leak into G2.
12. Combat retry does not duplicate identity intents.
13. `Cannot add bots right now.` abort/retry paths clear or recover state correctly.
14. Capacity-dependent remove -> reuse waits for roster disappearance + 3.0s; unrelated raid-bootstrap-overlap bursts may proceed only while they do not require that freed slot.
15. Replace Missing uses Active Roster, not selected preset.
16. Confirmation OFF leaves scanner dormant.
17. Confirmation ON skips confirmed bots and sleeps when complete.
18. Replacement/new bot wakes scanner when enabled.
19. Shield Slam evidence preserved.
20. pfUI tank icons match exact named resolved roles; manual flags survive.
21. Saved human present snaps to exact logical slot even if Blizzard displays another row.
22. Saved human absent leaves underlying bot active.
23. New human remains in Other Players until assigned.
24. Human at logical key/filler slot suppresses exactly that bot, never whichever physical Blizzard row they occupy.
25. Bot ordinal identity inside a subgroup ignores human rows.
26. Blizzard roster remains authoritative for live name/class/subgroup/location.
27. Location auto-swap preserves dirty editor changes.
28. AQ40 resolves `Ahn'Qiraj`.
29. Direct command matrix/target/Ctrl-Come unaffected.
30. Preset send/request protocol still validates/serializes correctly.
31. Frequent preset reload with recurring saved players restores their logical assignments without manual dragging.
32. 5-man bootstrap rebuild with one human remains a party, fills the non-reserved bot slots, removes bootstrap, waits disappearance + 3.0s, then fills the reserved final bot slot.
33. 5-man bootstrap rebuild with multiple humans derives pre-removal bot count from actual occupancy; no fixed “three then fourth” assumption.
34. Raid rebuild that needs continuity reuses one existing bot bootstrap instead of summoning another, waits old-bot teardown + 3.0s before new G1, then removes bootstrap and overlaps its settle with later non-capacity-dependent bursts.
35. If present humans already preserve required party/raid continuity, no unnecessary bot bootstrap is retained solely for topology.
36. No 5-man target is converted to raid by bootstrap logic.
37. Fresh T3/raid start still manufactures a bootstrap when no suitable existing member can establish the raid.

Any further intentional deviation must be logged in `DECISIONS.md`.
