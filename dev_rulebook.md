# Vanilla Addon Development Rulebook

This document is the canonical development workflow for Vanilla WoW 1.12.1 addon projects based on this template.

It supersedes `DEV_GUIDE.md` once adopted.

Project-specific development state, architecture decisions, invariants, protocols, test plans, deferred scope and feature decisions belong in `DEV_PROGRESS.md`. If a project intentionally needs an exception to this rulebook, record the exception there explicitly.

Permanent product or user documentation may exist where useful, but it is not a competing development source of truth.

---

## 1. Authority and sources of truth

Use these sources for different kinds of truth:

- `dev_rulebook.md` — canonical development workflow and engineering rules.
- `DEV_PROGRESS.md` — current project state, live development contract and fresh-chat recovery source.
- Git history and current code — historical implementation record and implemented reality.
- The addon `.toc` — version source of truth.

Do not maintain multiple competing live handoff documents.

Legacy `HANDOFF.md` files are predecessors to the `DEV_PROGRESS.md` workflow. Once their still-relevant information has been migrated into `DEV_PROGRESS.md`, delete them rather than keeping a second mutable project-status document.

Git history carries history. `DEV_PROGRESS.md` carries current state.

---

## 2. Default structure

Default layout:

```text
AddonName/
    AddonName.toc
    AddonName.lua
    locales/
        enUS.lua
        [optional translations]
    artwork/
        [flat assets]
    dev_rulebook.md
    DEV_PROGRESS.md
    Debug.lua       # dev only, when needed
```

Defaults:

- Prefer one main Lua file unless the existing project architecture or an explicitly agreed design calls for more.
- `Debug.lua` is the normal development-only exception for small addons.
- Preserve an established multi-file architecture in existing addons; do not collapse it to fit this template.
- Put user-facing strings in the project's localization system. For new template addons, use `locales/enUS.lua`.
- Put translations in the corresponding locale file.
- Put artwork under `artwork/`, flattened unless there is a concrete reason not to.
- Avoid bundled libraries, frameworks or dependencies unless they solve a concrete requirement.

---

## 3. Target environment

Default target:

- World of Warcraft 1.12.1.
- `## Interface: 11200`.
- Lua 5.0.
- Native WoW 1.12.1 API unless an explicitly supported client extension supplies additional capability.

Do not use later Lua syntax or later WoW APIs by assumption.

### Lua 5.0 implementation limits

Vanilla Lua limits are part of the target environment, not an afterthought.

In particular:

- Lua 5.0 has a parser/compiler limit of 200 local variables in a function.
- The top-level addon chunk is compiled as a function, so large single-file addons can hit this limit through top-level locals.
- Watch local counts when a file grows substantially.
- Do not solve a local-limit failure by blindly globalizing internal state. Prefer a deliberate structural fix consistent with the addon architecture.

Static compatibility checks should look for accidentally introduced modern APIs/syntax where practical, but static inspection is not an in-game test.

---

## 4. Optional client extensions

Nampower, SuperWoW, ClassicAPI and other explicitly selected client extensions may be supported.

Rules:

- Treat extensions as optional capability enhancements unless the project explicitly requires one.
- Prefer the native 1.12.1 path when it provides a good solution.
- Use an extension when it materially improves correctness, capability or implementation quality.
- Preserve a native/non-DLL path where reasonably possible.
- Do not make existing native functionality DLL-dependent without an explicit reason.
- If a feature cannot reasonably preserve a native fallback, flag that dependency before treating it as required.
- When an extension is an explicit project prerequisite, use its real capabilities directly rather than duplicating weaker fallback implementations without a reason.

---

## 5. Versioning

The addon `.toc` is the single source of truth for version.

Example:

```lua
local ADDON_NAME = "AddonName"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")
```

Rules:

- The addon `.toc` `## Version` field is the single source of truth for the addon version.
- Runtime Lua must never contain a separately hardcoded addon version string. Whenever the addon needs to display, report, compare, or transmit its own version, read it from TOC metadata with `GetAddOnMetadata("<AddonFolderName>", "Version")` using the real addon/folder name.
- Every new addon build must increment the numeric TOC version. For ordinary development revisions, increment the patch component, for example `0.5.1-dev` -> `0.5.2-dev` -> `0.5.3-dev`.
- A build means a new testable/runtime state of the addon. Multiple implementation commits may contribute to one build, but before that state is handed off for testing or use, its TOC version must be higher than the previous build.
- A deliberate major/minor release-line change may bump that component instead of the patch component.
- Documentation-only/status-only commits do not create a new addon build and therefore do not require a version bump.
- Development builds keep the `-dev` suffix.
- Do not invent suffix counters such as `-dev1` or `-dev2`; increment the numeric version instead.

Development:

```toc
## Title: AddonName-dev
## Version: 0.1.0-dev
```

