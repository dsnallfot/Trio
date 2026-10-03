# Nightscout upload lifetime patch

Device status is for live monitoring. This patch retains at most one pending refresh,
which reads the latest data when it runs. It does not backfill historical status gaps.

## Behavior

- After saving the loop result (including enacted state), APSManager explicitly hands
  uploads to Nightscout before ending its own background task. Both open-loop and
  closed-loop exits use this handoff.
- All device-status callers share one serial worker. Existing callers of
  `uploadDeviceStatus()` still await completion; the loop's `enqueueLoopUploads()`
  only awaits acquisition of background time.
- A burst of triggers becomes one current attempt and at most one pending refresh.
  Identical successful payloads are suppressed for 60 seconds. The comparison includes
  suggested/enacted content, pump state, uploader state, settings, and the destination;
  only the two memory usage diagnostics are excluded. An enacted update is therefore
  not suppressed merely because `deliverAt` is unchanged. Failed attempts do not
  update the deduplication key.
- Post-loop treatments and pod-age uploads use separate workers, so they cannot hold
  the loop gate or block status behind a slow treatment request. Existing independent
  treatment subscribers are unchanged.
- Error notes acquire background time and return without awaiting the network.
  Each note has its own worker; notes are not coalesced.
- UIKit task identifiers belong to individual main-actor lifetime objects, with
  idempotent completion and generation-checked expiration. Expiration cancels the
  network operation and discards pending work. The next external trigger can try
  again; there is no periodic retry or stored historical status queue.

## Verification

Run `python3 scripts/test-nightscout-upload-worker.py` from the repository root.
It compiles the production lifetime/worker classes with a deterministic UIKit fake
and checks the real status model comparison (including enacted revisions),
handoff overlap, serialization, latest-trigger coalescing, cancellation,
a new trigger during cancellation cleanup, denied background time, independent
status/treatment progress, and stale expiration callbacks.

These tests do not emulate actual iOS suspension or contact Nightscout.

## Physical test phone

Build the Trio workspace as usual. Let the app run in the background for several
sensor cycles and compare the current device status in Nightscout/LoopFollow.

Useful log markers:

- `NS status start suggested=... enacted=...`
- `NS status success ... elapsedSec=...`
- `NS status failed ... cancelled=... error=...`
- `BGTask ... name=nightscout-status ... event=start/end/expiration`
- `BGTask ... name=loop ... event=end reason=upload-handoff`

For the handoff, upload background time should already be active when the loop's
background task ends. A status operation may also have finished before handoff.
There should no longer be loop `after-uploads ... invalid-id` messages.

Check a cycle with a newly enacted result: its updated status should reach Nightscout
even if a suggested status was already uploaded for that same calculation. On the
test phone, also check recovery after briefly losing network access. Do not expect
old device-status gaps to be filled on recovery.

Background time remains controlled by iOS. This fixes premature release by Trio;
it does not guarantee delivery when network access or background time is unavailable.
