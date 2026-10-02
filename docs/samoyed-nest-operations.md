# Public Nest operations

Origin: `https://samoyed.protium.top`. Host: `root@47.77.197.236`.
This host is shared. Only operate the `samoyed-nest` Compose project unless a separate request authorizes another application.

## Configuration

- Compose: `/opt/samoyed-nest/compose.yaml`
- Version: `/etc/samoyed-nest/image.env`
- Private configuration: `/etc/samoyed-nest/nest.env` (mode 0600; never print or commit)
- Database volume: `samoyed-nest-data`, `/data/nest.sqlite` in the Nest container
- Backups: `/var/backups/samoyed-nest`; private development copies in `~/Library/Application Support/Samoyed Nest/backups`
- Ingress snippet: `/etc/acornary/ingress/sites.d/samoyed.caddy`
- Shared ingress generator: `/usr/local/sbin/acornary-ingress`; maintenance source is Acornary `deploy/ingress.sh`

Keep the instance ID, auth secret, origin and database together across image upgrades. Do not regenerate the instance ID for a routine release. No credentials belong in the plugin ZIP or iOS app.

## Release

1. Run Node SQLite/D1 contracts and native checks. Build a fixed Linux amd64 image locally or in CI; never build dependencies on this small host.
2. Capture IDs, start times, health, restarts, OOM state and ports of the existing six containers without collecting environment values.
3. Run `/usr/local/sbin/backup-samoyed-nest release`; copy the new consistent SQLite backup to the private development backup folder. Keep credentials private.
4. Transfer the image archive, `docker load` it, save the previous `image.env`, then update only its `NEST_IMAGE` value.
5. Run:
   ```sh
   docker compose --project-name samoyed-nest --env-file /etc/samoyed-nest/image.env -f /opt/samoyed-nest/compose.yaml up -d --no-deps nest
   ```
6. Verify readiness, unauthenticated API rejection, authenticated native and MCP access, and the unchanged existing-service baseline.

Do not run a broad `docker compose down`, prune shared resources, restart Caddy, or modify other application networks. Nest must retain 256 MiB / 0.5 CPU / 128 PIDs, its own persistent volume, no host port, and only the ingress network.

## Ingress changes

Use `/run/lock/runbuoy-deploy.lock`, preserve the previous configuration, validate the complete candidate, and reload Caddy. The shared helper supports `ACORNARY_INGRESS_LOCK_HELD=1` when the caller already holds the lock. Preserve `sites.d` in the candidate and the wildcard import in the root. Validate a regenerated root after any publisher change.

The patch in https://github.com/Cabbyte/Acornary/pull/5 was merged as `1e936d47cd54665895eb6258b4bb6dbcba6878e4` after CI passed. This source-only merge did not trigger an Acornary deployment.

## Backup and restore

`samoyed-nest-backup.timer` runs daily at 05:10 Asia/Shanghai. The helper uses SQLite's online backup API, retains seven daily copies and four Sunday copies, and stores extra pre-release copies separately.

Verify backups in a separate database/container with `PRAGMA integrity_check` and expected identity/entity counts. A raw copy of the active main database file is not a backup. Never restore an older snapshot over live writes as an automatic rollback. Prefer the previous schema-compatible image, preserving the database and new records.

For a structurally invalid materialized plan, `node dist-node/src/admin.js repair-plan <plan-id> <expected-revision> <source-revision> <operation-id>` previews recovery from that plan's immutable history. Rehearse on a backup first. Add `--apply` only for the reviewed recovery, retaining the exact operation ID on retries. This appends a new plan revision and sync change; it does not replace the database or edit Note/execution records. Recovery refuses a valid current plan, stale revisions, changed corrections, loss of started/executed/Note-linked blocks, or any concurrent user write. No recovery endpoint is exposed through MCP or HTTP.

Materialization retains complete root subtrees containing started, executed, or corrected blocks. If merging a selected routine would invalidate those subtrees or shorten their stored ranges, the previous valid snapshot and its source metadata remain in use. The requested date/weekday rule is not rewritten. An unexecuted future plan remains replaceable.

## Access

An administrator can generate a one-time invite with `node dist-node/src/admin.js invite <display-name>` through the Nest container. Deliver its output only to the intended recipient; do not include it in logs, issues or repository files. The browser handles Passkeys and consent. iOS uses public-client PKCE; MCP clients use their own OAuth authorization. Device and Agent grants are individually revoked through the account page.

Installed plugin: https://chatgpt.com/plugins/plugins_6abe5befef9c81919c6b3ec63308a784 . Installation and OAuth connection are separate. A successful connection must be proved by `nest_connection_status` returning the public instance ID and expected account. An archived Sites tool with the same display name is not public Nest acceptance.

## Sites archive

The old Site remains read-only and does not forward traffic. Its original test data and source evidence are archived separately. Do not turn Sites writes back on during rollback; public Nest is the only main database.
