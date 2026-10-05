# Samoyed Nest status and acceptance

Updated 2026-10-05. The user confirmed initial acceptance with no issues and authorized integrating the plan-recovery fix, legacy cleanup, consolidation onto `main`, and another TestFlight release. This does not claim every manual failure scenario has been exercised.

## Current deployment

- Sole writable origin: https://samoyed.protium.top. The old Sites service remains a read-only archive.
- Instance: `886aa157-8d8b-44da-8b97-05aec0c7825e`; shared host `47.77.197.236`; Compose project `samoyed-nest`.
- Running image verified October 5: `samoyed-nest:plan-recovery-20261003-9f6b9db`, SHA `20731ab272a9b3ee919227f660b5e69c0f6e015b627053a3765af6ad4b945460`.
- Read-only inspection returned running/healthy, zero restarts; public `/readyz` returned ready. These are server checks, not phone acceptance.
- Runtime retains its dedicated SQLite volume, read-only root filesystem, 256 MiB / 0.5 CPU / 128 PIDs and private ingress network. Deployment and backup commands are in [operations](samoyed-nest-operations.md).
- The 2.2.2 source cleanup removes unused shared landing/capability handlers already owned by the Node and archive entry points. The production image above remains the independently verified deployment; a source merge or iOS release does not deploy Nest.

## Source and iOS release

- Runtime redesign and Nest were merged through PRs [4](https://github.com/Cabbyte/Samoyed/pull/4) and [5](https://github.com/Cabbyte/Samoyed/pull/5).
- The prior iOS release `ios-v2.2.1` completed as 2.2.1 (14), with Apple processing `VALID`: [TestFlight run](https://github.com/Cabbyte/Samoyed/actions/runs/37031424218).
- The plan-recovery source `9f6b9db` passed core, SQLite/D1 and unsigned iOS archive CI: [run](https://github.com/Cabbyte/Samoyed/actions/runs/37036915666).
- The current cleanup prepares version 2.2.2. `main` is the long-lived branch; a new immutable `ios-v2.2.2` tag triggers the signed TestFlight workflow after CI passes. Final build number and Apple processing evidence belong to the resulting [TestFlight run](https://github.com/Cabbyte/Samoyed/actions/workflows/testflight.yml).

## Current contract

- Local mode remains available. Connected iOS clients keep account-partitioned SQLite, Keychain credentials, offline outbox, cursors and conflict archives.
- Node/SQLite is the writable deployment. D1 uses the same domain contracts; the archived Sites identity does not become a public account automatically.
- Routine/week-rule changes default to tomorrow in the account timezone. Existing started/executed/corrected subtrees remain valid snapshots; incompatible replacements retain the previous source.
- Timeline Notes are independent, time-stamped content with optional block-instance links. Fixed Routine guidance and local append-only Feedback remain separate concepts.
- Native and MCP OAuth resources are distinct. Installed plugin: https://chatgpt.com/plugins/plugins_6abe5befef9c81919c6b3ec63308a784; installation alone is not authentication proof.

## Evidence and remaining coverage

- [October 1 acceptance](archive/2026-10-01-nest-acceptance.md) records actual phone/HTTP/MCP writes, token renewal, controlled offline transport, lost-response replay, restart recovery, zero pending/conflicting operations, and backup integrity/restore. Its data counts and image belong to that date.
- [October 2 Today/Nest UI QA](qa/2026-10-02-today-nest-ui.md) records navigation and visual fixes. The interrupted simulator suite was not a complete UI pass; the user chose iPhone acceptance.
- [October 3 recovery](qa/2026-10-03-plan-recovery.md) records the invalid merged tree, protected-history recovery, regression coverage, deployed image and retained Today screenshot.
- On October 5 the user reported initial acceptance with no issues. This supersedes the prior lack of user confirmation; it is not a new automated device run.
- Manual airplane-mode transitions, two separate physical devices editing through their UIs, physical revocation behavior and comprehensive accessibility/visual coverage remain separately scoped checks. No simulator run is implied by this cleanup.

## Historical material

The [Sites/native-auth probe](archive/2026-10-01-sites-probe.md) is retained only as historical evidence. Its unfinished native-auth and lifecycle statements are superseded by the later public deployment and acceptance records.
