# Memories for iOS

Memories is a native SwiftUI app that turns the photos that matter into a story. It follows a warm editorial design and includes the complete flow from photo-and-video access through moment grouping, cutting, pacing, titles, music, export, and cleanup review.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer

## Run

Open `TripReel.xcodeproj`, select an iPhone simulator, and run the shared `TripReel` scheme.

The App Store product is named **Memories: Create Stories**, with the subtitle **AI Reel & Slideshow Maker**. The concise on-device and Home Screen name remains **Memories**. The paid tier is **Memories Pro**. The existing Xcode project, scheme, source module, bundle identifier, and secure backend protocol retain their internal TripReel names so TestFlight history, signing, App Attest, and server compatibility remain intact. Set the App Store Connect listing name and RevenueCat/App Store Connect product display names separately; they are not controlled by the Xcode target name.

On first launch, Memories presents its animated brand story once, then asks for Photos access once. iOS persists that decision: returning users with Full or Limited access go directly to their stories, while users without access return to the setup choice. Memories scans every non-hidden photo and video available under the user's Full or Limited Photos permission (including bursts, synced media, and Shared Albums), groups memories locally from capture dates and embedded locations, reverse-geocodes one representative coordinate per collection, and loads visible PhotoKit previews on demand. iCloud-backed media shows live download progress and retries safely. Limited access can only include moments selected in Apple's permission UI. “Select moments instead” also works without broad library permission by copying only the chosen photo or video files into Memories' private cache for the current editing session.

Before building a film, Smart Selection runs on the iPhone with Apple Vision. Photos use Apple's screenshot subtype, image classification, OCR coverage (recognized text itself is not retained), face and person rectangles, attention saliency, document segmentation, feature prints, and iOS 18+ aesthetics. Videos are sampled at a bounded number of points; the same visual signals plus frame-to-frame change choose a clear 2–4 second source window while avoiding dead time, violent camera moves, and document-like footage. Clips remain distinct from still-image similarity groups, so a moving event moment is not discarded merely because its poster resembles a nearby photo. High-confidence utility and very low-quality media move to recoverable **More Moments** and are never deleted. The complete First Cut, including video trims, is created privately on-device and never requires cloud AI.

The same local signals now shape titles without generating claims about the user's life. Trip cards turn raw geocoder output into readable context such as “A week in Da Nang” or “An afternoon around Gardens by the Bay,” while keeping the precise place and dates visible below. A film receives a locally suggested intro, an optional ending for longer cuts, and a middle story beat anchored to a real day or visual-theme transition (people, events, food, coast, nature, or city). Every suggestion remains editable or removable, and both preview and export use the same anchored title timeline.

The analysis screen is an immersive live contact-sheet experience: the current photo, recent processed frames, changing Vision phase, and exact progress remain visible while First Cut is assembled. After watching it, the user chooses **Improve with AI**, **Edit Myself**, or **Looks Good**. Manual editing opens a vertical creator workspace with a live 9:16 canvas, draggable photo timeline, visible title and music tracks, and one-tap crop, text, music, style, and pace tools. Improve with AI first shows a short, explicit OpenAI sharing decision. Only after permission does the user choose the exact photos, an optional short story hint, and an on-device recommended reel recipe; no preview is prepared until they tap **Create AI cut**. A successful request creates a separate **AI Cut** while preserving First Cut. The director applies a story arc, editable opening, mid-film chapter and optional ending, one of Memories' bundled soundtracks, a visual treatment, pacing, order, and varied motion choreography. Its hook, chapter, and payoff can also become short text beats placed directly over the relevant photos; every line, placement, style, and entrance remains editable, and the same overlays appear in preview and export. The comparison plays the selected soundtrack and explains the director's concrete recommendations; the user can preview either version, adopt it, edit every applied choice, or try another direction. Failure or cancellation always returns safely to First Cut. Export remains entirely local.

