# Home presentation work while backgrounded

## Evidence (2026-10-12)

`Trio-bakgrund.trace`, attached PID 29380, 18:16:41–18:31:42, 901 seconds.
User confirmed phone locked and screen off. Instruments' lifecycle table itself
reported Unknown (attached process, no observed lifecycle transition).
27,266 weighted 1 ms Time Profiler samples: main thread 73.8%, UIHostingView
transaction stacks 69.2%, Charts binary present in 58.3%. Categories overlap;
these are sampled CPU distributions, not energy estimates or getrusage totals.
189 UI activity groups (>300 ms sample gap), median start separation 5.000 s.
Home.StateModel's five-second timer writes observable timerDate, which RootView
previously read while constructing headers alongside the charts.

## Patch

- Home owns a presentation-only clock lifecycle. It runs only while the scene is
  active and the Home tab is selected; disappearance also suspends it.
- The main-queue callback checks visibility again, so queued ticks after hiding
  cannot update the UI. Resuming refreshes the date immediately.
- Dedicated small PresentationClockView bodies observe timerDate, preventing
  that dependency from invalidating RootView and its chart siblings.
- The chart subtree is removed in background or on other tabs. Inactive transient
  states (e.g. Control Center) retain the chart, but suspend the header clock.
- Visible charts refresh with data changes and a one-minute TimelineView clock.
  The timeline is removed along with the charts in background.
- Recreated charts rebuild both regular and temporary basal presentation caches.
  Selected time range is retained; scroll/selection returns to the usual initial
  current-time position after backgrounding or switching tabs.
- Data reception/storage, Home data subscribers, pump/CGM communication, loop
  scheduling, alarms, bolus commands and Nightscout uploads are unchanged by this
  patch. Existing data subscribers keep presentation data current for reopening.

## Validation

Run `python3 scripts/test-home-presentation-clock.py` for real lifecycle-method
behavior: initial inactivity, repeated transitions, queued tick after hiding,
immediate date refresh on resumption and subsequent active ticks.
Build the full Trio simulator target.

On device: Home -> lock for 15 minutes -> reopen; verify current glucose, graph,
regular/temp basal series, current-time marker, bolus status and time-range
controls. Switch tabs and back. Check live data updates while looking at Home.
Repeat Time Profiler capture and process CPU summaries with the same phone
conditions. Expect the periodic five-second chart bursts to disappear; do not
interpret the old sample percentages as promised battery savings.
