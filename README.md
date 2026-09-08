# TripReel for iOS

TripReel is a native SwiftUI app that turns detected photo trips into controllable travel films. It follows the supplied warm editorial design and includes the complete flow from photo access through trip selection, cutting, pacing, titles, music, export, and cleanup review.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer

## Run

Open `TripReel.xcodeproj`, select an iPhone simulator, and run the shared `TripReel` scheme.

On a normal launch, TripReel scans every non-hidden image available under the user's Full or Limited Photos permission (including bursts, synced photos, and Shared Albums), groups trips locally from capture dates and embedded locations, reverse-geocodes one representative coordinate per collection, and loads visible PhotoKit thumbnails on demand. iCloud-backed frames show live download progress, retry with a data fallback, prewarm upcoming montage frames, and retain a bounded in-memory cache. Montage playback now waits briefly for the active asset, holds the last real frame instead of cutting to an empty cloud tile, and skips that slide for the current loop if Photos still needs more time. Full-screen requests account for the source aspect ratio, fill crop, display scale, and motion overscan; a cached preview remains visible only while TripReel upgrades it to the required resolution. Limited access can only include the photos selected in Apple's permission UI. “Select photos instead” also works without broad library permission by copying only the chosen files into TripReel's private cache for the current editing session.

Before building a film, Smart Selection runs on the iPhone with Apple Vision. It combines Apple's screenshot subtype, image classification, OCR coverage (recognized text itself is not retained), face and person rectangles, attention saliency, document segmentation, feature prints, and iOS 18+ aesthetics. Human bounds take priority over generic saliency when choosing a starting frame, and photos containing people default to a fit-based treatment so faces and bodies near an edge remain visible. Screenshots do not make a photo collection qualify as a trip. High-confidence utility and very low-quality images are moved to a recoverable **More Photos** list and are never deleted. Whole-image feature prints are used conservatively for non-people moments only: a repeated event backdrop must never collapse photos of different people, because TripReel does not identify faces. Safe, readable collections of up to 36 photos stay complete; larger trips are shaped into a concise **First Cut** with day coverage, strong-memory protection, non-people near-duplicate suppression, and visual/category variety. This complete first version is created privately on-device and never requires cloud AI. Analysis automatically retries an iCloud thumbnail and then falls back to source-data delivery while decoding only a temporary 512 px copy. A Photos or Vision miss stays recoverable in **More Photos** but remains outside the active cut until a later retry can read it, so the first watch contains only working frames.

The analysis screen is an immersive live contact-sheet experience: the current photo, recent processed frames, changing Vision phase, and exact progress remain visible while First Cut is assembled. After watching it, the user chooses **Improve with AI**, **Edit Myself**, or **Looks Good**. Manual editing reuses the existing Film Studio. Improve with AI first asks for a creative direction, then shows explicit consent before any preview is prepared for transmission. A successful request creates a separate **AI Cut** while preserving First Cut; a local comparison lets the user preview either version, choose one, edit either one manually, or try another direction. Failure or cancellation always returns safely to First Cut. Export remains entirely local.

Motion uses one app-wide SwiftUI language: directional navigation preserves the user's sense of place, major regions reveal once with restrained springs, press and selection feedback stays tactile, live progress remains continuous, and background light drifts almost imperceptibly. Title typography arrives in a short hierarchy, music choices show a live level meter, and rendered films use eased camera paths plus 240 ms cross-dissolves instead of mechanical linear movement and hard cuts. Selecting a frame, camera move, film look, or motion intensity updates the existing preview without restarting the entire timeline; pinch and drag framing remain directly attached to the user's fingers. Reduce Motion replaces spatial and ambient movement with brief opacity transitions and stops every repeating animation.

Music preview is real and offline. TripReel bundles 90-second edited previews of Scott Buckley's organic cinematic tracks “Wanderlust,” “Simplicity,” “Castles in the Sky,” and “The Long Way Home,” all used under CC BY 4.0 with visible in-app attribution and full credits in `TripReel/Resources/Music/MUSIC-CREDITS.txt`. Playback uses an explicit movie-playback audio session and supports play/pause without a network request. Before encoding, export stages a temporary target-resolution copy of every selected frame, shows per-photo iCloud progress, retries transient PhotoKit misses, and falls back to downloading/decoding the source data. Encoding starts only after the complete local export set is ready; a final failure keeps all edits and offers a one-tap retry. Export then renders the photo-and-title timeline upright as a vertical H.264 MP4, applies the same eased motion and cross-dissolves shown in preview, loops the selected soundtrack across the finished film, and provides real Photos save and system share actions. The CapCut route now renders this compatible MP4 and shares it through an explicit MPEG-4 file representation so iOS can offer CapCut; because CapCut Mobile does not import CSV/FCPXML/EDL projects, the movie arrives as one flattened editable clip, with Save to Photos as the reliable fallback. Standard output is 720p with a prominent “Made with TripReel” watermark; HD is 1080p without one.

