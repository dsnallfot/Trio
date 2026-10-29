# PR #1443 — Dynamic ISF sigmoid boundary fix

Applied 2026-10-29 to the local ivar-dev-os port.

Source: https://github.com/nightscout/Trio/pull/1443
Upstream head: c9892a566d680f90e42338c1f7f14a7e8d6198af

Imported the exact DynamicISF.swift hunk and both DynamicISFTests.swift regression tests. Excluded unrelated Localizable.xcstrings changes.

When autosensMin is exactly 1 and sigmoid is enabled, use 0.99 internally for the curve floor to avoid log10(0) and the resulting Decimal conversion crash. Final clamping still uses the configured limits. This intentionally differs from legacy JavaScript, which produces a constant ratio of 1 in this case; Swift can respond to rising glucose. Other limits and the logarithmic formula are unchanged.

Validation: native macOS test host compiled the current Swift core. Both added tests and the complete DynamicISF suite passed. The full run executed 216 tests and reported 31 failures, all reason-text assertions expecting the original English strings. A control run with only these PR changes removed from the temporary host executed 214 tests with the exact same 31 failures (file, line and assertion matched). The repository fix remained applied throughout. No full iOS build or device run was performed for this patch.