Stable:

```toc
## Title: AddonName
## Version: 0.1.0
```

A user-tested result belongs to the exact version/commit that was tested. A later version may inherit that known-good baseline, but its new delta remains untested until exercised.

---

## 6. Branch model

### `dev`

For new template addons, active development happens on `dev`.

The development branch:

- uses development Title/Version metadata;
- contains `dev_rulebook.md` and `DEV_PROGRESS.md`;
- may contain dev-only debug/test helpers;
- may contain clearly documented incomplete or experimental work.

Existing repositories may use a dedicated feature/design branch instead of `dev` when that is already their established workflow. The same rules apply to whichever branch owns the current development work.

### `main`

`main` contains stable releases or the project's intentionally stable baseline.

For template addons, stable releases must:

- use stable Title/Version metadata;
- exclude `DEV_PROGRESS.md`;
- exclude dev-only debug/test helpers;
- exclude development-only loader entries;
- exclude knowingly speculative work unless the user explicitly authorizes that release with the remaining validation debt documented.

Do not assume that `main` is byte-for-byte derivable from `dev`. Main may contain legitimate release-only or presentation-only files. Release preparation must inspect and preserve intended main-only content.

---

## 7. Starting or resuming development

Before substantial code changes:

1. Read `dev_rulebook.md`.
2. Read `DEV_PROGRESS.md`.
3. Resolve the documented branch and exact handoff/head commit.
4. Verify that the actual remote branch head still matches the documented handoff before editing.
5. Identify the latest stable runtime/release baseline separately from the current development head.
6. Confirm the requested work does not silently cross a documented deferred boundary or contradict the current development contract.

If the remote branch moved since the handoff:

- do not force-update it;
- inspect the new commits;
- reconcile the current state before continuing;
- update the status document if the old handoff is stale.

A casual interpretation of a chat request must not silently override the written contract. If the new request intentionally changes the contract, make that change explicit.

---

## 8. Scope and architecture

General rules:

- Preserve existing architecture unless deliberately changing it.
- Do not silently broaden scope.
- Do not perform unrelated refactors during a targeted fix.
- Structural changes require an explicit reason and agreement appropriate to the project.
- Do not add systems, abstractions, modules or dependencies without a concrete need.
- Fix underlying causes rather than layering accidental bandages over them.
- Temporary workarounds require explicit agreement and must remain identified as temporary.

### Architectural ownership

When a domain already has an authoritative request path, coordinator, state owner or lifecycle front door:

- new entry points should route through that owner;
- do not bypass it by calling a lower-level implementation directly unless the bypass is intentional and documented;
- do not create a parallel scheduler/state machine for work already owned elsewhere;
- preserve clear ownership of identity, state mutation and lifecycle transitions.

Before adding a new execution path, check whether the project already has a proven owner for the same kind of operation.

---

## 9. User agency and tool design

Design for capable users, not hypothetical misuse.

A tool should restrict the user only where unrestricted behaviour would make the tool incorrect, corrupt state, violate a required invariant, or exceed a genuine external constraint. It should not restrict behaviour merely because a value is unusual, a workflow is uncommon, or the developer believes the user probably should not do it.

Prefer capability over paternalism.

- Distinguish **invalid** from merely **unwise, unusual or inconvenient**.
- If an operation is valid, allow it even when the result may be extreme, inefficient, visually awkward or easy to misuse.
- Do not silently replace user intent with developer judgement.
- Prefer clear feedback, warnings and documentation over prevention.
- Do not add arbitrary caps, clamps, cooldowns, retry limits, disabled states or forced workflows for convenience or presumed safety.
- Every imposed constraint should have a concrete technical justification.
- Scope necessary constraints as narrowly as possible to the invariant or external limitation that requires them.
- Preserve advanced and unexpected uses when the underlying system can support them correctly.
- Treat robustness as a way to support a wider range of valid behaviour, not as a reason to narrow what the user is allowed to do.
- Keep behaviour predictable: accept the user's choice faithfully, expose its consequences clearly, and avoid hidden normalization or correction.

When an unusual input exposes weakness in the implementation, first ask whether the implementation can be made robust enough to support it. Do not default to forbidding the input.

**Enforce correctness, not preference. Trust the user with every capability the system can reliably provide.**

### Genuine constraints and invalid operations

Some limits are part of making the tool correct rather than restricting user choice.

A constraint is appropriate when it is required to:

- preserve data or state integrity;
- satisfy a real API, protocol, server or client limit;
- prevent an operation whose required preconditions are not met;
- preserve an architectural invariant necessary for correct execution;
- prevent one operation from corrupting or invalidating another operation already in progress.

When such a constraint is necessary:

- enforce the narrowest constraint that solves the real problem;
- make the reason visible when useful;
- do not extend it to adjacent valid behaviour for convenience;
- prefer removing the constraint later if the underlying technical limitation can be eliminated.

