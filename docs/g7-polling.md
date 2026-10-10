# G7 routine polling

Trio keeps its existing one-minute fetch timer. G7's fetch completion still returns
`noData` immediately; actual readings and sensor errors arrive through the CGM delegate.

## Connection handling

On its Bluetooth queue, G7SensorKit skips routine connection work when its active
peripheral matches the target (or no explicit target is set) and is connected or
connecting. A missing/disconnected link and a changed target still enter recovery.
Discovery also avoids resubmitting a connection already managed by this central.
A peripheral connected elsewhere in iOS still receives the initial `connect` call
when adopted by this central, preserving eavesdropping behavior.

Disconnect/error recovery, Bluetooth power-state recovery, authentication, reading
requests, backfill and the polling interval are unchanged. There is no new timeout
or cancellation of pending connections.

## Empty poll results

Only `noData` returned by a G7 fetch completion bypasses Trio's sensor-error handling.
Delegate results, errors and other CGM implementations retain their existing path.
Empty glucose batches still run the age-based stale check, but no longer acquire and
immediately release background execution time. Nonempty batches retain background
protection and the existing storage/loop path.

## Validation

Regression tests cover connected/pending links, missing/disconnected links, a changed
target and initial adoption of a system-connected peripheral. Run `G7CGMManagerTests`
and `G7SessionModeMigrationTests` with test language `en` and region `US`: an existing
model-name test expects English localized strings.

On 2026-10-09, all 48 selected tests passed in English, including the three new
connection-policy tests. The complete Trio Debug build succeeded for arm64 iOS
Simulator. A Swedish-language run passed the connection tests but failed three
English string assertions in the existing model-name test.

Simulator tests/builds do not measure battery savings or establish physical-sensor
recovery behavior. Device observation is still needed, especially with the screen
locked, after an out-of-range interval and after Bluetooth is restored.
