# Local MedtrumKit integration

The following open PRs were combined locally on 2026-10-08, on top of MedtrumKit `ef866fa68db22932271af9bce86372ced8604203`.

| PR | Title | Reviewed head |
| --- | --- | --- |
| [#206](https://github.com/jbr7rr/MedtrumKit/pull/206) | better attempts | `d95eb081709029119392c03bcd20fcd122510e8b` |
| [#207](https://github.com/jbr7rr/MedtrumKit/pull/207) | base reset detection | `8e02da741e5b114f604bf6cef2ba6c5714fe116b` |
| [#208](https://github.com/jbr7rr/MedtrumKit/pull/208) | updated instruction screens with "how to" buttons | `792b0692831e5e68d0c232709be4943e34ebdc78` |

Integration was first performed using three-way Git merges in `/tmp/medtrum-pr-review/integration`, including a snapshot of the existing local changes. All three merges completed without conflicts. The combined delta was then applied to the existing MedtrumKit working copy, including image assets.

The actual MedtrumKit checkout remains at its original HEAD with uncommitted local changes. No GitHub branch or PR was modified, and nothing was pushed.

Preserved local work:
- Existing translations (compared per localization entry).
- Expiration reminder fix in `MedtrumAlert.swift` and `PatchSettingsViewModel.swift`.
- Trio Site Change upload/acknowledgement changes, outside this submodule.

Reproducible local regression checks:
```sh
python3 scripts/test-medtrum-connect-attempt.py
python3 scripts/test-medtrum-expiration-reminder.py
python3 scripts/test-medtrum-site-change.py
python3 scripts/test-site-change-uploads.py
```

Upstream #207 includes `BaseResetDetectionTests.swift`. The project uses synchronized folders, so the new tests and walkthrough source are automatically included in their targets.

This integration has not been exercised against a physical pump. Simulator and isolated code tests cannot validate radio behavior or a real pump-base reset.

Validation completed 2026-10-09:
- Full Trio Debug build for iOS Simulator: **BUILD SUCCEEDED**.
- MedtrumKitTests on iPhone 17 / iOS 27.0 Simulator: **TEST SUCCEEDED**, including all BaseResetDetectionTests from #207.
- All four local regression commands above passed.
- All 16 instruction image references resolve to existing image assets.
- Later Swedish localization edits in the shared working copy were left untouched.

Build and test logs: `/tmp/medtrum-pr-review/build.log` and `/tmp/medtrum-pr-review/tests.log`.
