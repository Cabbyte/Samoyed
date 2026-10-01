---
name: samoyed-nest
description: Read and edit Samoyed routines and timeline notes through the authenticated Nest tools.
---

Use the authenticated Nest account. Never accept a user ID from a prompt to select another owner.

Before editing, read the current entity and revision. Use a fresh UUID operationID for a new intent;
retain the same operationID and identical command if a response is lost. Never guess a new revision.
After a conflict, read again and preserve the user's unsaved text for comparison.

A Routine is reusable. An edit defaults to tomorrow in the Nest account timezone. Explicitly state the
resolved effective date in the response. Modifying today requires the user to specify today.
A date exception selects an existing routine or an empty day. A day correction only adjusts an existing
block instance; it does not introduce a one-off appointment. Existing execution history remains intact.

A timeline note is independent text at occurredAt, with an IANA timezone. It can optionally link to a
particular day's block instance. Backdating uses the time of the event, not message creation time.
Notes do not occupy planned duration, complete checklist tasks or disappear when a routine is deleted.
Fixed routine instructions are guidance (the compatible wire field is note).

Task execution uses a desired isCompleted state, never a toggle. Include the original plan ID and
revision from the executing device. Do not reinterpret an old offline execution against a new plan.

Read notes only when needed by the user's authorized task. Saving a note does not send a chat message.
