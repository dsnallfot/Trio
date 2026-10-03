# MedtrumKit integration

Based on https://github.com/nightscout/Trio/pull/1039 (head `4dd90024dd8d9b5edf7f317946aed7ea3685687f`).
MedtrumKit is pinned to `b7f3d44c06bb7c580be897e0414e64de2d6dd995`, the submodule revision in that PR.

## Adaptations for this fork

- Register Medtrum alongside the existing unified `OmniPumpManager`, Dana, Medtronic and simulator managers.
- Add Medtrum Nano to both existing pump selectors and use MedtrumKit's pump setup controller with Trio's initial delivery settings and Bluetooth provider.
- Link and embed MedtrumKit through `Trio.xcworkspace`.
- Forward reservoir updates and patch expiry to Trio. Forward activation time only in extended expiry mode, as in the source PR.
- Preserve the custom pump header layout. Extended mode gets the plus-hourglass icon and the PR's 80-hour color threshold, evaluated using the view's timer date.
- Reset patch dates when changing/removing the pump, and clear activation time when leaving extended mode or when no patch is active.
- Use the fork's existing English/Swedish `.strings` files instead of importing the upstream string catalog.
- Exclude MedtrumKit from Trio's formatter.

No files under `Trio/Sources/Modules/Onboarding` were imported or modified. MedtrumKit's own pump pairing/setup UI is required for adding the pump and is included.

## Checkout and verification

After cloning this fork, run `git submodule update --init --recursive` and open `Trio.xcworkspace`.

Build verification command:

```sh
xcodebuild -workspace Trio.xcworkspace -scheme Trio -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/trio-medtrum-build CODE_SIGNING_ALLOWED=NO build
```

Verification completed on 2026-09-24 with Xcode 27.0 (27A266a):

- Full clean Debug simulator build: **BUILD SUCCEEDED**, including arm64 and x86_64.
- MedtrumKit framework is present in the built app's `Frameworks` directory.
- Swift syntax, project plist and English/Swedish localization validation passed.
- `git diff --check` passed; no changes under `Modules/Onboarding`.
- Xcode still reports dependency declaration warnings for the existing DanaKit and G7SensorKit integration.

Physical pump pairing, delivery and background Bluetooth behavior have not been tested; a simulator build does not verify those behaviors.
