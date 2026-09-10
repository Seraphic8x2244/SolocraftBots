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

## Next low-risk consolidation steps

- Absorb `Location.lua` into `Presets.lua`.
- Absorb `Comms.lua` into `Presets.lua`.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.