Trips currently need at least 15 photos across at least 18 hours and two calendar dates. A gap over 48 hours starts a new time window, repeated locations more than 120 km apart form separate destinations, and candidates longer than 45 days are rejected instead of becoming giant false trips. A location seen during at least eight weeks over 90 days is treated as habitual/home and filtered from multi-day trips. The same on-device evidence powers a lightweight **Trips / Nearby** segmented view. Nearby learns habitual places at neighborhood scale, treats a 4 km home area as a hard boundary, and groups at least six non-screenshot camera photos within a 5 km one-day outing. This keeps home photos in places such as Yishun out of a Marina Bay event while still attaching nearby photos without GPS. It shows at most the 20 newest results and prefers Apple-provided landmark or neighborhood labels over repeating a broad city name.

TripReel never deletes an original merely because it was cut from a film. Cleanup can delete only the cut PhotoKit assets a user explicitly selects, with individual toggles plus visible **Select all** and **Clear all** controls for large batches. The selected/total count remains visible, followed by both a clear TripReel destructive warning and Apple Photos' own system confirmation. Cancellation or an inaccessible item leaves the whole selection untouched; confirmed iCloud Photos deletion can propagate to synced devices.

Bundled travel photos are used only before permission is granted and by deterministic UI-test launches using `-qaScreen`.

## Optional AI Remix

Cloud AI is explicit opt-in and fail-closed. Choosing a creative direction performs no network work. Only after the user continues through consent does TripReel prepare up to 36 representative, reduced JPEG previews and send them with ephemeral `p0…` IDs. The candidate set is balanced between the local First Cut and safe, locally analyzed photos in **More Photos**, allowing the visual editor to rescue moments that conservative local ranking omitted. A `first_cut` or `more_photos` hint is sent as an advisory label; it contains no personal metadata. The request contains no EXIF, GPS, filenames, capture dates, or stable PhotoKit identifiers. Known screenshots, sensitive/document-like images, utility images, and assets that never completed local analysis remain blocked. The external model keeps a useful minimum share of materially different moments, then returns a strict plan containing selection, order, duration, editorial role, emphasis, and supported non-destructive motion. TripReel validates every reference and applies the decisions locally. Closing or declining consent means no upload.

TripReel and the reference proxy do not intentionally persist previews or edit plans and discard their in-memory copies after each foreground request. The proxy uses OpenAI Responses with `store: false`. This is not the same as Zero Data Retention: under OpenAI's default API controls, API content may be retained in abuse-monitoring logs for up to 30 days, or longer when legally or safety-required. ZDR removes that default storage for eligible organizations, but image inputs flagged by OpenAI's child-safety classifier may still be retained for manual review. API data is not used to train OpenAI models by default unless the organization opts in. The in-app disclosure states this distinction and links to [OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data).

The app and reference Worker include a production App Attest flow. On a supported physical iPhone, TripReel registers a Secure Enclave-backed App Attest key, obtains a fresh one-time challenge for every request, and signs the exact analysis body. The Worker validates Apple's certificate chain, the app identity, assertion signature, challenge, and monotonically increasing counter before it calls OpenAI. Replay state and quotas are kept in a narrowly scoped Cloudflare Durable Object; photo bytes, body hashes, Photos identifiers, and model results are never stored there.

The app points at `https://tripreel-visual-analysis.tripreel-prakashash18.workers.dev/v1/analyze`. This source revision validates every image and model response, disables request logging/storage, caps batches at 36 thumbnails and 128 KiB per thumbnail, and requests strict structured output with low-detail images, no reasoning, and `store: false`. The model defaults to `gpt-5.6-luna` but can be changed only through the Worker's validated `OPENAI_MODEL` setting. The matching Worker revision is deployed to the configured production endpoint; deploy tracked Worker changes again whenever this contract is updated.

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
