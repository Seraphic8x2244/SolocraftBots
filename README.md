# SoloCraft Bots — 0.1.0-test14

Clean-sheet WoW 1.12.1 SoloCraft PartyBot controller.

## Open

- `/scb`
- `/solocraftbots`
- Key Bindings → SoloCraft Bots → Toggle SoloCraft Bots

## Summon

Eight faction-valid classes are shown in the compact 4×2 grid. Paladin is Alliance-only and Shaman Horde-only. Role/spec buttons remain max two wide under each class.

The Summon heading contains two direct spawn-distance controls:

- binoculars: `.partybot distance on` (Spawn Far)
- magnifying glass: `.partybot distance off` (Spawn Near)

Spawn Near is the default for a fresh bot session. The last distance command issued by SCB is remembered through `/reload` when an SCB-known bot is still present. A relog removes those bots, so the remembered transient state returns to Near. The selected indicator now follows the round artwork instead of drawing a square highlight box.

Paladin blessing and Shaman totem controls remain intentionally out of this build. Level-60 testing has shown Paladin blessing assignment works there and can be revisited later.

## Commands

The direct command area is intentionally scoped instead of repeating every command for every recipient.

Rows:

- All: Heel / Force Heel / Move / Stay / Pause / Unpause
- Target: Heel / Force Heel / Move / Stay / Pause / Unpause
- slight visual gap
- Tanks: Heel / Force Heel / Move / Stay / Pull
- Healers: Heel / Force Heel / Move / Stay
- Melee: Heel / Force Heel / Move / Stay
- Ranged: Heel / Force Heel / Move / Stay / Spread / Hug
- Object / AoE sit separately below because their scope is fixed

Force Heel is an SCB convenience action that sends Move and then Heel for the chosen recipient. Normal commands are sent immediately; there is no general command queue.

## Raidmarks

Focus and CC are back to a mode toggle in the Raidmarks subheading:

- Eye = Focus
- Padlock = CC
- Focus is the default

A single centred row of the eight raidmark buttons uses the selected mode. The selection highlight follows the circular icon artwork.

## Presets

The `Presets >` side tab opens a compact 5-player group preset editor:

`[+] [-] [S] [Preset selector]`

- `+` creates a new named preset by cloning the currently displayed composition.
- `-` removes the current preset immediately.
- `S` explicitly saves the displayed composition.
- Left-click the preset selector to choose a preset; right-click it to rename the current preset.
- Unsaved composition changes make the Save button pulse gently gold.

Slots are:

- 1: Player
- 2–5: Class icon + Role/Spec icon

Left-click a class/role icon to cycle forward; right-click to cycle backward. The underlying preset data remains an ordered slot list so a later 10-player dungeon mode can extend the same design.

### test14 preset fixes

- The name entered when creating/renaming a preset is now read from the actual Vanilla StaticPopup edit box rather than falling back to the generated default name.
- Preset slots are normalised to exactly four bot slots on load/save/summon, independent of preset index or deletion history.
- The dedicated preset batch sender now has explicit running/reset state so subsequent selected presets can start new batches reliably.

Preset Summon sends the four spawn requests as a dedicated batch, spaced slightly apart for reliable server handling. This batch sender is only used for preset spawning; normal commands and single-bot summons remain immediate.

## FillRaidBots

If neither `PCPFrame` nor `PCPFrameRemake` already exists, SoloCraft Bots exposes its main frame as `PCPFrameRemake` so FillRaidBots can continue attaching its external controls.

## Artwork

Bundled TGA assets live directly in `SoloCraftBots/artwork/`.
