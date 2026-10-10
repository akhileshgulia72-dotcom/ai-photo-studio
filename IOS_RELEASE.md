# VYRO iOS release guide

Everything in this document reflects the current state of the repository. Each
blocker that needs an Apple, AdMob, or Firebase account action is marked
**[ACTION REQUIRED]** with the exact secret name and value format.

---

## 1. What is already configured

| Item | Value |
|---|---|
| Bundle identifier | `com.agdevelops.ainotescanner` |
| iOS deployment target | `15.0` |
| Swift version | `5.0` |
| Xcode project | `ios/Runner.xcodeproj` |
| Workspace | `ios/Runner.xcworkspace` |
| Scheme | `Runner` |
| CocoaPods | Required (`ios/Podfile` committed), SPM disabled for iOS |
| Flutter version | `3.44.2` (Dart `3.12.2`) |
| Version / build | `1.0.0+22` from `pubspec.yaml`; TestFlight workflow supplies its run number |
| Display name | `AI Photo Studio` (from `Info.plist`) |
| Production backend | `https://vyro-api-jnz6yqjl4a-el.a.run.app` |
| Firebase init | `lib/firebase_options.dart` via `Firebase.initializeApp(options:)` |
| iOS AdMob app id | `ca-app-pub-7694497723149363~7064149443` (in `Info.plist`) |

### AdMob ids

The app id is configured once in `ios/Runner/Info.plist` as
`GADApplicationIdentifier`. Ad **unit** ids are selected per platform in Dart, so
Android keeps its original units and iOS uses its own.

| Format | Android | iOS |
|---|---|---|
| Rewarded | `ca-app-pub-7694497723149363/9751807400` | `ca-app-pub-7694497723149363/8453252739` |
| Interstitial | `ca-app-pub-7694497723149363/7630322351` | `ca-app-pub-7694497723149363/8336693504` |
| Native | `ca-app-pub-7694497723149363/6374835026` | `ca-app-pub-7694497723149363/7462595539` |
| App id | `ca-app-pub-7694497723149363~1446706318` | `ca-app-pub-7694497723149363~7064149443` |

Source of truth:

- `lib/services/ad_unit_config.dart` — platform-specific IDs for rewarded,
  interstitial, and native formats, plus the opt-in demo-unit switch

The iOS TestFlight workflow explicitly opts into Google's official demo ad
units so ad loading and rendering can be validated before live ads are approved.
Normal builds continue to use production units unless they pass
`--dart-define=ADMOB_USE_TEST_ADS=true`.

Selection uses `defaultTargetPlatform == TargetPlatform.iOS`, so non-Apple
platforms keep the Android units. `test/ad_unit_ids_test.dart` asserts this
mapping for both platforms.

### Why the deployment target is 15.0

Every Firebase iOS plugin in this project declares `ios.deployment_target = '15.0'`:

- `firebase_core` 4.14.0, `firebase_auth` 6.6.1, `cloud_firestore` 6.9.0,
  `firebase_storage` 13.6.0, `firebase_app_check` 0.4.7

The project previously targeted `13.0`, which **fails to build**. `15.0` is the
minimum that satisfies the dependency graph. `ios/Podfile` pins the same value,
and the two must stay in step.

---

## 2. GitHub Actions workflow

Path: **`.github/workflows/ios-release.yml`**

Triggers:

- `push` to `main` / `master`
- tags matching `v*`
- pull requests to `main` / `master`
- manual `workflow_dispatch` (with an `upload_to_testflight` toggle)

Runner: `macos-15`, with the newest installed Xcode selected. Timeout 90 minutes.

Step order:

1. Checkout
2. Select newest available Xcode
3. Set up Flutter `3.44.2` (cached)
4. `flutter pub get`
5. Verify `lib/firebase_options.dart` exists
6. **Preflight** — detects which credentials exist and sets `signing` and
   `can_upload`
7. Verify the iOS AdMob application id in `Info.plist` belongs to the VYRO
   account and is not the Android id
8. Validate the iOS OAuth IDs, URL scheme, and Firebase options
9. `flutter test`
10. `flutter analyze`
11. Import the signing certificate and provisioning profile (only when signing is configured)
12. `pod repo update && pod install`
13. Build:
    - signed → `flutter build ipa --release` with `ios/ExportOptions.plist`
    - unsigned → `flutter build ios --release --no-codesign`
