# Export reliability release gate

## Latest local verification

29 September 2026: all 181 unit tests passed on the iPhone 17 Pro / iOS 26.5 simulator with Xcode 26.6, including the 90-second real export, cancellation/retry and watchdog tests. Result bundle: `/tmp/MemoriesExportTests-Final.xcresult` (local, temporary). Physical iPhone 13 verification remains outstanding. No real-device speedup is claimed.

## Automated coverage

`TripReelModelTests.testRealExporterNinetySecondMixedStoryAtThirtyFPS` runs the real renderer, not the UI demo's simulated progress. It creates a moving H.264 source fixture, interleaves 15 photos and 15 four-second videos, cancels an in-progress export, then retries the same request. It exports 90 seconds at 1080 × 1920 / 30 fps, then decodes and counts all 2,700 frames. The test attaches elapsed time to the Xcode result bundle. It runs with the normal unit test suite in CI.

Watchdog tests check inactivity, cancellation, completion and single delivery of the abort callback. A model test checks that a stall offers retry without downgrading an HD export.

These synthetic, silent H.264 fixtures do **not** establish iPhone 13 performance or cover HEVC/HDR, source audio, iCloud downloads or damaged media.

## Physical iPhone 13 acceptance

Use a Release/TestFlight build, with the same 90-second memory that stopped at 55%. Keep 1080p and 30 fps. Run each case three times; record build, iOS, export wall time, longest unchanged progress interval, free storage and thermal state.

| Case | What it exercises |
| --- | --- |
| Original failing memory, foreground | Reproduction and comparison with previous build |
| 90-second mixed photos/H.264 clips, no music | Frame renderer and encoder |
| Same memory with original audio and music | Audio mixing and final multiplexing |
| Landscape/portrait 4K HEVC and HDR, trimmed clips | Decoder, scaling and orientation |
| Media not downloaded from iCloud | Preparation rather than rendering progress |
| Cancel during video rendering, then retry | Resource release; no duplicate charge or lost edits |
| Three consecutive exports while warm; Low Power Mode | Sustained performance and memory pressure |
| Background, lock, return to foreground | Separate background execution limits |

For completed exports: play through the last frame, check sound sync, Save to Photos, reopen the saved video and create a share link. Check that a failed/retried paid export does not ask for another purchase.

Profile the Release build on a physical device with Instruments Allocations and Time Profiler. Memory should not grow continuously with frame count. Compare at identical settings and footage; simulator times are not device benchmarks.

## Diagnostics and timeout scope

In macOS Console, select the connected iPhone and filter the app's `VideoExport` category. Per-item entries contain frame count, elapsed seconds and whether the item is video. A stall entry identifies the item/frame and encoder or decode/draw stage. Logs deliberately exclude photo names, library identifiers, locations and video contents.

The watchdog requests cancellation after 45 seconds without progress in silent-video preparation/rendering/finalization. This is an inactivity limit, **not** a 45-second total export limit. It runs on a separate queue so it can request decoder cancellation during a synchronous read. AVFoundation must still return from its underlying operation; this is not a guarantee against an operating-system deadlock. Photo-library download preparation and audio mixing have separate code paths and are not covered by this watchdog.

Do not mark the reported iPhone 13 problem resolved solely because simulator tests pass. Ship to TestFlight, reproduce with the original footage, inspect timing/memory, and pass the device checks before publishing.
