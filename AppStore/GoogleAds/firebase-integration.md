# Firebase install measurement — 2 October 2026

## Configured

- Firebase project: `getmemoriesapp---web` (262765004634).
- GA4 property: GetMemoriesApp - Web (557094680), iOS stream 15941433390.
- Firebase app: `1:262765004634:ios:37c2940bac2738176d1563`.
- iOS bundle: `com.prakashash18.tripreel`; App Store ID 6808904703 saved in Firebase.
- Firebase Analytics enabled in the Firebase integrations screen.
- Firebase SDK pinned to 12.19.2, using FirebaseAnalyticsCore without advertising-ID support.
- Existing package versions preserved. Supabase continues handling the backend and accounts.
- Firebase configuration bundled in app resources; initialization uses the SwiftUI application delegate.
- Release builds collect automatic events. Normal debug launches and XCTest runs skip Firebase; use `-FIRDebugEnabled` deliberately for DebugView testing.
- Feature and journey events are documented in `firebase/ENGAGEMENT.md`. No media, story text, account IDs or email fields are attached. IDFV, automatic screen reporting and ad-personalization signals disabled. SDK automatic purchase events may include product IDs and prices.
- App Privacy Policy includes Share app analytics. Disabling stops collection and resets local analytics data; it does not delete historical server data.
- Local policy and privacy manifest updated. Website policy edits are local and not deployed.

## Verification and release gates

The unsigned iPhone Release build passed. Configuration plist and privacy manifest validate. This is compile-time verification, not proof that Firebase received live events.

Before publishing the app update:
1. Run a Debug build on a test iPhone with `-FIRDebugEnabled`; verify first_open/session events in this Firebase project's DebugView. Confirm no personal media or story content appears in event parameters.
2. Test Share app analytics off, relaunch, and verify collection remains off. Re-enable and verify events resume. Debug events must not count toward paid campaign results.
3. Review App Store Connect privacy labels for the full app and SDK configuration. New analytics declarations include app-instance/device identifier, approximate location, usage and purchase events. They are conservatively declared linked to a device in the local manifest. Google Ads sharing and tracking classifications must reflect the final account settings.
4. Publish the matching privacy policy, upload a signed build, and release it through App Store Connect. No upload, submission or release was performed in this task.
5. Link the intended Google Ads account (896-826-6684), keeping personalized advertising disabled, and import the iOS first_open conversion. Verify the conversion is available before launching install ads.
6. Revisit campaign dates. Preserve SGD100 total including tax/fees and the requested non-European targeting. No ad campaign has been launched.

The legacy scripts/generate_project.rb is already out of sync with the checked-in project (including older Ads dependencies). Do not regenerate this project from that script without reconciling it; the checked-in Xcode project contains the validated integration.

## References

- [Firebase iOS Analytics setup](https://firebase.google.com/docs/analytics/ios/get-started)
- [Analytics collection controls](https://firebase.google.com/docs/analytics/ios/configure-data-collection)
- [Google Analytics App Store disclosures](https://support.google.com/analytics/answer/10285841)
