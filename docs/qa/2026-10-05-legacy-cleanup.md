# Legacy cleanup and 2.2.2 release preparation

The user confirmed initial acceptance of the existing app and authorized source/document cleanup, integration of plan recovery, retaining only `main`, and TestFlight publication.

## Changes

- Remove unused WeekdayPicker/WeekdayButton, unconfigured notification coordinator, unregistered Control Widgets/intents and Home Screen Quick Action generation/handlers.
- Remove the activation notification toggle and permission request because the current app does not schedule notifications.
- Keep the one-time legacy surface migration under an accurate name and preserve its persisted key. Existing JSON/SQLite migration, wire fields, route source values, account data and six supported App Shortcuts remain compatible.
- Rename the Routine/Usual Week view file to match its type; remove unused Store selection/override helpers.
- Remove redundant shared HTTP landing/capability stubs; keep the self-hosted OAuth endpoint and read-only Sites archive entry points authoritative.
- Replace conflicting product/UI prose, remove the superseded widget proposal, and separate dated Sites/Nest evidence from current status. Preserve domain algorithms and tested historical compatibility.
- Set App/Widget marketing version to 2.2.2; TestFlight supplies the actual build number.

## Local validation

- Swift core: 149 tests passed.
- Nest typecheck passed; SQLite 32 tests passed; D1 29 passed and three Node-only auth tests skipped.
- Workers artifact build and ESM validation passed.
- Xcode 27 generic iOS Release build succeeded for App and Widget with signing disabled; no simulator was launched.
- Existing migration, routing, persistence, time resolution, offline replay and plan-recovery tests remain intact.

## Release evidence boundary

CI must pass for the final source commit before pushing `ios-v2.2.2`. The tag invokes `.github/workflows/testflight.yml`, including exported-IPA signature/identity/version/profile/entitlement checks and Apple processing wait. Actual release success is recorded by that run, not inferred from these local checks. The Nest production deployment remains the separately verified recovery image.
