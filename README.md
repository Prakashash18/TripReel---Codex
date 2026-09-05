# TripReel for iOS

TripReel is a native SwiftUI app that turns detected photo trips into controllable travel films. It follows the supplied warm editorial design and includes the complete flow from photo access through trip selection, cutting, pacing, titles, music, export, and cleanup review.

## Requirements

- Xcode 15 or newer
- iOS 17 or newer

## Run

Open `TripReel.xcodeproj`, select an iPhone simulator, and run the shared `TripReel` scheme.

On a normal launch, TripReel scans every non-hidden image available under the user's Full or Limited Photos permission (including bursts, synced photos, and Shared Albums), groups trips locally from capture dates and embedded locations, reverse-geocodes one representative coordinate per trip, and loads visible PhotoKit thumbnails on demand. iCloud-backed thumbnails are network-enabled. Limited access can only include the photos selected in Apple's permission UI. “Select photos instead” also works without broad library permission by copying only the chosen files into TripReel's private cache for the current editing session.

Trips currently need at least 15 photos across at least 18 hours and two calendar dates. A gap over 48 hours starts a new time window, repeated locations more than 120 km apart form separate destinations, and candidates longer than 45 days are rejected instead of becoming giant false trips. A location seen during at least eight weeks over 90 days is treated as habitual/home and filtered from trip results. The final video-render/save actions remain prototype simulations; the app never deletes originals.

Bundled travel photos are used only before permission is granted and by deterministic UI-test launches using `-qaScreen`.

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

Instrument Serif is bundled under the SIL Open Font License; its license is included in `TripReel/Resources/Fonts`.

## Recreate the Xcode project

The checked-in project is ready to use. If source files are added, regenerate it with:

```sh
ruby scripts/generate_project.rb
```
