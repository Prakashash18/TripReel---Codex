# TripReel for iOS

TripReel is a native SwiftUI prototype that turns a detected photo trip into a controllable travel film. It follows the supplied warm editorial design and includes the complete local flow from photo access through trip selection, cutting, pacing, titles, music, export, and cleanup review.

## Requirements

- Xcode 15 or newer
- iOS 17 or newer

## Run

Open `TripReel.xcodeproj`, select an iPhone simulator, and run the shared `TripReel` scheme.

The experience uses realistic bundled demo photos. Photo-library permission and the system photo picker are native, while trip detection and film rendering remain local prototype behavior.

For a physical iPhone, choose your Apple Development Team in Signing & Capabilities and change the placeholder `com.tripreel.app` bundle identifier if Xcode reports that it is unavailable.

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
