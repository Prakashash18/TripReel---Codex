# RevenueCat setup for Memories

The iOS app uses RevenueCat through Swift Package Manager and keeps purchase state in
`RevenueCatPurchaseService`. The native RevenueCat paywall and Customer Center are
presented from `PaywallScreen`.

## 1. Swift package

The Xcode project already includes:

- Package URL: `https://github.com/RevenueCat/purchases-ios-spm.git`
- Minimum version: `5.43.0`
- Products linked to the Memories target: `RevenueCat` and `RevenueCatUI`

If Xcode needs to refresh it, use **File > Packages > Resolve Package Versions**.

## 2. Test Store configuration

The Debug build is configured with the supplied `test_...` public SDK key. The key is
stored in the Debug build setting `REVENUECAT_PUBLIC_SDK_KEY`, not in Swift source.
Debug currently checks the RevenueCat entitlement `story_pass`.

In the RevenueCat dashboard for the Test Store app:

1. Create an entitlement with identifier `story_pass`.
2. Create these Test Store products:
   - `lifetime` — lifetime/non-renewing access
   - `yearly` — annual subscription
   - `monthly` — monthly subscription
3. Attach all three products to the `story_pass` entitlement.
4. Create an offering, normally `default`.
5. Add these packages to the offering:
   - Lifetime package -> product `lifetime`
   - Annual package -> product `yearly`
   - Monthly package -> product `monthly`
6. Make that offering the **Current Offering**.
7. In **Paywalls**, design and publish a paywall for the current offering.
8. In **Customer Center**, configure and publish the customer-management screen.

Prices and subscription periods shown by Memories come from RevenueCat/StoreKit, so
they automatically use the customer's App Store locale.

## 3. Production App Store configuration

Do not ship the Test Store key. The Release build deliberately has a blank
`REVENUECAT_PUBLIC_SDK_KEY` until the real iOS public key (`appl_...`) is added.

The product model currently separates two concepts:

- **Memories Pro**: renewable or lifetime access. Production entitlement:
  `memories_pro`.
- **Story Pass**: a consumable purchase that unlocks one specific story. It must not
  be attached to a permanent RevenueCat entitlement.

In App Store Connect:

1. Create `monthly` and `yearly` as auto-renewable subscriptions in the same
   subscription group.
2. Create `lifetime` as a non-consumable only if permanent Pro access is part of the
   intended business model.
3. Create the one-story Story Pass as a consumable with its own product identifier.
4. Complete prices, localization, tax category, review screenshot, review notes, and
   subscription disclosures.

In RevenueCat:

1. Add the App Store app and import the App Store Connect products.
2. Attach `monthly`, `yearly`, and (if offered) `lifetime` to `memories_pro`.
3. Do not attach the consumable Story Pass to an entitlement.
4. Put Pro products in the standard monthly, annual, and lifetime packages.
5. Put Story Pass in a custom offering package whose package identifier is
   `story_pass`.
6. Set the offering as current and publish the production paywall.
7. Copy the RevenueCat iOS **public SDK key** (`appl_...`) into the Release build
   setting `REVENUECAT_PUBLIC_SDK_KEY`.

Never place a RevenueCat secret key in the app. iOS must contain only the public SDK
key.

## 4. App lifecycle and customer information

`TripReelApp` owns one purchase service for the whole app:

```swift
@StateObject private var purchases = RevenueCatPurchaseService()

WindowGroup {
    RootView()
        .environmentObject(purchases)
        .task { await purchases.refresh() }
}
```

The service configures RevenueCat once, loads the current offering and customer
information concurrently, and listens for subsequent customer-info updates through
`PurchasesDelegate`.

The modern async customer-info call is:

```swift
let customerInfo = try await Purchases.shared.customerInfo()
let hasAccess = customerInfo.entitlements.active["story_pass"]?.isActive == true
```

In the app, use the observable state instead of making this call from every screen:

```swift
@EnvironmentObject private var purchases: RevenueCatPurchaseService

if purchases.isPremium {
    Text("Full export unlocked")
}
```

RevenueCat caches `CustomerInfo`; refreshing on launch, app foreground, purchase,
restore, and delegate updates is sufficient.

## 5. Purchasing and restoring

The custom Memories purchase UI uses the packages from the Current Offering:

```swift
Task {
    let unlocked = await purchases.purchase(
        package,
        unlockingStoryID: model.exportStoryID
    )
    if unlocked {
        model.resumePendingExportAfterPurchase()
    }
}
```

Restore access with:

```swift
Task {
    let restored = await purchases.restorePurchases()
    if restored {
        model.resumePendingExportAfterPurchase()
    }
}
```

The service handles cancellation, offline/store errors, pending family approval,
disabled purchases, unavailable products, configuration problems, and successful
customer-info updates. A cancelled purchase is never treated as an error or unlock.

## 6. RevenueCat Paywall

`PaywallScreen` offers **View all plans**, which presents the dashboard-driven native
paywall:

```swift
.sheet(isPresented: $showsRevenueCatPaywall) {
    PaywallView(displayCloseButton: true)
        .onPurchaseCompleted { transaction, customerInfo in
            purchases.handleRevenueCatUICompletion(
                customerInfo: customerInfo,
                purchasedProductIdentifier: transaction?.productIdentifier,
                storyID: model.exportStoryID
            )
        }
        .onRestoreCompleted { customerInfo in
            purchases.handleRevenueCatUICompletion(customerInfo: customerInfo)
        }
        .onPurchaseFailure { error in
            purchases.handleRevenueCatUIError(error, action: .purchasing)
        }
        .onRestoreFailure { error in
            purchases.handleRevenueCatUIError(error, action: .restoring)
        }
}
```

Because the paywall is dashboard-driven, product order, marketing copy, package
selection, and experiments can be changed without an app update.

## 7. Customer Center

Customer Center is useful after a renewable subscription is active. It lets customers
manage or cancel, restore purchases, and resolve common billing issues without a
custom support flow.

Memories shows **Manage subscription** to Pro customers and presents:

```swift
CustomerCenterView()
    .onCustomerCenterRestoreCompleted { customerInfo in
        purchases.handleRevenueCatUICompletion(customerInfo: customerInfo)
    }
    .onCustomerCenterRestoreFailed { error in
        purchases.handleRevenueCatUIError(error, action: .restoring)
    }
```

It does not need to be shown for a one-time consumable Story Pass.

## 8. Testing checklist

1. Run a Debug build and confirm RevenueCat logs show the Test Store app.
2. Confirm the current offering returns Lifetime, Yearly, and Monthly.
3. Buy each package with a fresh Test Store customer and verify `story_pass` becomes
   active.
4. Cancel a purchase and confirm the app remains locked with no charge message.
5. Restore a purchase and confirm access updates immediately.
6. Open **View all plans** and complete a purchase in the RevenueCat paywall.
7. Open **Manage subscription** and verify Customer Center loads.
8. Test offline, Ask to Buy/payment pending, and an empty offering.
9. Before TestFlight/App Store upload, add the production `appl_...` key and test the
   App Store products with an Apple sandbox tester.

The RevenueCat Test Store validates the app flow, but App Store sandbox testing is
still required before release.
