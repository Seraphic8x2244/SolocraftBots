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

## Presets sizing decision

- Do not force `Location.lua` or `Comms.lua` into `Presets.lua` merely to reduce file count.
- Continue moving non-preset runtime responsibilities out of `Presets.lua`, then reassess the resulting size and cohesion.
- Merge Location and/or Comms into Presets only if the final ownership remains clear and the file stays reasonably sized.

## Next consolidation direction

- Flatten the human/layout/presentation wrapper chain around exact logical human slots.
- Continue moving role/identity/runtime ownership toward the eventual `Raid.lua` owner without changing established behaviour unintentionally.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.