14. Confirm `GENERATION_API_BASE_URL` is not the `v2fixed` test revision
15. Upload artefacts (`.app` or `.ipa`)
16. Upload to TestFlight (only when signing and the App Store Connect key are present)
17. Delete the temporary keychain

Both build paths pass:

```
--build-name=1.0.0
--build-number=<github.run_number>
--dart-define=GENERATION_API_BASE_URL=https://vyro-api-jnz6yqjl4a-el.a.run.app
```

The build number comes from the workflow run number so every TestFlight upload is
unique without manual edits.

---

## 3. GitHub Secrets

Add these under **Settings → Secrets and variables → Actions → New repository secret**.

### Required for a TestFlight upload

| Secret | Format | Why |
|---|---|---|
| `IOS_CERTIFICATE_BASE64` | base64 of an Apple **Distribution** `.p12` | Signs the archive. |
| `IOS_CERTIFICATE_PASSWORD` | the `.p12` export password | Unlocks the certificate. |
| `IOS_PROVISIONING_PROFILE_BASE64` | base64 of an **App Store** `.mobileprovision` | Must match `com.agdevelops.ainotescanner`. |
| `KEYCHAIN_PASSWORD` | any strong random string | Password for the throwaway CI keychain. |
| `APP_STORE_CONNECT_KEY_ID` | e.g. `2X9ABCD3EF` | App Store Connect API key id. |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID, e.g. `69a6de7e-...` | API key issuer id. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | full text of `AuthKey_XXXX.p8` **including** the `-----BEGIN PRIVATE KEY-----` lines | Authenticates the upload. |

> The iOS AdMob application id is **not** a secret. It is committed in
> `ios/Runner/Info.plist` as `GADApplicationIdentifier`
> (`ca-app-pub-7694497723149363~7064149443`), which is how the Google Mobile Ads
> SDK expects to find it. The workflow verifies it rather than injecting it.

### Optional repository variable

| Variable | Default | Why |
|---|---|---|
| `GENERATION_API_BASE_URL` | `https://vyro-api-jnz6yqjl4a-el.a.run.app` | Override to point a run at the `v2fixed` test revision. Never leave a test value here for a release. |

---

## 4. How to run it

**Automatic:** push to `main`, or push a tag such as `v1.0.0`.

**Manual:** GitHub → Actions → **iOS Release** → *Run workflow*. Leave
`upload_to_testflight` checked to also upload.

**What happens without secrets:** the workflow still runs `flutter test`,
`flutter analyze`, and an unsigned `flutter build ios --release`, then uploads
`Runner.app` as an artefact. It emits a warning that the build must not be
distributed. This makes pull-request runs meaningful before the Apple account is
ready.

---

## 5. Local verification on a Mac

```sh
flutter clean
flutter pub get
flutter analyze
flutter test

cd ios
pod repo update
pod install
cd ..

# Compile-only check, no Apple account needed:
flutter build ios --release --no-codesign \
  --build-name=1.0.0 \
  --build-number=17 \
  --dart-define=GENERATION_API_BASE_URL=https://vyro-api-jnz6yqjl4a-el.a.run.app
```

Expected artifact: `build/ios/iphoneos/Runner.app`

To also verify the production URL really landed in the binary:

```sh
strings build/ios/iphoneos/Runner.app/Frameworks/App.framework/App | grep -c "vyro-api-jnz6yqjl4a"
```

Then, with signing configured in Xcode:

```sh
open ios/Runner.xcworkspace
# Product → Archive → Distribute App → App Store Connect → Upload
```

---

## 6. TestFlight upload steps

1. Create the app record in App Store Connect with bundle id
   `com.agdevelops.ainotescanner`.
2. Add all required secrets listed in section 3.
3. Push to `main` (or run the workflow manually with upload enabled).
4. Watch the **Upload to TestFlight** step. A successful upload prints
   `Uploaded to App Store Connect`.
5. Wait 5–15 minutes for processing, then the build appears under
   TestFlight → Builds.
6. Complete **Export Compliance** if prompted (already answered by
   `ITSAppUsesNonExemptEncryption = false` in `Info.plist`).
7. Add the build to a tester group.

---

## 7. [ACTION REQUIRED] Manual steps outside this repository

