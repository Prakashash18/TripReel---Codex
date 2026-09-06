# TripReel for iOS

TripReel is a native SwiftUI app that turns detected photo trips into controllable travel films. It follows the supplied warm editorial design and includes the complete flow from photo access through trip selection, cutting, pacing, titles, music, export, and cleanup review.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer

## Run

Open `TripReel.xcodeproj`, select an iPhone simulator, and run the shared `TripReel` scheme.

On a normal launch, TripReel scans every non-hidden image available under the user's Full or Limited Photos permission (including bursts, synced photos, and Shared Albums), groups trips locally from capture dates and embedded locations, reverse-geocodes one representative coordinate per collection, and loads visible PhotoKit thumbnails on demand. iCloud-backed frames show live download progress, retry with a data fallback, prewarm upcoming montage frames, and retain a bounded in-memory cache so a slow cloud fetch does not become a permanent empty frame. Full-screen requests account for the source aspect ratio, fill crop, display scale, and motion overscan; a cached preview remains visible only while TripReel upgrades it to the required resolution. Limited access can only include the photos selected in Apple's permission UI. “Select photos instead” also works without broad library permission by copying only the chosen files into TripReel's private cache for the current editing session.

Before building a film, Smart Selection runs on the iPhone with Apple Vision. It combines Apple's screenshot subtype, image classification, OCR coverage (recognized text itself is not retained), faces, document segmentation, feature prints, and iOS 18+ aesthetics. Screenshots do not make a photo collection qualify as a trip. High-confidence utility and very low-quality images are moved to a recoverable **More Photos** list and are never deleted. Large trips are then shaped into a concise first cut with day coverage, strong-memory protection, near-duplicate suppression, and visual/category variety; 431 eligible photos produce roughly 64 highlights rather than a nearly nine-minute camera-roll replay. Temporary Photos, Vision, or cloud misses never interrupt first watch with an error alert: the working preview appears first, followed by an optional positive summary with category counts and a user-initiated **Check again now** action.

The analysis screen is an immersive live contact-sheet experience: the current photo, recent processed frames, changing Vision phase, and exact progress remain visible while the first cut is assembled. The same local analysis drives an editorial sequence rather than a plain timestamp slideshow: days stay in story order, while strong establishing shots open each day and the cut alternates scenery, people, food, orientation, and near-duplicates. The montage automatically chooses full-bleed, cinematic, portrait-matte, and postcard treatments, and alternates zoom-in, zoom-out, directional pan, rise, and settle motion. Portrait images are shown sharp and uncropped over a softened fill, so faces and the full composition remain visible. In Second Watch, users can choose Story, Cinema, Journal, or Clean and set motion to Still, Gentle, or Expressive. A focused per-photo editor adds pinch-to-zoom, drag-to-reframe, frame treatment, motion direction, and individual time-on-screen controls without turning the app into a crowded professional timeline. iOS Reduce Motion always wins.

Music preview is real and offline. TripReel bundles 90-second edited previews of Scott Buckley's organic cinematic tracks “Wanderlust,” “Simplicity,” “Castles in the Sky,” and “The Long Way Home,” all used under CC BY 4.0 with visible in-app attribution and full credits in `TripReel/Resources/Music/MUSIC-CREDITS.txt`. Playback uses an explicit movie-playback audio session and supports play/pause without a network request. Export now renders the photo-and-title timeline as a vertical H.264 MP4, loops the selected soundtrack across the finished film, and provides real Photos save and system share actions. Standard output is 720p with a watermark; HD is 1080p without one.

Trips currently need at least 15 photos across at least 18 hours and two calendar dates. A gap over 48 hours starts a new time window, repeated locations more than 120 km apart form separate destinations, and candidates longer than 45 days are rejected instead of becoming giant false trips. A location seen during at least eight weeks over 90 days is treated as habitual/home and filtered from multi-day trips. The same on-device evidence powers a lightweight **Trips / Nearby** segmented view. Nearby learns habitual places at neighborhood scale, treats a 4 km home area as a hard boundary, and groups at least six non-screenshot camera photos within a 5 km one-day outing. This keeps home photos in places such as Yishun out of a Marina Bay event while still attaching nearby photos without GPS. It shows at most the 20 newest results and prefers Apple-provided landmark or neighborhood labels over repeating a broad city name.

