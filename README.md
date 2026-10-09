# AI Photo Studio

A premium, template-first Flutter app for transforming portraits. The first client flow includes template discovery, template details, camera/gallery selection, backend generation states, a result screen, and a session gallery.

## Run the app

```sh
flutter pub get
flutter run
```

Firebase initialization and anonymous authentication run after the first frame. Existing Firebase project configuration is preserved.

## Secure image-generation backend

The Flutter app contains no image-provider secret. To enable generation, deploy a backend and start the app with:

```sh
flutter run --dart-define=GENERATION_API_BASE_URL=https://vyro-api-jnz6yqjl4a-el.a.run.app
```

The client sends `POST /v1/generations` as multipart form data with fields `templateId`, `prompt`, and `negativePrompt`, an `image` file, and the Firebase ID token in `Authorization: Bearer ...`. A successful backend response must include `outputImageUrl`.

The FastAPI backend is in `backend/` and is designed for Cloud Run in the same Google Cloud project as Firebase. It validates Firebase ID tokens, manages credits, stores generated images in private Firebase Storage, and records generation metadata in Firestore. Keep provider keys in Secret Manager. The app defaults to `https://vyro-api-jnz6yqjl4a-el.a.run.app`; override it with `--dart-define=GENERATION_API_BASE_URL=...` only when the service URL changes.


## Release ad configuration

The AdMob app and production ad unit IDs are configured in the repository and
selected by platform. To exercise Google's official demo ads in a debug build,
pass `--dart-define=ADMOB_USE_TEST_ADS=true`. The switch is ignored in release
builds. The iOS demo IDs cover rewarded, interstitial, and native ads.

```sh
flutter run --debug --dart-define=ADMOB_USE_TEST_ADS=true
```

Ad entitlement lookup fails closed, so ads are hidden when the paid plan cannot
be verified. Live ad serving also depends on the app's AdMob verification and
readiness status.

## iOS

See [IOS_RELEASE.md](IOS_RELEASE.md) for the full iOS build, signing, and TestFlight guide, including the exact GitHub Secrets required.

| Item | Value |
|---|---|
| Bundle identifier | `com.agdevelops.ainotescanner` |
| iOS deployment target | `15.0` |
| Workflow | `.github/workflows/ios-release.yml` |
| Runner | `macos-15` |
| Flutter | `3.44.2` |
| Production backend | `https://vyro-api-jnz6yqjl4a-el.a.run.app` |

```sh
# Production iOS build (on macOS):
flutter build ipa --release \
  --dart-define=GENERATION_API_BASE_URL=https://vyro-api-jnz6yqjl4a-el.a.run.app
```

Push to `main`, push a `v*` tag, or run the **iOS Release** workflow manually to build and (when signing credentials are configured) upload to TestFlight.

The iOS AdMob app id lives in `Info.plist`; ad unit ids are chosen per platform in Dart, so Android keeps its existing units:

| Format | Android | iOS |
|---|---|---|
| Rewarded | `…/9751807400` | `…/8453252739` |
| Interstitial | `…/7630322351` | `…/8336693504` |
| Native | `…/6374835026` | `…/7462595539` |

Remaining release items are Apple signing credentials and the App Store Connect
in-app purchase products. Confirm the Google provider is enabled in Firebase
Authentication. See [IOS_RELEASE.md](IOS_RELEASE.md) section 7.

