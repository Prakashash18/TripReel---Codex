# RevenueCat setup for Memories

Version 1 of Memories sells one product: a consumable **Story Pass** that unlocks
the selected memory's full-length 1080p export without a watermark. There are no
monthly, yearly, lifetime, or other subscription products in the launch offering.

## 1. Swift package

The Xcode project includes RevenueCat through Swift Package Manager:

- Package URL: `https://github.com/RevenueCat/purchases-ios-spm.git`
- Minimum version: `5.43.0`
- Product linked to the Memories target: `RevenueCat`

If Xcode needs to refresh it, use **File > Packages > Resolve Package Versions**.

## 2. App Store Connect

1. Create a consumable In-App Purchase for Story Pass.
2. Complete its display name, description, localized price, tax category, review
   screenshot, and review notes.
3. Do not create a subscription group for version 1.
4. If monthly, yearly, or lifetime products already exist, leave them unused and do
   not include them with the app version submitted for review.

## 3. RevenueCat

1. Add the App Store app and import the Story Pass product.
2. Do not attach Story Pass to an entitlement. Consumables must not grant permanent
   access.
3. Create an offering, normally `default`.
4. Add one custom package with identifier `story_pass` and attach the Story Pass
   product.
5. Remove every monthly, yearly, and lifetime package from the offering.
6. Make this the Current Offering.
7. Copy RevenueCat's iOS **public SDK key** (`appl_...`) into the Release build
   setting `REVENUECAT_PUBLIC_SDK_KEY`.

Never place a RevenueCat secret key in the app. iOS must contain only the public SDK
key. The price displayed by Memories is read from StoreKit through RevenueCat and is
automatically localized for the customer's App Store storefront.

## 4. Purchase behavior

`RevenueCatPurchaseService` loads only the custom Story Pass package. Subscription
or lifetime packages accidentally left in an older offering are ignored by the app.

After a successful purchase, Memories records the selected story ID locally and
resumes its pending full export. Re-editing and exporting that same story remains
unlocked on that device.

Story Pass is consumable, so it is not restored like a subscription or
non-consumable purchase. Version 1 has no Memories account or server-side story
ledger; deleting the app or moving to another device can therefore remove the local
per-story unlock. This limitation must remain clear in the purchase copy and support
documentation.

## 5. Testing checklist

1. Run a Debug build and confirm RevenueCat logs show the Test Store app.
2. Confirm the Current Offering returns exactly one custom `story_pass` package.
3. Confirm Monthly, Yearly, and Lifetime never appear in the purchase screen.
4. Buy Story Pass and verify the pending full export starts automatically.
5. Re-export the same story and verify it does not charge again.
6. Cancel a purchase and confirm the story remains locked and nothing is charged.
7. Test an unavailable product, offline connection, pending approval, and an empty
   offering.
8. Before App Store submission, add the production `appl_...` key and test the real
   Story Pass product with an Apple sandbox tester.

The RevenueCat Test Store validates the app flow, but App Store sandbox testing is
still required before release.