TripReel never deletes an original merely because it was cut from a film. Cleanup can delete only the cut PhotoKit assets a user explicitly selects, after both a clear TripReel destructive warning and Apple Photos' own system confirmation. Cancellation or an inaccessible item leaves the whole selection untouched; confirmed iCloud Photos deletion can propagate to synced devices.

Bundled travel photos are used only before permission is granted and by deterministic UI-test launches using `-qaScreen`.

## Optional GPT-5.6 Luna enhancement

Cloud visual analysis is explicit opt-in and fail-closed. Before the first possible upload, the app explains that some uncertain photos may be sent as reduced 512px JPEG thumbnail copies to TripReel's service and then to OpenAI's `gpt-5.6-luna`. The copies are re-encoded without EXIF, GPS, filenames, or stable PhotoKit identifiers. Known screenshots and sensitive/document-like images are blocked from cloud review. Closing or declining the consent screen means no upload.

TripReel and the reference proxy do not persist thumbnails and discard their in-memory copies after each foreground classification request. The proxy uses OpenAI Responses with `store: false`. This is not the same as Zero Data Retention: under OpenAI's default API controls, API content may be retained in abuse-monitoring logs for up to 30 days, or longer when legally or safety-required. ZDR removes that default storage for eligible organizations, but image inputs flagged by OpenAI's child-safety classifier may still be retained for manual review. API data is not used to train OpenAI models by default unless the organization opts in. The in-app disclosure states this distinction and links to [OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data).

The app and reference Worker include a production App Attest flow. On a supported physical iPhone, TripReel registers a Secure Enclave-backed App Attest key, obtains a fresh one-time challenge for every request, and signs the exact analysis body. The Worker validates Apple's certificate chain, the app identity, assertion signature, challenge, and monotonically increasing counter before it calls OpenAI. Replay state and quotas are kept in a narrowly scoped Cloudflare Durable Object; photo bytes, body hashes, Photos identifiers, and model results are never stored there.

The Worker is deployed at `https://tripreel-visual-analysis.tripreel-prakashash18.workers.dev/v1/analyze`, and that public, non-secret endpoint is configured in both app build configurations. It validates every image and model response, disables request logging/storage, caps batches at 12 thumbnails and 256 KiB per thumbnail, and calls exactly `gpt-5.6-luna` with low-detail images, no reasoning, strict structured output, and `store: false`.

Before building for TestFlight, enable the App Attest capability for the explicit App ID `com.prakashash18.tripreel` in the Apple Developer portal and allow Xcode Cloud to refresh the provisioning profile. Never embed `OPENAI_API_KEY`, `TRIPREEL_AUTH_TOKEN`, `APP_ATTEST_ROUTING_SECRET`, or any other long-lived shared secret in the app or Xcode build settings.

For a local Debug smoke test only, `TRIPREEL_DEVELOPMENT_AUTH_TOKEN` may be set in an unshared Xcode Run environment. It must match the Worker's development bearer token and is read at runtime; it is never available in Release/TestFlight builds. Without that local override, a Debug build on a supported physical iPhone uses App Attest too. Debug may override `TRIPREEL_PHOTO_ANALYSIS_ENDPOINT` at runtime when testing another deployment.

Before enabling the cloud option for testers, publish [`PRIVACY.md`](PRIVACY.md), use its public URL for App Store Connect, update the App Privacy answers for the deployed data flow, and verify the disclosure against the backend's actual logging and OpenAI retention configuration.

For a physical iPhone, keep the configured Apple Development Team in Signing & Capabilities and make sure the `com.prakashash18.tripreel` bundle identifier belongs to that team.

## Test

Run the unit and end-to-end UI suite on an installed simulator:

```sh
xcodebuild -project TripReel.xcodeproj \
  -scheme TripReel \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -derivedDataPath /tmp/TripReelTestDerivedData \
  test
```

Validate the backend without making a network request:

```sh
cd Backend
npm test
```

Instrument Serif is bundled under the SIL Open Font License; its license is included in `TripReel/Resources/Fonts`.

## Recreate the Xcode project

The checked-in project is ready to use. If source files are added, regenerate it with:

```sh
ruby scripts/generate_project.rb
```
