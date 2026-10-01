# Samoyed Nest deployment and acceptance record

Updated 2026-10-01. Branch `codex/samoyed-nest-v1`. Public deployment is running; complete beta acceptance is still in progress.

## Current deployment

- Sole writable origin: https://samoyed.protium.top, server `47.77.197.236`.
- Instance ID: `886aa157-8d8b-44da-8b97-05aec0c7825e`.
- Compose project `samoyed-nest`, container `samoyed-nest-nest-1`, configuration `/opt/samoyed-nest/compose.yaml`.
- Image `samoyed-nest:beta-20261001-1430`, Linux amd64, image SHA `b13a0fe5d1c90efe70b8735874ba06d7a18ff274d793809c747c2c0ff1faa5f4`.
- Dedicated SQLite volume `samoyed-nest-data`; 256 MiB, 0.5 CPU, 128 PIDs, read-only root filesystem, no published host port. Only ingress network `acornary-edge-v1`.
- Caddy route `/etc/acornary/ingress/sites.d/samoyed.caddy`; shared generator now preserves and validates these snippets. Maintenance PR: https://github.com/Cabbyte/Acornary/pull/5 (merged as `1e936d47cd54665895eb6258b4bb6dbcba6878e4`; CI passed; merge did not deploy other apps).
- All six existing containers retained their IDs, start times, restart counts, OOM status, ports and health before/after the final Nest-only update. The original baseline has null health for containers without a healthcheck; the final collector reports their running state instead. Caddy reload and subsequent Nest-only image update left the existing Caddy process unchanged. RunBuoy and Acornary read-only health checks passed.
- Sites was archived before public writes. Deployment `appgdep_6abe5b3b5ee8819191975cf62228b8b1`, source `45f35a7007563a0a8cd69d56c0ca20e4bd065788`; actual old-plugin write returned `site_archived_read_only`. Its only prior entity was a tombstoned acceptance Note. No Sites identity was automatically linked to a public account.

## Identity and native synchronization

- Better Auth Passkey invite registration, PKCE native OAuth, resource-separated MCP OAuth, Keychain credential rotation, device/agent revocation checks and first-party account management are implemented.
- The user registered a Passkey on the public origin and confirmed iPhone 16 initial synchronization.
- After the human import there were three routines, five weekday rules and 52 legacy day plans. A separate invited acceptance account was later registered through the public browser using a software WebAuthn authenticator. No Note text or credentials were copied into this record.
- A signed Debug app was installed and relaunched on the physical iPhone. Its diagnostic at `2026-10-01T13:33:20Z` confirms App Group SQLite, the public instance/account partition, a saved cursor, three routines, 52 displayed day plans, zero pending operations and zero Note conflicts.
- The production refresh credential rotated at `2026-10-01T13:33:14Z`, after the original 5-minute access credential expired. The old refresh row is revoked and the new row is active. This establishes native access/renewal after browser closure and app restart; physical revocation acceptance remains outstanding.
- Local mode, account partitions, import archive, offline outbox, explicit completion/undo, standalone Notes and Note conflict resolution are connected to the app lifecycle. Pending conflicts now produce a visible incomplete-sync status, and resolving a Note schedules another sync. Generic Routine, selection, correction and execution conflicts now offer explicit local/cloud choice and archive rejected commands. Rebased corrections preserve the dependency order of newly added tasks.

## Plugin

