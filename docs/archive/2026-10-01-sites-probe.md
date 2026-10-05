# Historical Sites/native-auth probe — 2026-10-01

Historical snapshot from `codex/samoyed-nest-v1`, before the public Nest migration. The unfinished items below describe that probe date, not current blockers. Superseded by [current Nest status](../samoyed-nest-status.md) and [operations](../samoyed-nest-operations.md).

## Implemented

- TypeScript/Hono service with official MCP SDK, Workers entry, fail-closed Node entry,
  D1/SQLite repository adapters and shared Drizzle migrations.
- Nest User/Identity mapping, owner-scoped entity reads, operations and cursors. Service headers are
  trusted only at the Sites entry. Email is not an identity join key.
- Versioned routine writes, default tomorrow after timezone setup, weekday/date selection, saved plan
  sources, explicit execution state, timeline notes, tombstones and optimistic revision conflicts.
- Atomic entity/change-log/operation-receipt writes, stable retry fingerprints and coherent bootstrap.
- App Group GRDB migration from JSON with original file, byte-preserving backup and migration archive.
  Every account partition has its own document, remote base, outbox, cursor and conflict archive.
- iOS standalone TimelineNote editor, backdating, deletion marker, optional day-block link, Today
  without a Routine and a local-mode skip entry. Fixed block note remains guidance-compatible.
- Local document/outbox transactions, cursor-after-apply, pending edit preservation, acknowledgements
  and conflict archiving. Sync protocol/URLSession transport and engine are implemented but are **not
  connected to the app account lifecycle** until native auth is verified.
- Note conflict comparison and choice UI is implemented. Subsequent edits remain blocked until
  resolved; retaining a remotely deleted note creates a new ID. Both versions are archived atomically.
  Its connected-account wiring still depends on the unfinished account lifecycle.
- Existing system surface dormancy remains in place.

## Deployment evidence

- Site identity: `appgprj_6abe20b9f0688191ad0710e82fbcfff6`.
- Initial connection probe deployed successfully to https://samoyed-nest.timli0617.chatgpt.site.
- Generated plugin: `plugin_asdk_app_sites_48dd33f3b1d481919e399caf0e3ae621`.
- Actual `nest_connection_status` plugin call succeeded with an authenticated Site-scoped identity.
- Unauthenticated native-style HTTP API request returned 401. MCP returned a protected-resource
  discovery challenge. Discovery advertises OpenAI OAuth, PKCE support and refresh, but no supported
  native client registration has been identified. **This is not proof that Sites is incapable.**
- First D1 publish failed on the trigger migration with `incomplete input: SQLITE_ERROR`. The
  generated table migration was preserved; only the failed custom migration and its matching
  metadata were regenerated. Atomic batch guards replace triggers.
- Corrected persistent-service publish succeeded on 2026-10-01, deployment
  `appgdep_6abe291d74f48191922532aa2b8f43d1`, source
  `08033e4e152b0c6646567604ac941fd5c00c0e45` in the Sites source repository.
  D1 overview confirms all nine expected tables. A subsequent actual plugin call returned
  the internal Nest user and unconfirmed timezone state.
- After the user refreshed the installed plugin, all ten MCP tools became available. Actual production
  Note create, idempotent replay, edit, timeline read, stale revision rejection, delete and attempted
  resurrection rejection passed on 2026-10-01. The synthetic test Note was soft-deleted (revision 3),
  and its timeline range was re-read as empty. No second-user check is claimed.
- The SIWC landing link correction was subsequently deployed successfully on the same Site:
  deployment `appgdep_6abe44a430ec81919d8ea83e38f8c1a9`, source
  `0f52cda2116320fcba520019bf393dee718501d2`. Typecheck, build and artifact validation passed.

## Native evidence and current gate

After earlier CoreDevice 4016 failures, the user reconnected the iPhone 16. A fresh signed build,
installation and launch succeeded on 2026-10-01. The actual device's URLSession diagnostic file
reports HTTP 401 for `/v1/capabilities` and `/v1/identity`, and HTTP 200 for OAuth protected-resource
discovery. These are unauthenticated baseline results, not a successful device connection.

The dedicated `--nest-connection-probe` debug launch records status codes without tokens or Note
contents. It cannot bind local data or issue credentials. Inspection found a wrong SIWC return query spelling (`returnTo`);
the native probe was corrected to the platform's `return_to` before evaluating the browser return.
The corrected probe was rebuilt, installed and launched successfully on the same iPhone 16.
Do not declare Sites unsupported based on the earlier device failure or this implementation error.

The user completed sign-in on the corrected build. The device diagnostic file then recorded:

```text
Browser returned. authenticated=true. No device credential issued.
URLSession /v1/capabilities: HTTP 401
URLSession /v1/identity: HTTP 401
URLSession /.well-known/oauth-protected-resource/mcp: HTTP 200
```

This proves browser authentication and return, followed by unsuccessful native authenticated access.
The current probe sends no bearer credential, so it does **not** prove that a correctly registered native
OAuth client would fail. Re-reading Sites connection configuration exposes the MCP resource but no
native registration/exchange settings. OpenID discovery advertises PKCE S256 and refresh grants,
but no registration endpoint. Device credential issuance, refresh and revocation remain blocked on
a supported platform integration path; do not describe them as implemented or accepted.

## Remaining work before beta

1. Establish a supported native Sites credential exchange. Verify on the iPhone after browser closure,
   including renewal and separate device/agent revocation. Never use the Sites service credential.
2. If and only if the platform limitation is confirmed, select the whole-service self-host fallback,
   collect current domain/SSH/volume details, implement Better Auth Passkey plus MCP OAuth, and verify it.
3. Finish iOS account lifecycle, Keychain, login/logout/partition selection, initial import preview and
   idempotent legacy import, conflict UI account wiring, timezone confirmation and sync triggers.
4. Complete per-day correction propagation and historical offline-plan projection, routine parity
   fixtures beyond clock/DST cases, pagination under concurrent changes, schema bounds and retention.
5. Attach/verify the orchestration skill in the generated plugin without creating a duplicate plugin.
6. Run two real accounts, two devices, offline completion/undo/backdated note, lost-response retry,
   app termination/restart, concurrent note edit recovery, deleted-object resurrection attempts,
   cross-user authorization, refresh/revocation, backup restore and real ChatGPT-to-phone round trip.

## Verification

- Swift core: 115 tests passed at the latest recorded run.
- Backend: 14 common contracts passed on Node SQLite and on Miniflare D1.
- TypeScript typecheck and Worker artifact validation passed.
- Signed iOS Debug build, iPhone 16 installation and diagnostic launch passed.
- Production npm dependencies: zero audit findings; development tooling has outstanding advisories.
- No App Store, TestFlight or public plugin-directory submission was performed.

## Plugin connection follow-up

The user completed Refresh tools; the tool inventory and actual Note CRUD calls now confirm the
new schema is active. Synthetic Note ID: `58a88ce0-5849-4dc4-80b8-5ee373428e90`.
The creation operation `055e3f42-9c6c-40eb-aad5-6194537fc506` was submitted twice and returned the
same revision 1 receipt; edit advanced to revision 2 and deletion to revision 3. A query for its backdated
14:15 Asia/Shanghai occurrence returned the note before deletion and no items after deletion.