Motion uses one app-wide SwiftUI language: directional navigation preserves the user's sense of place, major regions reveal once with restrained springs, press and selection feedback stays tactile, live progress remains continuous, and background light drifts almost imperceptibly. Title typography arrives in a short hierarchy, music choices show a live level meter, and rendered films use eased camera paths plus 240 ms cross-dissolves instead of mechanical linear movement and hard cuts. Selecting a frame, camera move, film look, or motion intensity updates the existing preview without restarting the entire timeline; pinch and drag framing remain directly attached to the user's fingers. Reduce Motion replaces spatial and ambient movement with brief opacity transitions and stops every repeating animation.

Music preview is real and offline. Memories bundles 90-second edited previews of Scott Buckley's organic cinematic tracks “Wanderlust,” “Simplicity,” “Castles in the Sky,” and “The Long Way Home,” all used under CC BY 4.0 with visible in-app attribution and full credits in `TripReel/Resources/Music/MUSIC-CREDITS.txt`. The live 9:16 preview plays selected video windows instead of frozen posters and lowers the soundtrack when source clips contain sound. Users can adjust each clip's source moment and length in Film Studio. Export renders the same mixed photo, video, title, and text timeline upright as a vertical H.264 MP4; original clip sound fades in locally while music ducks underneath it. Standard output is 720p with a prominent “Made with Memories” watermark; HD is 1080p without one.

Multi-day memories currently need at least 15 photos across at least 18 hours and two calendar dates. A gap over 48 hours starts a new time window, repeated locations more than 120 km apart form separate destinations, and candidates longer than 45 days are rejected instead of becoming giant false memories. A location seen during at least eight weeks over 90 days is treated as habitual/home and filtered from destination memories. The same on-device evidence powers an adaptive **Overseas / Local** view. The segmented control appears only when both categories contain results; when the library contains just one category, Memories removes the tabs and presents one calm list. Local detection learns habitual places at neighborhood scale, treats a 4 km home area as a hard boundary, and groups at least six non-screenshot camera photos within a 5 km one-day outing. This keeps home photos in places such as Yishun out of a Marina Bay memory while still attaching nearby photos without GPS. It shows at most the 20 newest results and prefers Apple-provided landmark or neighborhood labels over repeating a broad city name.

Memories never deletes an original merely because it was cut from a film. Cleanup can delete only the cut PhotoKit assets a user explicitly selects, with individual toggles plus visible **Select all** and **Clear all** controls for large batches. The selected/total count remains visible, followed by both a clear Memories destructive warning and Apple Photos' own system confirmation. Cancellation or an inaccessible item leaves the whole selection untouched; confirmed iCloud Photos deletion can propagate to synced devices.

Bundled travel photos are used only before permission is granted and by deterministic UI-test launches using `-qaScreen`.

## AI Director

Cloud AI is explicit opt-in and fail-closed. The app names OpenAI and GPT-5.6 Luna before asking permission. After accepting, the user can choose the exact eligible moments; Memories suggests a balanced set but never exceeds 36. Photos are sent as reduced JPEG previews. Each selected video is represented by one metadata-free, left-to-right contact sheet of three locally sampled frames, plus coarse duration, motion, and source-audio availability; original video bytes and audio never leave the iPhone. The AI Director can therefore interleave real clips and stills, vary pacing, select a soundtrack, and write editable hook/chapter/payoff text while all trimming, playback, audio mixing, and rendering remain local. It never sends exact dates, GPS, filenames, OCR text, faces, EXIF, or stable PhotoKit identifiers. Memories validates every field and reference, applies decisions locally, and keeps recommendations editable in Film Studio. Closing or declining consent means no upload.

Memories and the reference proxy do not intentionally persist previews or edit plans and discard their in-memory copies after each foreground request. The proxy uses OpenAI Responses with `store: false`. This is not the same as Zero Data Retention: under OpenAI's default API controls, API content may be retained in abuse-monitoring logs for up to 30 days, or longer when legally or safety-required. ZDR removes that default storage for eligible organizations, but image inputs flagged by OpenAI's child-safety classifier may still be retained for manual review. API data is not used to train OpenAI models by default unless the organization opts in. The in-app disclosure states this distinction and links to [OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data).

