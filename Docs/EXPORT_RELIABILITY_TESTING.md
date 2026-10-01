# Export reliability release gate

## Latest local verification

1 October 2026: all 200 unit tests passed on the iPhone 17 Pro simulator, including the new resume tests below. 30 September 2026: all 194 unit tests passed on the iPhone 17 Pro simulator, including a real 120-second 1080p export with soundtrack and atmosphere (`testRealExporterTwoMinuteHDFilmWithSoundtrackAndAtmosphere`, about 102 seconds on the simulator), the free and paid film test, and new tests for the audio-stage monitor and the PhotoKit inactivity guard. The reported hang after payment on long films was **not** reproduced in the simulator, so it is not confirmed fixed. It still needs the physical iPhone checks below.

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

The watchdog requests cancellation after 45 seconds without progress in silent-video rendering and finalization. This is an inactivity limit, **not** a 45-second total export limit. It runs on a separate queue so it can request decoder cancellation during a synchronous read. AVFoundation must still return from its underlying operation; this is not a guarantee against an operating-system deadlock.

Two more stages now have their own inactivity limits:

- **Soundtrack mix and final mux** run under a second watchdog. `ExportSessionProgressMonitor` polls each `AVAssetExportSession`'s progress and reports every change, so a slow export that keeps advancing is left alone. A session that stops advancing for 45 seconds is cancelled and surfaces as the same retryable "Export paused" state, and task cancellation now cancels the session too.
- **PhotoKit downloads** (iCloud photos and videos) fail after 60 seconds with no progress callback (`RequestInactivityGuard`) and surface as "needs a little longer in Photos", which offers a download retry. A stalled request is not retried three times.

## Why export re-downloads from iCloud

Analysis and First Cut read only what is already on the iPhone (`allowsICloudAssetDownload` is false, and videos get network access only on a follow-up pass), and playback uses small opportunistic images. Export is the first step that asks for the full-quality originals (up to 4,096 px photos and high-quality video), so every iCloud download happens there. Up to three items are now fetched at the same time (`maxConcurrentPreparations`); before, they were fetched one after another. 

To avoid making the user wait after paying, the app now prefetches the full-quality originals for an HD export while the user is on the First Cut, options, second-watch, pace, export or paywall screens (`MediaPrefetchCoordinator`, started from `TripReelModel.go`). At export time the exporter waits for a running prefetch, reuses what it fetched and fetches only what is missing. A retry reuses the same prefetched originals. Prefetch is skipped on cellular and in Low Data Mode, uses two downloads at a time at background priority, stops waiting after 60 seconds without progress, and is discarded when the user leaves the flow, finishes, or chooses the free export. A test exports after deleting the source photos to prove reuse; how much time it saves on a real iCloud-backed library has not been measured on a device.

Do not mark the reported iPhone 13 problem resolved solely because simulator tests pass. Ship to TestFlight, reproduce with the original footage, inspect timing/memory, and pass the device checks before publishing.

## Resumable rendering (added 1 October 2026)

A paid film is no longer one long job that iOS can throw away. The silent video is rendered in pieces of
about ten seconds (whole timeline items), each written to its own file under
`Application Support/RenderCheckpoints/<fingerprint>/` with a small manifest and the last picture shown
(a lossless PNG, needed for the cross fade into the next piece). The finished pieces are joined without
re-encoding, and only a finished film clears them.

- **Interruption** (iOS ends the background task, a stall, a crash, the app is closed) keeps the finished
  pieces. The next attempt skips them. When iOS pauses a background export the app now shows "Export
  paused", and `TripReelModel.resumeInterruptedExportIfNeeded()` continues automatically when the person
  returns. Cancelling on purpose discards the pieces.
- **Fingerprint:** a hash of everything that changes the pictures (photos, titles, text, look, motion, quality,
  frame rate). An edited film never reuses old pieces. Pieces nobody came back to are removed after 48 hours.
- **No B-frames in pieces.** Frame reordering shifted each piece's timestamps and made the joins overlap;
  without it the joined film has perfectly regular timing (840 frames at 30/1 fps in a 28-second test).
- **Unique attempt files.** A cancelled attempt's writer deletes its output asynchronously. Pieces first
  write to a unique file and are renamed into place when complete; before this, a resume could have its
  piece deleted by the cancelled attempt's late cleanup (it failed 2 of 3 runs of the 90-second test).
- The screen stays awake while a render runs in the foreground.

Tests: piece plan, fingerprint, and `testInterruptedExportResumesFromFinishedPiecesAndMatchesAnUninterruptedFilm`
(interrupts a 48-second export after the first piece, resumes with a new exporter, checks it renders only the
remaining pieces, that both films are 48 s at 30 fps and look the same at the joins, and that saved pieces are
cleared). Not yet verified on a physical iPhone: how often iOS ends the background task there, and how long
a full 1080p film takes on an older phone.

## My exports: finished films kept on the phone (added 1 October 2026)

A finished film is kept in the app's private storage, with no upload, so a paid export can be opened again
instead of being lost when the person leaves the ready screen: a full 1080p film for seven days, a free
preview for 24 hours. `LocalCompletedExport` is now a shelf (index `shelf.json`) that holds the newest five
films, removes expired ones and their files whenever it is read, excludes them from backups, and migrates the
old single receipt once. A film that finished while the app was closed opens on the ready screen once
(`seen`), then lives on the shelf. The trips list shows a "My exports" entry; each film can be opened to
save, share or link again, or deleted. Leaving the ready screen only warns when the film is not on the shelf.

The privacy policy (in the app, `PRIVACY.md`, and `marketing-site/dist/privacy/index.html`, which is not
tracked here and must be deployed separately) now states this retention. Tests cover retention by quality,
the five-film cap, one-time opening, deletion and legacy migration; model tests run against an isolated shelf
so they can never write to a real one. Not yet verified on a physical iPhone.
