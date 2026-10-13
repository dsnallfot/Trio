# Verify pending bolus before delivery commands

Incident: 2026-10-10, a 1.5 U bolus was accepted at 20:07:30, delivery was
reported at 20:07:31, and contact was lost at 20:07:45. Later temp-basal
requests reported "already bolusing" from retained state until explicit completion
arrived at 20:24:18. The 20:06 failed request was a separate attempt.

Both bolus and temp-basal command paths now establish communication first. If a
bolus was pending before connection, or remains pending afterwards, they explicitly
request a synchronization response and require valid, non-truncated bolus fields:

- connection/read failure, missing fields or invalid payload: communication error
  explaining that the previous bolus completion could not be verified; no new
  delivery command is sent;
- explicit completed=false: already-bolusing error;
- explicit completed=true: reconcile through StateSyncer, then require local bolus
  state to be clear before continuing the requested command.

There is no elapsed-time fallback and no retry of a delivery command. The previous
checkBolusDone reconnect fallback no longer invents full delivered units when bolus
fields are missing; it retains the pending dose and reports uncertainty.
A pump that cannot provide completion information can therefore remain blocked
pending reconciliation. This is intentional, rather than treating elapsed time as
proof of delivery. Pump state remains conservative while contact is unavailable.

The ordinary no-pending-bolus path adds no extra sync request. Basal suspension is
also rechecked after preflight before issuing a bolus. Acknowledged bolus completion,
not command acceptance alone, is what releases an existing pending bolus.

Validation:
- scripts/test-medtrum-bolus-preflight.py executes production preflight with fake
  transport and clock-independent outcomes; no device data or real commands.
- PumpStateSnapshotTests covers the production response decision for absent,
  active, completed, truncated and invalid responses.
- Full Trio simulator build and MedtrumKit simulator suite validate integration.

These tests do not reproduce a real radio dropout. Verify device behavior without
creating extra insulin requests just to exercise the error case.

Recovery: an unsuccessful verification is not latched. A later command retries
connection/status verification. Reconnection status can also reconcile completion
before the next command. An explicit regression test covers failure followed by
successful completion on the same manager. No history-download command is currently
implemented in this MedtrumKit, so the patch does not claim historical fallback.

Verified: full Trio simulator build passed, MedtrumKit simulator suite passed,
and production-control-flow harness plus receiver-gate harness passed.
