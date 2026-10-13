# Contact image rendering cache

The contact image manager keeps one render key and encoded PNG per configured
contact. Identical inputs reuse the PNG before UIKit/SwiftUI rendering and encoding.
The existing Contacts lookup, byte comparison, and write path still run. Failed
writes can retry with the cached PNG; external image changes can still be repaired.
An encoding failure removes that contact's cache entry and retries next time.
Entries for removed contacts are pruned on the next batch refresh. Cache contents
are in memory only and start empty after an app restart.

The key conservatively includes the full ContactImageState and contact settings,
plus resolved age-dependent state (stale BG, loop age category, and bobble minutes),
current traits, locale and time zone. The transient UI UUID generated on every
storage fetch is normalized; managed object identity is not retained. Changes to
unused state may still cause a render; this patch does not attempt per-layout
state reduction.

A single timestamp is used for both the key and rendering so a clock boundary
cannot cache an image under the wrong freshness category. This does not add a
timer or change refresh triggers, dosing, CGM processing, or alarms.

Validation:
- `python3 scripts/test-contact-image-render-cache.py` executes the production key
  and cache methods with a counting renderer and lightweight platform stubs.
  Covers repeated inputs/fresh UI IDs, changed glucose/settings, stale BG,
  loop ring thresholds, rounded bobble age, encoding failure/retry, and pruning.
- Full Trio iOS Simulator build checks the actual UIKit/SwiftUI integration.
- Device follow-up: confirm configured contact images update for new readings,
  settings, and stale transitions. CPU/energy benefit has not yet been measured.