### 7.1 iOS AdMob — code configured; account approval must be checked

The iOS AdMob app and ad units are configured and wired in:

- App id `ca-app-pub-7694497723149363~7064149443` → `ios/Runner/Info.plist`
- Rewarded `…/8453252739`, Interstitial `…/8336693504`, Native `…/7462595539`
  → selected per platform in Dart (see section 1)

The app id and platform-specific units are wired in code. Ad serving status is
controlled by the AdMob account, not this repository. If the app dashboard says
**Requires review**, complete app verification/app-ads.txt and the app readiness
review; the app may not fully serve live ads until AdMob marks it ready. Confirm
the rewarded unit amount is **5** with item name **credits**, matching
`AD_REWARD_CREDITS = 5` on the backend.

### 7.2 Firebase and Google provider

The local `GoogleService-Info.plist`, `lib/firebase_options.dart`, and Xcode
Runner target agree on Firebase project `ai-note-scanner` and bundle ID
`com.agdevelops.ainotescanner`. `firebase.json` now points at the same iOS app
ID as the runtime options. Google Sign-In OAuth IDs are passed explicitly in
Dart; the reversed client ID URL scheme is in `ios/Runner/Info.plist`.

The enabled state of the Google provider is stored in Firebase Console and
cannot be verified from this repository. Android Google Sign-In is reported to
work for this project; if iOS still fails after this build, capture the safe
`AuthService` stage/code log and confirm the Google provider remains enabled in
Firebase Authentication.

### 7.3 GoogleService-Info.plist

This file is intentionally gitignored. VYRO initializes Firebase from
`lib/firebase_options.dart` and passes the iOS OAuth client ID plus the Web
server client ID directly to `google_sign_in` in `AuthService`. The required
reversed-client-ID URL scheme is committed in `ios/Runner/Info.plist`. The
release build therefore does not depend on a local copy of this plist.

### 7.4 App Store Connect app record and in-app purchase

**[ACTION REQUIRED]** Create the app record, then create the premium products
that the Android build already sells. The product ids live in
`lib/screens/premium_screen.dart` and `backend/purchase_policy.py`; use exactly
those ids — do not invent new ones. An iOS build cannot sell a product that does
not exist in App Store Connect.

Apple IAP verification is intentionally not implemented on the backend; see
`backend/ENVIRONMENT.md`. The client does not complete iOS purchases until a
server-side Apple verification path exists, so **premium purchases will not work
on iOS** until that endpoint is added. This is a pre-existing product decision,
not a build blocker.

### 7.5 Signing certificate and profile

Create an Apple **Distribution** certificate and an **App Store** provisioning
profile for `com.agdevelops.ainotescanner` (or an App Store Connect API key with
sufficient role), then base64 them into the secrets above.

---

## 8. Notes and known limitations

- **App Tracking Transparency.** `NSUserTrackingUsageDescription` is present in
  `Info.plist`, but the app does not call `ATTrackingManager` anywhere (there is
  no `app_tracking_transparency` dependency). AdMob uses the description for its
  own attribution. To actually obtain the IDFA opt-in, a native ATT request is
  needed — a behavioural change that was deliberately not made here.
- **Android is unchanged.** No Android file was modified, and all Android AdMob
  ids are byte-identical to their previous values. `test/ad_unit_ids_test.dart`
  asserts this. The backend was not modified.
- **`v2fixed` default URL.** `lib/services/api_config.dart` still defaults to the
  test revision. Every iOS release build overrides it with
  `--dart-define=GENERATION_API_BASE_URL=…`, and the workflow fails if the value
  contains `v2fixed`. The default was **not** changed because it is shared with
  the working Android build and the same risk applies there.
  **[ACTION REQUIRED]** Confirm your Android release command also passes the
  production URL, otherwise the Play Store build points at the test revision.
- **Excluded from the repository by `.gitignore`:** `*.p12`, `*.mobileprovision`,
  `AuthKey_*.p8`, `ios/Runner/GoogleService-Info.plist`, `ios/key.properties`.
- **Not verifiable on this machine.** iOS builds require macOS and Xcode. The
  workflow, plists and Xcode project were validated for syntax and consistency
  (YAML parsed, plists parsed as XML, deployment target and bundle id unified),
  but `flutter build ios` itself has not been executed. The first GitHub Actions
  run is the real compile check.
