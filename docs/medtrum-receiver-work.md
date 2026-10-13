# Medtrum receiver work experiment

The patch reduces duplicate receiver writes without changing BLE cadence, packet parsing,
raw pump state persistence, lastSync, dose events, bolus progress or loop scheduling.
Only Medtrum receivers are filtered; other pumps keep their existing behavior.

- Reservoir callbacks and status callbacks share one reservoir value cache.
- Patch start storage, expiry/activation publications, pump-name publications and timezone
  broadcasts are suppressed when their values are unchanged.
- Battery database writes and pump-status file saves retain an event-driven 300-second
  refresh deadline. This preserves timestamp freshness (battery readers use a 30-minute window).
  Actual value changes pass immediately. No timer is introduced.
- Caches pass the first value, including nil, and values from a different manager instance.
  A failed battery database save invalidates its cache entry for retry.

`MedtrumWork` summaries are emitted through the Medtrum logger about every 900 seconds
on existing activity. With no activity the report is delayed; windowSec gives the real interval.
Each report contains interval counts, not cumulative totals. PID identifies the process;
counts reset on manager recreation. Absent fields mean zero in that window.

Key fields:
- receivedBLEPackets: nonempty characteristic value callbacks without a reported error
  (characteristic chunks, not necessarily complete protocol messages).
- heartbeatPackets: callbacks on READ_UUID.
- fullSyncAttempts / fullSyncResponses: synchronization requests / parsed full-sync responses.
- notificationStates: parsed non-full-sync state responses.
- stateRequests / stateSuppressed / stateForwarded: kit snapshot filter decisions.
- kitObserverCalls / deviceStatusCallbacks / apsStatusCallbacks / reservoirCallbacks: delivery counts.
- rawStateSaveCalls / reservoirSaveCalls / patchDateSaveCalls / pumpStatusSaveCalls:
  actual calls to the host's save API, NOT confirmation of physical disk writes or success
  (the existing API has no success return value).
- batteryCoreDataSaves: successful context saves.
- reservoirBroadcasts / patchDatePublications / pumpNamePublications / timeZoneBroadcasts:
  calls issuing those notifications, not the number of subscribers.
- reservoirSuppressed / batterySuppressed / pumpStatusSuppressed: avoided work.

Validation: `python3 scripts/test-medtrum-receiver-work.py` exercises the production
value gate and counters with deterministic timestamps: duplicates, changed values,
manager replacement, nil transitions, five-minute refresh, failed-save retry, summary
intervals and counter reset. Full Trio simulator build checks framework integration.

For the device trial, install a build containing BOTH the Trio and MedtrumKit changes.
Collect Trio and MedtrumKit logs after approximately a day, plus battery start/end times
and notable periods out of Bluetooth range. Compare counts per window and runtime;
log reduction or passing tests alone do not establish battery savings or device safety.

## 2026-10-11 school-day experiment

- Snapshot comparison now copies typed values instead of constructing the raw persistence
  dictionary (and encoding previousPatch) for each notification. It still includes every
  persisted field, mutable dose progress by value, transient fields and time-dependent status.
  Notification scheduling, actual state serialization and freshness rules are unchanged.
- `Logga diagnostik` remains the master switch for Trio diagnostics. New `Detaljerad diagnostik`
  defaults OFF, independently of an existing enabled diagnostic preference. Leave diagnostics
  ON and detail OFF for the school-day trial. Detail enables per-task BGTask lines and the
  Medtrum debug packet log. Warnings/errors and MedtrumWork are retained independently.
- BGTaskSummary reports every approximately 15 minutes on existing activity, with counts per
  name/event, peak/current open tasks, oldest open age and maximum completed duration. Anomalies
  and expirations still log immediately when diagnostics are enabled. Tasks spanning a reporting
  boundary need not have balanced start/end counts in that particular window; trackedOpen is
  the current gauge. No timer is added and no UIKit task lifetime is changed.
- MEM snapshots and registered-object sampling use a 15-minute cadence in summary mode;
  detailed mode retains the prior minute cadence and forced samples. The in-app memory display
  consequently refreshes less often in summary mode.

New MedtrumWork fields:

- fullSyncReconnect / fullSyncPeriodic / fullSyncExplicit: request reasons. Existing
  bolusVerificationAttempts is the fourth reason. Explicit syncs now participate in the
  aggregate fullSyncAttempts/fullSyncResponses, so those totals are not perfectly comparable
  with the earlier instrumentation. Responses may land in a later reporting window.
- unexpectedDisconnects, reconnectScheduled, disconnectsBeforeReady: transport events, not
  missed loops. A disconnect before readiness can be followed by another retry in the same outage.
- recoveryCount / recoveryMsTotal / recoveryMsMax: completed recovery from the first unexpected
  disconnect until the fully ready session, including failed retries. Radio-off and deliberate
  disconnects reset measurement. Ongoing outages have not yet contributed a recovery duration.
- readySessionCount / readySessionMsTotal / readySessionMsMax, readySessionsUnder60s: lifetime
  of fully ready sessions that subsequently disconnect. Initial ready time is observed when the
  connection completion succeeds. A session that stays connected is not included until it ends.
- historyBatches / historyEvents / historyDuplicateCandidates / historyUnchangedBatches /
  historyContextSaves: receiving storage work attributable to Medtrum. Duplicate candidates can
  still correct an earlier bolus; this measurement does not discard any events. Context saves
  are successful saves, not physical disk I/O. Async results can cross a reporting boundary.

For comparison, retain charge-disconnect time, battery end time, periods with the phone carried
and periods at a distance. Do not interpret counter reductions as measured CPU or battery savings.

Validation includes the full Trio simulator build, MedtrumKitTests (including typed-vs-legacy
persistence comparison, mutable dose copies, freshness and cancellation timeout), the existing
receiver/bolus preflight harnesses, and scripts/test-background-work-summary.py.

## 2026-10-13 CPU diagnostics removed

The temporary process CPU sampler and its dedicated test harness have been removed after
profiling. RuntimeDiagnostics continues to collect memory footprints and bounded counters
at the existing cadence. MEM logging, RAM display and Nightscout devicestatus reporting
remain unchanged. MedtrumWork and background-task summaries remain available.

Omnipod reference, 2026-10-08 06:43–12:00 (Loggarkiv/log_prev.txt): 57 logged connect-on-demand
scans, 57 connections and 57 disconnections; median spacing of scan starts 301 seconds.
This is evidence of short communication sessions, not a count of actual system wakeups.
