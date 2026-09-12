# Memories Privacy Policy

Effective September 12, 2026

Memories turns the photos that matter into a story. This policy explains what the app processes and what happens when you optionally enable cloud photo intelligence.

## Photos, videos and memory detection

With Photos permission, Memories reads accessible photos and videos, capture dates, durations, and embedded locations to find meaningful moments, nearby outings, and build a film. Detection and grouping happen on your device. Memories uses Apple's system geocoder to turn one representative coordinate into a place name. Originals remain in Apple Photos unless you explicitly select cut moments in Cleanup, accept Memories' destructive warning, and approve Apple's system deletion prompt. With iCloud Photos, a confirmed deletion can affect other synced devices.

Photos or videos selected without broad library permission are copied temporarily into Memories' private on-device cache for the editing session.

## On-device visual intelligence

Apple Vision analyzes reduced photo thumbnails and a bounded set of sampled video frames on the iPhone for screenshots, document-like images, people, scenery, food, and visual quality. Memories compares sampled video frames to choose a useful 2–4 second source window, preferring clear people or scenic moments with usable motion over static, abrupt, or document-like sections. Recognized text itself is not retained. Moments omitted from an automatic cut remain recoverable under **More Moments** and can be restored.

## Optional OpenAI analysis

Memories creates a complete First Cut on-device without cloud AI. Only after the user chooses Improve with AI, selects a creative direction, and explicitly continues may selected reduced-resolution JPEG previews pass through Memories' secure backend to a configurable OpenAI image-capable model. A selected video is represented by a metadata-free three-frame contact sheet and coarse cues for clip duration, motion, and whether local source sound exists; the source video and audio are not uploaded. If the user writes or chooses an optional story hint, that short text is sent with the selected previews so titles and story structure can reflect the intended occasion. To compare its proposal with the existing film, Memories also sends a privacy-safe description of the First Cut and coarse on-device editorial cues: temporary sequence IDs, relative order and duration, frame and motion choices, title text, bundled soundtrack and style choices, relative day/time-gap bands, orientation, broad Vision scene categories, people counts, score bands, and temporary similarity groups. Memories does not send exact timestamps, GPS, filenames, recognized OCR text, faces, or stable Apple Photos identifiers. The thumbnail copies are re-encoded without EXIF or other embedded metadata. Known screenshots and sensitive or document-like images are blocked. OpenAI returns only a structured editorial plan and diagnosis, which Memories validates and applies locally without modifying original media. Memories' backend independently calculates the change counts shown in the comparison screen.

## Storage and deletion

Memories' backend does not intentionally persist cloud previews or edit plans and discards in-memory request copies after use. OpenAI is called with `store: false`.

Leaving a photo out of a film never deletes the original. Cleanup can request deletion only for cut Apple Photos assets the user individually selects. The request is batched atomically, requires a clear in-app warning and Apple's system confirmation, and is not made if any selected photo is unavailable. Imported picker copies and bundled demo images cannot be deleted from Apple Photos by Memories.

Under OpenAI's default API controls, OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Zero Data Retention removes default storage for eligible accounts, but images flagged by OpenAI's child-safety classifier may still be retained for manual review. OpenAI states that API data is not used to train its models by default unless the API organization opts in. See [OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data).

## Purchases

Apple processes in-app payments. RevenueCat receives an anonymous app user identifier and purchase or subscription status so Memories can unlock longer reels and HD export and restore eligible purchases. RevenueCat does not receive photos, reduced previews, finished films, titles, or location data from Memories.

## Identity, advertising, and tracking

Memories sends per-request placeholder IDs instead of Apple Photos identifiers. Cloud images are not used by Memories for advertising or cross-app tracking. Cloud AI requests are not linked to a Memories user profile.

## Your choices

Users can keep all photo analysis on-device or change the cloud choice from the **Cloud photo intelligence** card on the Trips screen. Turning cloud analysis off prevents future uploads. Revoking Photos access in iOS Settings stops further library access.

## Changes and contact

Material changes to this policy will be reflected here and in the app. Privacy questions can be submitted through [Memories support](https://github.com/Prakashash18/TripReel---Codex/issues).