The app and reference Worker include a production App Attest flow. On a supported physical iPhone, Memories registers a Secure Enclave-backed App Attest key, obtains a fresh one-time challenge for every request, and signs the exact analysis body. The Worker validates Apple's certificate chain, the app identity, assertion signature, challenge, and monotonically increasing counter before it calls OpenAI. Replay state and quotas are kept in a narrowly scoped Cloudflare Durable Object; photo bytes, body hashes, Photos identifiers, and model results are never stored there.

The app points at `https://tripreel-visual-analysis.tripreel-prakashash18.workers.dev/v1/analyze`. This source revision validates every image and model response, disables request logging/storage, caps batches at 36 thumbnails and 128 KiB per thumbnail, and requests strict structured output with low-detail images, bounded reasoning for comparative direction, and `store: false`. The model defaults to `gpt-5.6-luna` but can be changed only through the Worker's validated `OPENAI_MODEL` setting. The matching Worker revision must be deployed to the configured production endpoint whenever this contract is updated.

After comparing First Cut and AI Cut, the result screen keeps the explanation compact: the film stays visible, concrete differences are split across three horizontally swipeable cards, and the current cut has distinct **Export** and **Edit** actions. The former experimental generated-video branch is retired; legacy Worker video routes return `410 feature_retired` without calling a provider.

Before building for TestFlight, enable the App Attest and In-App Purchase capabilities for the explicit App ID `com.prakashash18.tripreel` in the Apple Developer portal and allow Xcode Cloud to refresh the provisioning profile. Store `OPENAI_API_KEY` only as an encrypted Worker secret. Never embed it, `TRIPREEL_AUTH_TOKEN`, `APP_ATTEST_ROUTING_SECRET`, or any other long-lived backend secret in the app or Xcode build settings.

## RevenueCat and exports

Previewing and editing the complete reel are free. The free export is a separate 720p watermarked **Memory Preview**: an on-device planner selects three to five high-quality, relevant moments across the story and gives them brisk trailer pacing. A full-length 1080p export without a watermark can be unlocked once for that memory with a consumable Story Pass, or across all memories with Memories Pro. The pending export automatically resumes after a successful purchase or eligible restore.

Create a RevenueCat project for the iOS app, add products in App Store Connect, and put them in the current offering. Subscription products grant the entitlement `memories_pro`; the consumable Story Pass must not grant an entitlement. Add the **public iOS SDK key** as the `REVENUECAT_PUBLIC_SDK_KEY` build setting for the TripReel app target. RevenueCat's public SDK key is designed to ship in the app; never use a RevenueCat secret API key there. Prices and package periods are read from the current RevenueCat offering, so they stay localized and are not hard-coded in Swift.

Required dashboard setup before a TestFlight purchase test:

1. Create the subscription products and a consumable Story Pass product in App Store Connect; finish their price, localization, tax, and review metadata.
2. Connect the App Store app to RevenueCat. Attach only subscriptions to the `memories_pro` entitlement. Do not attach the consumable to an entitlement.
3. Put the products in RevenueCat's **current offering**. Use a custom package identifier of `story_pass` for the consumable. If you use another identifier, set `REVENUECAT_STORY_PASS_PACKAGE_ID` in the app target's Build Settings. The paywall prefers Story Pass, followed by annual Pro.
4. Copy RevenueCat's **public iOS SDK key** into the target's `REVENUECAT_PUBLIC_SDK_KEY` Build Setting for both Debug and Release, then commit that public value so Xcode Cloud receives it.
5. Upload a new TestFlight build. Purchases there use Apple's sandbox accounts; **Restore purchases** refreshes Pro subscriptions. Story Pass is a consumable and its per-memory unlock is retained locally on the purchasing device.

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
