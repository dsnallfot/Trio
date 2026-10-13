# G7 nonzero glucose status in Trio

Integrated the diff from loopandlearn/G7SensorKit PR #16, head
`36a514657d320564f6b5e1de2962defa7cdc0d56`:
https://github.com/loopandlearn/G7SensorKit/pull/16

The parser accepts nonzero status replies and preserves their algorithm state,
while withholding glucose, prediction and trend. The PR also retries version
information until the serial arrives and defers sensor-start events until the
serial arrives (or the next reading after ten minutes, or sensor end).

## Trio integration

Trio's PluginSource does not implement Loop's alert presentation. The upstream
change alone would remove the log message used by our fallback and deliver
`noData` rather than an error, leaving the specific sensor issue unreported.

G7CGMManager now emits `G7SensorError.glucoseUnavailable(status:algorithmState:)`
for a decoded nonzero-status reading, before the failed-sensor teardown. It
does not emit a glucose sample from that reply. PluginSource maps this typed
error into its existing Home sensor-issue publisher and Nightscout note path.
Known terminal algorithm states get the sensor-replacement message; temporary
issues and warmup get their own messages. Unknown states remain visible with
their status and algorithm state, without claiming permanent sensor failure.

The old log-text fallback remains for replies that cannot be parsed at all.
Notes are deduplicated by message until a recent, non-display-only reading
arrives. Empty results and old backfill do not clear the banner. These are the
existing in-memory semantics; the note goes through the existing Nightscout
uploader, not a new local notification service.

## Checks

- `python3 scripts/test-cgm-sensor-banner.py` exercises the production mapping,
  note deduplication and recovery code with a fake uploader; no remote notes
  are sent.
- G7GlucoseMessageTests includes the PR's real failed-sensor payload.
- G7LifecycleAlertManagerTests checks host error delivery for terminal and
  unknown nonzero statuses, plus the PR's sensor-start event behavior.

Simulator tests do not establish physical-sensor behavior or delivery through
the user's remote Nightscout notification configuration.

Validation on 2026-10-11: the banner/uploader harness passed, the Trio Debug
arm64 Simulator build succeeded, and the selected G7GlucoseMessageTests,
G7LifecycleAlertManagerTests and G7CGMManagerTests passed. The initial test
launch failed in ThreadSanitizer before execution; the successful run disabled
ThreadSanitizer and UndefinedBehaviorSanitizer and used English/US test settings.
