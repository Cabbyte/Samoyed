# Samoyed Maintenance Guide

## Product Authority
- Read `PRD.md` before accepting feature work. It owns the target user, product behavior, supported capabilities, and validation criteria.
- `README.md` owns domain models and algorithms; `Design.md` owns UI expression.
- Approved Figma `KMmryraXYpe4O2BTgadVjJ`, `PRD.md`, and `SystemSurfaces.md` define the shipping product scope; archive-era mobile-authoring screens do not.
- Existing code is a technical asset, not evidence that a capability belongs in the active product scope.

## Read Order
- `PRD.md`: product goal, current scope, and requirement admission rules
- `README.md`: domain semantics and invariants
- `Design.md`: current experience and UI acceptance flow
- `Samoyed/CoreShared`: pure rules and shared models
- `Samoyed/SamoyedStore.swift`: app state, screen queries, user commands
- `Samoyed/SamoyedApp.swift`: app launch, root UI, quick actions, external routing
- `SamoyedWidgetExtension`: widget rendering and widget-only entry points

## Product Change Gate
- Prioritize automatic running, valid day snapshots, `Now`, read-only `Today`, Timeline Notes, Nest/local persistence, and explicit Suggestion approval. Keep Feedback separate from synchronized Notes.
- Do not expand frozen capabilities merely because their implementation already exists.
- Before accepting a feature, identify the user problem, journey stage, measurable outcome, smallest experiment, and explicit non-goal.
- If a change does not improve the current acceptance flow or a PRD metric, keep it out of the active scope.
- Sample data must never replace production onboarding or a failed load. Explicitly authorized Mock fixtures may exist in a user account; preserve and clearly label them.

## Where Changes Go
- Change planning rules, validation, template logic, or time resolution in `Engine` files.
- Change what a screen needs to render in `ScreenModels` and the presentation helpers.
- Change user-triggered app behavior in `SamoyedStore`.
- Change deep links, quick actions, widget buttons, notifications, or live activity wiring in the app/widget entry files.

## When To Add A File
- Add a new file only when one file is carrying two separate responsibilities.
- Do not create a new file for a tiny helper that is only used by one feature screen or one entry point.
- Prefer adding a `MARK` section and a private helper before splitting a file.

## When To Avoid Abstraction
- Add protocols only at real external seams such as `PlannerClient`; keep local services concrete.
- Prefer a concrete type with explicit parameters over a hidden dependency layer.
- Prefer one obvious write path over multiple convenience entry points.

## Safe Refactor Checklist
- Confirm the change is inside the current PRD scope or is a required regression fix.
- Keep `DayPlanEngine` and `TemplateEngine` pure.
- Keep repository code limited to loading, saving, and atomic document mutation.
- Keep route parsing outside `SamoyedStore`.
- Verify the empty-document path when changing startup, templates, or materialization.
- Verify legacy decode defaults whenever adding a `SamoyedDocument` or Routine-version field.
- Verify suggestion import/apply is transactional, idempotent, and never auto-applies.
- Keep production Planner disconnected unless a real configured client reports otherwise.
- Run `swift test` after core changes.
- Run an Xcode build after app or widget entry changes.

## TestFlight Release Gate

- Keep the existing Apple deployment identity in `Config/AppleIdentity.xcconfig`; do not duplicate those values in workflows or source files.
- Configure the `testflight` GitHub Environment variables `SAMOYED_APP_PROVISIONING_PROFILE_NAME` and `SAMOYED_WIDGET_PROVISIONING_PROFILE_NAME` with the exact active App Store profile names. Multiple active profiles may coexist; the workflow selects only the configured names.
- Keep App Store Connect credentials and the Apple Distribution certificate in the `testflight` Environment secrets referenced by `.github/workflows/testflight.yml`.
- The release workflow must verify the exported IPA—not only the archive—including signatures, Bundle IDs, versions, App Group entitlements, embedded profile names and entitlements, privacy manifests, URL scheme, and generated App Icon files before upload.

## Compatibility and Source Cleanup

- Remove unused UI/entry-point implementations only after checking App, extensions, fixtures and tests for references.
- Retain legacy JSON-to-SQLite import, wire field names, old route source spellings and persisted migration keys. Never replace the Apple identity or account partitions during cleanup.
- Keep the old Sites entry read-only and its dated investigation under `docs/archive/`; production authentication and capabilities belong to `self-hosted.ts`.
- Use `RoutinesRootView.swift` for the Routine/Usual Week screens. Internal Template model names remain serialization-compatible.

## Main and Release Hygiene

- `main` is the long-lived branch. Integrate validated changes, then delete only branches whose commits are reachable from `main`.
- Detach or archive old worktrees before deleting their checked-out branches; preserve local files and QA artifacts. Do not force-delete unknown work.
- Test core rules with `swift test`; run Nest typecheck, SQLite/D1 tests and build validation; build App/Widget changes for generic iOS without launching a simulator when device acceptance is the chosen path.
- Require the CI core, Nest and unsigned iOS archive jobs to pass on the release commit.
- Create a new immutable `ios-vX.Y.Z` tag on that commit. Its push triggers `testflight.yml`; do not also dispatch a duplicate release workflow.
- Record the actual workflow/build number and Apple processing `VALID`. A successful source merge or queued workflow alone is not a TestFlight release.
