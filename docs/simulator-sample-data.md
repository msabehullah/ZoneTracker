# Simulator Sample Data

ZoneTracker now supports a debug-only seeded app state for simulator review.

## Launch Arguments

- `-codex-bypass-auth`
  Uses the existing debug Sign in with Apple bypass.
- `-codex-seed-sample-data`
  Resets the local SwiftData store to a realistic sample profile and workout history on launch.
- `-codex-selected-tab 0|1|2|3`
  Opens Dashboard, History, Progress, or Settings directly.

## Example

```bash
xcrun simctl launch booted com.zonetracker.app \
  -codex-bypass-auth \
  -codex-seed-sample-data \
  -codex-selected-tab 2
```

## What Gets Seeded

- A completed-onboarding sample profile in `Phase 2`
- A believable multi-week workout history across treadmill, bike, intervals, and mile benchmarks
- Enough data to populate:
  - dashboard quick stats
  - history grouping
  - progress timeline
  - pace chart
  - mile benchmark trend
  - recovery trend
- Mock resting heart rate history for simulator-only chart rendering

## Notes

- This path is `DEBUG` only.
- It is intended for simulator/demo/UI review, not production data migration.
- Launching with the seed argument overwrites the current local simulator data to keep screenshots deterministic.