- Public plugin: https://chatgpt.com/plugins/plugins_6abe5befef9c81919c6b3ec63308a784
- Release `pluginrel_6abe5bf0aa988191b6d37d78fd7def8b`; source `nest/plugin/samoyed-nest`, endpoint https://samoyed.protium.top/mcp.
- The plugin includes the Routine orchestration skill. It is private, not a public directory submission.
- On 2026-10-01 the installed public namespace `mcp__samoyed_nest__` successfully returned the expected public instance and the same account as iPhone. The actual plugin read all three imported routines.
- Actual MCP writes changed Workday's first block title with tomorrow's default effective date and created a backdated standalone Note. The user confirmed both appeared on iPhone after sync. An identical Note replay returned the original receipt; today's existing execution and legacy snapshots were unchanged.
- The temporary title was restored via revision 3 and the synthetic plugin Note was tombstoned. The user then saved a Note on iPhone; actual MCP read-back returned it with source `ios`, occurredAt `2026-10-01T14:06:00Z`, and an existing block association. At `14:06:31Z` the physical diagnostic had zero pending operations/conflicts. This proves normal phone-to-Nest-to-plugin flow, not an airplane-mode or independent-Note test. The user requested a simpler test, so further failure scenarios are being automated.


## Backup and recovery

- SQLite online backups include both authentication and business data. Independent systemd timer: daily 05:10 Asia/Shanghai, seven daily and four weekly copies.
- Server backup directory `/var/backups/samoyed-nest`; private development-machine copies under `~/Library/Application Support/Samoyed Nest/backups/`.
- Release backup `release-20261001-222339.sqlite` includes both accounts, the real imported data and phone-created Note (65 entities). Integrity check and a separate restore succeeded; entity and identity counts matched.
- Never copy a running SQLite main file as a substitute for online backup, or restore an old snapshot over newer user writes. Roll back compatible Nest images first. Do not reopen Sites writes.

## Verification and remaining acceptance

- Node SQLite: 23 tests passed; TypeScript typecheck passed. Constrained Docker: 23 tests passed under production limits (256 MiB, 0.5 CPU, 128 PIDs). D1: 20 common tests passed, three Node-specific auth tests skipped.
- Swift core: 123 tests passed. Signed iOS Debug build and physical installation passed. The new suite covers cached version history and missing-date materialization, complete/undo retained across reopen and newer cloud plans, and correction conflict recovery with dependent tasks.
- Public independent test account: foreign routine/cursor rejection, identical operation IDs isolated across users, replay after a lost response, concurrent Note conflict, tombstone protection, refresh rotation, independently revoked Agent and device tokens all passed through real HTTP/OAuth. Test grants were revoked afterward; the later physical-device test grants were also revoked and private test credential files removed. Software WebAuthn and two HTTP clients are not two physical iPhones.
- Connected clients now cache scheduling history at an owner-scoped cursor. Missing dates materialize using the version effective on that date. On reconnect, `offlinePlan` validates its claimed source against that historical cursor, remains immutable, and retains execution provenance even if the cloud changed meanwhile. The original opaque cursor stays available for later offline uploads.
- Timeline pagination now uses a fixed server watermark and includes every complete/undo event. Day corrections support task definitions as well as title/time/guidance.
- Physical iPhone controlled-failure acceptance passed at `14:29:41Z`, `14:29:57Z`, and `14:30:20Z`: cached missing-date planning, complete/undo plus backdated standalone Note while transport is disconnected, successful upload with its response intentionally dropped, process termination/restart, and exact replay/pull. The recovered queue and conflicts were both zero. An authorized MCP client read the Note (revision 1) and both execution events (final execution revision 2, incomplete). This used an isolated test account/database and never touched the human Keychain or partition. It simulates transport loss rather than toggling physical radios.
- The final image is deployed and the app returned to the human account. Its `14:33:28Z` diagnostic again has the original account partition, three routines, 52 plans, two Note rows including the earlier tombstone, zero pending operations and zero Note conflicts. Still unverified: manually toggled airplane-mode behavior and two separate physical devices editing through the UI. After the user explicitly requested removal, Plugin Management returned `not_installed` for the exact old Sites plugin ID (`plugin_asdk_app_sites_48dd33f3b1d481919e399caf0e3ae621`). It is already absent from the client; no uninstall was needed. The public plugin still returned the expected live instance and account afterward. Do not label these manual scenarios passed.

The earlier Sites probe and its evidence limits are preserved in `samoyed-nest-sites-probe.md`.
