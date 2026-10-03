# Nightscout treatment serialization

All existing calls to `uploadManualGlucose`, `uploadCarbs`, `uploadPumpHistory`,
`uploadOverrides`, and `uploadTempTargets` now enter a shared coordinator in
`BaseNightscoutManager`. Each treatment family has its own serial worker. This
includes calls from Core Data observers, loop uploads, shortcuts, remote commands,
configuration notifications and network recovery wherever those callers exist.

The worker encloses fetching pending records, network operations and persisted
acknowledgement. A burst becomes one active pass and one pending refresh. Payloads
are fetched inside each pass; a pending refresh cannot reuse a pre-upload snapshot.
Existing async callers wait for the worker to drain. Different families remain
independent, and use the existing UIKit background lifetime/expiration behavior.

Override definitions and completed runs share a worker. The existing conditional
DELETE followed by POST is preserved; the redundant individual POST of definitions
has been removed, leaving one batch POST. This change does not deduplicate by UUID
forever: later edits of an override must still be uploadable.

SGV uploads can include manual readings, but must not mark their shared
`isUploadedToNS` flag as true. That flag is acknowledged by the BG Check treatment
upload. Otherwise a successful SGV request can prevent the manual treatment from
being sent. The SGV payload and local webhook payload are unchanged.

## Remaining delivery limitation

This fixes overlapping client jobs, not exactly-once delivery. If a POST succeeds
on Nightscout but its response is lost, the record stays pending and may be sent
again. Failed local acknowledgement and partially successful multi-batch uploads
also retain this existing retry risk. A GET-before-POST check alone cannot
atomically prevent duplicates. No unverified `_id` format or server-specific
upsert behavior is introduced in this patch.

A follow-up needs verification of the deployed Nightscout API's idempotency or an
atomic server-side idempotency mechanism. Overrides require particular care:
legitimate revisions and delete/recreate operations must not be suppressed by an
idempotency key that identifies only the logical override.

Scope is the five Core Data treatment families above. Ad hoc notes, error notes,
CGM-state treatments and SGV entry uploads are not newly serialized by this patch.

## Verification

- `python3 scripts/test-nightscout-treatment-uploads.py` compiles the production
  entry points, scheduling, fetch/send orchestration and worker with fake storage
  and network. Tests suspend the first POST, overlap multiple callers, add a new
  pending record, and assert one send per record plus fresh subsequent fetching.
  Also tests secondary records, override delete/post ordering, failed-send retry,
  independent families and the production SGV acknowledgement predicate.
- `python3 scripts/test-nightscout-upload-worker.py` covers the existing worker's
  background lifetime, cancellation, denied execution and status behavior.

These tests do not emulate actual Core Data merging, iOS suspension or Nightscout.
On-device verification should register through a shortcut/remote command, then
edit and end an override, and confirm the treatment counts and chart duration.
