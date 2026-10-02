# Memories engagement and measurement

The app uses Firebase Analytics, In-App Messaging, and Remote Config 12.19.2. It uses the Analytics Core variant without IDFA support. The In-App Messaging SwiftPM product is named FirebaseInAppMessaging-Beta by Firebase. Supabase remains the backend.

## What ships

- First Cut starts/completions; AI Director and AI video requests/completions/failures/cancellations; AI edit acceptance/rejection; export starts/completions/failures/cancellations; distinct saved exports; share-sheet openings and created links; Story Pass funnel.
- `feature_used` with a categorical `feature` parameter, counted once per editing journey: music, atmosphere, title, title_style, selection, reorder, frame, motion, crop, duration, video_trim. This measures adoption, not every slider movement.
- Manual `screen_view` using fixed screen enum values. Automatic screen reporting is disabled.
- No custom media, account IDs, story text, links, precise locations, or raw errors in events. SDK identifiers and automatic metadata remain disclosed.
- Contextual dismissible guidance on First Cut options, at most once per 24 hours. Bundled default is save guidance. Remote Config selects `save`, `music`, or `none`; arbitrary remote strings cannot become app text.
- `help_tip_viewed`/`help_tip_dismissed` and subsequent events include the exposed `tip_variant`. First Cut starts clear the exposure context. Events after a new launch have no previous-session exposure attribution.
- Console In-App Messaging campaigns may display only on the trips/library screen. Use the `memories_library_ready` programmatic trigger and a once-per-campaign frequency. Never target `app_launch`. Contextual tips and these campaigns run on different screens.
- Apple review request after two distinct saved exports, on the finished-film screen, with a 120-day cooldown and at most one request per app version. StoreKit controls display. `review_requested` is not a rating or displayed-prompt measurement. This local eligibility does not require analytics.
- Existing device-local finished-export and one-day-before-expiry reminders remain intact. No OneSignal account, push campaign, paid service or new remote notification subscription is introduced.

## Consent and defaults

Share app analytics governs custom events, In-App Messaging collection, and Remote Config fetching. Turning it off suppresses messages, clears local tip exposure and stops new fetches; an already running request may finish. Collection starts disabled in Info.plist until the saved preference is applied. Ordinary Debug and XCTest launches skip Firebase; opt into DebugView with `-FIRDebugEnabled`. Disabling analytics does not erase previously collected server data.

## Console setup and rollout

Project: `getmemoriesapp---web`, GA4 property 557094680, iOS stream 15941433390.

1. The three parameters in `remote-config.template.json` were published as Remote Config version 1 on 2 October 2026. On later changes, merge into the existing template; do not overwrite unrelated parameters. The app has identical offline defaults. `memories_help_tips_enabled` and `memories_review_requests_enabled` are kill switches, applied after the next successful fetch (subject to SDK caching).
2. In GA4 create event-scoped custom dimensions for `feature` and `tip_variant`. Use Total users by feature for adoption, event counts for frequency, and a funnel of first_cut_started → first_cut_completed → export_started → export_completed → save_completed. Compare app versions and returning users. Never interpret share_sheet_opened as proof that a user shared.
3. Verify the release candidate on a test device with DebugView. Exercise opt-out/relaunch, success/failure/cancel paths, tips, nested sheets, and offline startup. Debug data must not be treated as production conversion data.
4. A console draft named “Memories — save reminder vs music tip” was prepared on 2 October 2026, with 5% exposure and save_completed as the goal. It remains pending publish and is not running; the Firebase tab retains the draft. For this Remote Config A/B experiment, use `memories_help_tip_variant`: baseline save, variant music (optionally a none control in a later experiment). Set `save_completed` as the primary objective; observe export failures and AI request volume. Restrict to the version containing this integration. Choose traffic allocation and minimum runtime based on actual traffic; do not declare a winner from a handful of events.
5. Once enough real traffic exists, use Remote Config Personalization on the same parameter and objective. Do not run personalization and an A/B test on the same parameter simultaneously. No model training is implied by bundling the SDK/template.
6. For a console messaging campaign, use the registered iOS app, trigger `memories_library_ready`, one impression per campaign, and the appropriate app-version audience. Suggested message: “Keep your favourite films” / “Videos in Memories are temporary. Save finished films to Photos to keep your own copy.” No AI generation is required. Verify with Firebase Test on Device before publishing.
7. Update App Store privacy labels and publish the matching policy with the signed app update. Analytics, messaging campaigns, experiments, and ML cannot be verified as live until that build runs and sends events. GA4 predictive audiences also require Google's eligibility thresholds; they are not enabled by these code changes.

AI event counts are a usage signal, not a billing ledger. Use the AI provider's usage reports for actual charges. Do not optimize for increased AI calls while the budget is limited.

## Verification

Unsigned iPhone Release build passed. Four targeted iPhone simulator tests passed: repeated-save deduplication, review cooldown/version persistence, daily tip limits including clock rollback, and remote-value allowlisting. Firebase event delivery, StoreKit presentation, and console campaigns still need device verification with the release candidate. No App Store upload/release or paid ad launch was performed.

## References

- https://firebase.google.com/docs/in-app-messaging/get-started?platform=ios
- https://firebase.google.com/docs/in-app-messaging/modify-message-behavior?platform=ios
- https://firebase.google.com/docs/remote-config/personalization
- https://support.google.com/analytics/answer/9846734
- https://developer.apple.com/documentation/storekit/requesting-app-store-reviews

## Toolchain-compatible package resolution

The app explicitly pins `swift-clocks` 1.0.6 and `xctest-dynamic-overlay` 1.11.0. These versions satisfy Supabase's requirements and keep the same dependency graph across Swift 6.3 and 6.4. Later versions (Clocks 1.1.1 and overlay 1.13.1) select a different Swift 6.4 manifest that introduces the separate `swift-issue-reporting` package. Resolving them on Swift 6.3 omits that package, causing a strict Xcode Cloud resolution failure. Adding the new package unconditionally is not compatible with the older toolchain because it duplicates the overlay's module names.

Keep these compatibility pins until upgrading and validating the local and cloud toolchains together. CI checks the committed lockfile with automatic resolution disabled before building. No Supabase, Firebase, or RevenueCat version change is required by this fix.
