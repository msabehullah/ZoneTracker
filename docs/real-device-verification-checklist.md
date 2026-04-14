# ZoneTracker Real-Device Verification Checklist

Use this checklist on a physical iPhone + Apple Watch pair. The simulator build is useful for UI and unit tests, but it does not prove the product-critical flows below.

## Preconditions

- Xcode signing is configured for the real app IDs.
- `Sign in with Apple` capability is enabled for the iPhone app target.
- CloudKit capability is enabled with the intended container.
- The iPhone and Apple Watch are paired and signed into the expected Apple ID.
- The iPhone is trusted by the Mac, visible in Xcode, and available as a run destination.
- The watch appears in Xcode as a paired watch destination before attempting watch installation.
- Developer Mode is enabled on both the iPhone and the paired Apple Watch.
- HealthKit permissions are available on both devices.
- Start from a clean install when verifying onboarding/auth behavior.

## Watch Setup Sanity Check

Run this before spending time on app-side debugging for the watch.

1. Connect the paired iPhone to the Mac with a cable and keep it unlocked.
2. Confirm the iPhone appears in `Xcode > Window > Devices and Simulators`.
3. In Xcode, select the shared `ZoneTrackerWatch` scheme.
4. Check whether the paired Apple Watch appears as a watch run destination.
5. If the watch does not appear, confirm the watch is unlocked, on wrist or recently unlocked, and near the iPhone.
6. Confirm Developer Mode is enabled on both the iPhone and the paired Apple Watch.
7. If Xcode or `devicectl` times out waiting for `CoreDeviceService`, restart device services on the Mac, reconnect the iPhone, and reopen the destination picker.
8. Retry a watch run from Xcode after the iPhone is available for development.
9. If the watch still does not appear, reboot the iPhone and Apple Watch, then re-check Xcode.
10. If the watch still does not appear, fix the phone/watch pairing state before changing app code.

Expected result:
- Xcode can see the physical watch as a destination. Until that happens, watch install failures are not actionable app-side failures.

## 1. Auth And App Gating

1. Launch the iPhone app fresh.
2. Confirm the app opens in the signed-out state.
3. Complete `Sign in with Apple`.
4. Confirm the app moves to onboarding instead of skipping straight into the main tabs.
5. Complete onboarding.
6. Confirm the app moves into the active dashboard flow.
7. Force-quit and relaunch the app.
8. Confirm account state and profile persist cleanly.

Expected result:
- Signed-out, signed-in-not-onboarded, and active-app states all appear at the right times.

## 2. CloudKit Persistence And Sync

1. While signed in, change profile values in Settings.
2. Create at least one workout on phone.
3. Send a planned workout to the watch.
4. Relaunch the iPhone app.
5. Confirm profile, workout history, and the latest plan still exist.
6. If a second iPhone signed into the same Apple ID is available, install and sign in there.
7. Confirm profile and workouts appear on the second phone after sync.

Expected result:
- Cloud-backed data survives relaunch and is tied to the signed-in account.

## 3. Phone To Watch Planned Workout Delivery

1. Open Dashboard on iPhone.
2. Confirm `Next Planned Workout` is the main CTA.
3. Send the plan to the watch.
4. Open the watch app.
5. Confirm the watch shows the planned workout rather than a generic workout first.
6. Verify the watch displays:
   - session type
   - target range
   - duration target
   - interval segment structure when applicable

Expected result:
- The watch receives a structured execution plan and presents it as the primary path.

## 4. Live Coaching And Haptics

### Steady session

1. Start a steady Zone 2 workout from the plan sent by phone.
2. Let heart rate drop below the active target range.
3. Confirm the watch gives one below-range haptic and updates the UI state.
4. Stay below range longer than a few seconds.
5. Confirm the watch does not spam repeated haptics before re-arming.
6. Return to the target range.
7. Confirm the watch re-arms coaching after returning in range.
8. Push above range.
9. Confirm the watch gives one above-range haptic.

### Interval session

1. Start an interval plan.
2. Confirm the active segment and segment target range are visible.
3. Let the segment change naturally.
4. Confirm target range updates with the new segment.
5. Repeat below-range / above-range checks during different segment types.

Expected result:
- Haptics occur on state transitions, not continuously.
- Segment-aware coaching follows the active interval target.

## 5. Watch Completion To Phone Auto-Ingest

1. Complete a planned watch workout.
2. Leave the iPhone app running, then repeat with the iPhone app backgrounded.
3. Confirm the phone ingests the completion payload automatically.
4. Open History and confirm the workout appears without manual HealthKit import.
5. Open Dashboard and confirm the next recommendation reflects the completed session.

Expected result:
- Planned watch workouts auto-save on phone and affect future recommendations.

## 6. Recovery And Fallback Paths

1. Start a planned workout with the phone temporarily unreachable.
2. Complete the workout.
3. Reconnect the phone and confirm the payload still arrives later.
4. Verify manual logging still works.
5. Verify manual HealthKit import still works for recovery or unsupported cases.

Expected result:
- Phone/watch delivery is resilient enough that a transient disconnect does not lose workouts.

## 7. Specific Regressions To Watch For

- Duplicate inactivity notifications.
- Wrong workout activity type after import.
- Phase progression inconsistent with user-facing 6-week copy.
- Leg-day deferral not affecting interval recommendations.
- Stale watch state carrying over between workouts.
- Incorrect zone-time accumulation after repeated workouts.
- Duplicate saves when the same workout is received more than once.

## Suggested Evidence To Capture

- One screen recording of Sign in with Apple through onboarding.
- One short steady-session haptic demo.
- One short interval-session segment transition demo.
- Screenshots of:
  - Dashboard before send
  - Watch planned workout start screen
  - Watch live coaching screen
  - iPhone History after watch completion
  - Dashboard after recommendation refresh
