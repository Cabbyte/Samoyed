# Samoyed Nest

Samoyed's shared service for versioned Routine planning, offline execution and timeline Notes.
The sole writable deployment is https://samoyed.protium.top. The old Site is a read-only archive.
See [acceptance evidence and remaining checks](../docs/samoyed-nest-status.md) and the
[public deployment runbook](../docs/samoyed-nest-operations.md).

## Architecture

`src/domain.ts` is shared by Hono HTTP routes and the official MCP SDK.
`storage/repository.ts` owns user-scoped revisions, receipts, change logs and opaque cursors.
Node uses SQLite on a dedicated persistent volume. The D1 adapter runs the same domain contracts;
Node-only Passkey/OAuth authentication uses Better Auth and its own migrations in the same SQLite database.
Native OAuth and MCP tokens have separate resources. User ownership is derived from authorization,
never a client-supplied ID or Sites header in the Node deployment.

## Development

Node 24 or newer:

```sh
npm ci
npm run typecheck
npm test
npm run test:d1
npm run build
npm run validate
```

`npm run dev` starts the Node entry. Self-host authentication needs the configured origin, instance ID,
auth secret, native client ID and database path. See the operations runbook; never commit credentials.
The Compose service has no host port and joins only the shared ingress network. Build Linux amd64
images locally/CI and transfer fixed tags; do not build dependencies on the small production host.

The Workers artifact is retained for portability and archive maintenance. Do not redeploy it as another
writable database. Canonical archived Site ID: `appgprj_6abe20b9f0688191ad0710e82fbcfff6`.

## Protocol

- `GET /v1/capabilities`: instance, protocol and native OAuth configuration.
- `GET /v1/identity`: current internal Nest user and timezone setup state.
- `POST /v1/account/time-zone`: explicit confirmation and expected previous timezone.
- `GET /v1/sync/bootstrap`: coherent entity snapshot and opaque owner-scoped cursor.
- `POST /v1/sync/push`: stable operation ID, object ID, expected revision and explicit desired state.
- `GET /v1/sync/pull`: cursor-based bounded pages including tombstones.
- `GET /v1/schedule-cache`: scheduling version history, account timezone and a source cursor for offline days.
- `POST /v1/plans/resolve`: materialize a date from the effective routine and rules.
- `GET /v1/timeline`: happened-time range, stable snapshot cursor and page offset.
- `/api/auth/*`: Passkey and OAuth; `/v1/device-sessions` and `/v1/agent-grants`: owned session revocation.
- `/mcp`: stateless Streamable HTTP with per-request authenticated ownership.

Operation IDs can collide across owners without disclosing another user's receipt. Exact replay returns
the original result; reused IDs with changed input fail. Revision conflicts preserve server and local
versions. Tombstones cannot resurrect. Notes are independent objects, never task-state toggles.

Routine and weekday-rule changes default to tomorrow in the account timezone. `offlinePlan` is an
immutable iOS snapshot verified against a previously issued scheduling cursor; executions retain that
source when newer cloud schedules exist. `legacyPlan` is reserved for explicit import of older data with
unknown provenance. Neither kind is an agent shortcut for creating new appointments.

Swift and TypeScript test `contracts/time-cases.json` for normal time, DST gaps/folds, half-hour gaps and
midnight. SQLite and D1 share domain tests for versions, effective dates, task states, corrections,
pagination, user isolation, idempotency and deletion. Logs contain request/operation/revision identifiers,
never credentials or Note text.

The private public-origin plugin is authored in `plugin/samoyed-nest`. Directory submission and App Store
release are outside this beta. Keep physical-device evidence separate from automated transport tests.
