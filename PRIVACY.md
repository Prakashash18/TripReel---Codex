# TripReel Privacy Policy

Effective September 5, 2026

TripReel turns photos you choose or make accessible into travel films. This policy explains what the app processes and what happens when you optionally enable cloud photo intelligence.

## Photos and trip detection

With Photos permission, TripReel reads accessible images, capture dates, and embedded locations to find trips and build a film. Trip detection and grouping happen on your device. TripReel uses Apple's system geocoder to turn one representative coordinate into a place name. Originals remain in Apple Photos, and TripReel does not delete them.

Photos selected without broad library permission are copied temporarily into TripReel's private on-device cache for the editing session.

## On-device visual intelligence

Apple Vision analyzes reduced images on the iPhone for screenshots, document-like images, people, scenery, food, and visual quality. Recognized text itself is not retained. Photos omitted from an automatic cut remain recoverable under **More Photos** and can be restored.

## Optional OpenAI analysis

Cloud enhancement is off until the user explicitly enables it. When enabled, only uncertain reduced-resolution JPEG thumbnail copies may pass through TripReel's secure backend to OpenAI's GPT-5.6 Luna. TripReel re-encodes the copies without EXIF, GPS, filenames, or stable Apple Photos identifiers. Known screenshots and sensitive or document-like images are blocked from cloud review. The purpose is solely to improve automatic film selection.

## Storage and deletion

TripReel's backend does not persist cloud thumbnails or classification results and discards its in-memory copies after each request. OpenAI is called with `store: false`.

Under OpenAI's default API controls, OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Zero Data Retention removes default storage for eligible accounts, but images flagged by OpenAI's child-safety classifier may still be retained for manual review. OpenAI states that API data is not used to train its models by default unless the API organization opts in. See [OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data).

## Identity, advertising, and tracking

TripReel sends per-request placeholder IDs instead of Apple Photos identifiers. Cloud thumbnails are not used for advertising or cross-app tracking. The cloud photo request is not linked to a TripReel user profile.

## Your choices

Users can keep all photo analysis on-device or change the cloud choice from the **Cloud photo intelligence** card on the Trips screen. Turning cloud analysis off prevents future uploads. Revoking Photos access in iOS Settings stops further library access.

## Changes and contact

Material changes to this policy will be reflected here and in the app. Privacy questions can be submitted through [TripReel support](https://github.com/Prakashash18/TripReel---Codex/issues).
