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
- `DetectionLifecycle.lua` remains temporarily separate because it currently loads after `Options.lua` and owns the optional scanner/event sleeping wrappers. It should be consolidated deliberately rather than by introducing a new load-order dependency.

## Presets sizing decision

- Do not force `Location.lua` or `Comms.lua` into `Presets.lua` merely to reduce file count.
- Continue moving non-preset runtime responsibilities out of `Presets.lua`, then reassess the resulting size and cohesion.
- Merge Location and/or Comms into Presets only if the final ownership remains clear and the file stays reasonably sized.

## Next consolidation direction

- Continue collapsing role-detection/lifecycle layering without changing the OFF-by-default performance behaviour.
- Then flatten the human/layout/presentation wrapper chain around exact logical human slots.
- Keep all historical audit notes; do not rewrite old observations as though the target architecture had always existed.
