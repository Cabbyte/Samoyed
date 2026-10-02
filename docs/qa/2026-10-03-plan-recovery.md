# iPhone 16 plan structure recovery

- Physical iPhone 16, installed Samoyed 2.2.1 (14), displayed `Unable to Load Now` / `A block extends outside its parent block` on 2026-10-03. No simulator was used.
- The server's October 3 plan revision 2 combined two executed blocks from the previous routine with the replacement routine. A retained 09:30 root shortened a new 09:00–11:30 parent while its later children remained. The merged plan was persisted without structural validation.
- The consistent pre-repair server backup passed `PRAGMA integrity_check`. The failure was an invalid day-plan tree, not demonstrated SQLite corruption.
- The fix preserves whole executed/started/corrected subtrees and validates the merged snapshot before persistence. A conflicting replacement keeps the previous valid snapshot and its source metadata. Parent corrections keep descendant absolute times consistent with correction validation.
- Administrative recovery defaults to preview, checks source/current revisions, retains protected block contents, refuses concurrent writes, and appends an idempotent plan revision. All earlier versions and events remain stored.
- Backup rehearsal: revision 2 restored from revision 1 as revision 3, six valid blocks, both protected blocks intact. Re-resolving retained the restored source. All seven current cloud plans validated; every non-plan entity, operation, and change remained byte-for-byte unchanged.
- Validation: TypeScript typecheck passed; Node SQLite 32/32; D1 29 passed with the three Node-only auth tests skipped; Node 24 Linux amd64 tests under production memory/CPU/PID limits 32/32. Production deployment and phone recovery are recorded after verification.