Timing, throttling, locking, cooldowns and retry behaviour are real product behaviour, not harmless implementation details. Do not introduce or tune them by guesswork. Use concrete protocol requirements, integrity requirements, or focused runtime evidence to establish the minimum constraint actually needed.

---

## 10. Testing states and provenance

Keep these states distinct:

**implemented -> checked -> user tested -> stable -> released**

Definitions:

- **Implemented** — code exists.
- **Checked** — static review, diff inspection, syntax/build checks, automated tests or CI passed as applicable.
- **User tested** — the relevant runtime behaviour was actually exercised by the user in the target environment.
- **Stable** — the behaviour/build has been accepted as a known-good baseline.
- **Released** — the stable build has been promoted/published through the project's release mechanism.

Rules:

- Implemented does not mean tested.
- Static/code inspection does not count as an in-game test.
- CI does not count as user runtime validation.
- A successful adjacent test does not prove an untested path.
- Record partial tests accurately.
- Bind runtime results to the exact tested version/commit.
- When later work builds on a tested baseline, state explicitly what remains inherited/known-good and what new delta is still untested.
- Never rewrite validation history by describing released-but-untested behaviour as though release itself tested it.

When a user explicitly authorizes promotion despite known untested work, record that validation debt clearly before release.

---

## 11. `DEV_PROGRESS.md`

`DEV_PROGRESS.md` is the sole live project-development document.

It carries the current state **and** the project-specific development context needed to make the next correct decision: active architecture, invariants, protocols, feature decisions, testing state, deferred boundaries and exact next step.

It is not the whole project history. Keep it concise enough that a fresh chat can resume immediately.

At minimum track:

- current branch;
- current dev version;
- exact current/handoff branch-head commit;
- latest stable release/runtime version and exact commit;
- current goal/scope;
- active architecture/design decisions and invariants that still constrain future work;
- current protocol/data-model decisions where relevant;
- recent relevant commits;
- completed and user-verified work;
- implemented but untested work;
- static/automated checks already performed;
- current issues;
- last runtime test and exact tested version/commit;
- next runtime test;
- planned/to-do work;
- deferred/out-of-scope work;
- exact next step.

Where relevant, also record:

- known release-only/main-only files that must be preserved;
- explicit design invariants;
- known validation debt accepted for a release;
- external/runtime prerequisites.

Do not turn `DEV_PROGRESS.md` into a chronological diary.

Remove or compress superseded implementation narratives once they no longer affect the current state, next test, architecture or recovery path.

---

## 12. Long-chat and handoff discipline

Development chats can become tool-heavy and state-heavy. Do not push them until context becomes unreliable.

Before context loss becomes likely:

1. finish or stop at a coherent checkpoint;
2. update `DEV_PROGRESS.md`;
3. record the current branch/version/head;
4. distinguish user-tested, statically checked and untested work;
5. record deferred work and the exact next step;
6. commit the handoff/status update;
7. provide a short copy-paste resume prompt for a fresh chat.

The resume prompt should name:

- repository;
- `DEV_PROGRESS.md` as the recovery source;
- branch;
- exact handoff commit;
- exact next step;
- any critical "do not start yet" boundary.

A new chat should verify that handoff against the actual branch head before doing new work.

---

## 13. Commit and promotion discipline

Prefer coherent commits that identify meaningful development states.

Before writing to an active shared development branch:

- verify the branch head is still the one you inspected;
- do not force-push over concurrent work;
- if the branch moved, reconcile first.

Before release/promotion:

1. identify the exact tested/accepted development commit;
2. identify the current `main` head separately;
3. compare development and main rather than assuming one can blindly replace the other;
4. preserve legitimate main-only/release-only content;
5. remove dev-only files and debug hooks;
6. apply stable Title/Version metadata;
7. verify the release tree contains the intended runtime delta and no unintended development material;
8. run all available static/build/automated checks;
9. record any runtime validation debt honestly;
10. promote through the project's established release mechanism.

After promotion:

- record the stable version and exact stable commit;
- distinguish the promotion/release commit from the previously tested development commit if they differ;
- do not claim the stable tree received a runtime test unless that exact stable build was actually exercised, though a metadata/dev-file-only promotion may inherit the explicitly documented runtime behaviour of its tested source.

For projects with CI/release workflows, a temporary build artifact is not automatically a product release. Use the project's real publishing path when the released product depends on tags, checksums, GitHub Releases, updater discovery or similar release metadata.

---

## 14. Development contract changes

This rulebook is a workflow contract.

Do not casually edit it during ordinary feature work.

Change it when the development standard itself is intentionally being revised.

Project-specific exceptions belong in `DEV_PROGRESS.md` unless they are meant to become the general standard for future addons.
