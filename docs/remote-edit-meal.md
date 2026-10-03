# Remote meal editing

Trio accepts `command_type: "editMeal"`. Authentication and the existing five-minute
command-age check apply as usual.

| JSON field | Meaning |
| --- | --- |
| `timestamp` | Time the command was sent, in Unix seconds. Must be fresh. |
| `original_time` | Required for editing. The existing parent meal's stored time, in Unix seconds. |
| `scheduled_time` | Optional replacement meal time, in Unix seconds. If absent, use `original_time`. |

`originalTime` is optional in the Swift `PushMessage` model so older command payloads
remain compatible. `editMeal` requires it. Existing `deleteMeal` commands continue
to use `scheduled_time`, falling back to `timestamp`.

Example payload (timestamps are illustrative; send the current time in `timestamp`):

```json
{
  "command_type": "editMeal",
  "user": "Loop Follow",
  "shared_secret": "YOUR_SHARED_SECRET",
  "timestamp": 1791025200,
  "original_time": 1791021600,
  "scheduled_time": 1791022200,
  "carbs": 45,
  "fat": 20,
  "protein": 15,
  "notes": "Updated meal"
}
```

Loop Follow should send the complete edited meal, including zero values for
nutrients that have been removed. Omitted nutrients become zero; omitted notes
clear the old note. At least one nutrient field must be present. Nonzero bolus
amounts are rejected; editing does not deliver insulin.

Use the original meal's full timestamp, not the displayed time rounded to minutes.
Editing matches parent meals (`isFPU == false`) within the specified Unix second.
No match or multiple matches reject the edit. A generated FPU entry cannot identify
a parent for editing. Existing standalone deletion retains its 60-second window.

The edit handler validates amounts and timestamps before deletion, reserves a
deduplication key for the entire operation, then calls `handleDeleteMealCommand`.
Only a successful local deletion permits `handleMealCommand` to run. The old
parent and all entries with its `fpuID` are deleted together. The replacement
gets new IDs and newly calculated FPU entries at its replacement time. Basal
recalculation and the success notification run after the replacement flow rather
than between deletion and insertion. Edits bypass the new-meal check for newer
carb history, which can contain this meal's own future equivalents.

The existing ten-minute in-memory deduplication mechanism covers duplicate edit
pushes. It is not a durable command ledger across app restarts.

## Persistence and external services

“Deletion succeeded” means the local Core Data deletion succeeded. External service
deletions still use the existing asynchronous service APIs, so this result does
not certify Nightscout, Health or Tidepool completion.

Deletion and insertion remain separate operations, not an atomic replacement.
There is no rollback if the app terminates or saving the replacement fails after
deletion. The existing `storeCarbs` API logs persistence errors internally without
returning them; an edit's success notification therefore is not a database commit
receipt. Atomic replacement and durable retry would require a separate storage
change.

## Verification

Run `python3 scripts/test-remote-edit-meal.py` on macOS with Xcode. It compiles
production payload, edit orchestration, validation, deduplication and deletion
code against a temporary SQLite store. It covers linked FPU deletion, changed and
unchanged times, duplicate pushes, ambiguous/missing meals, invalid payloads and
failed deletion. Replacement insertion and external services are test doubles;
this is not an end-to-end iOS or Nightscout test.
