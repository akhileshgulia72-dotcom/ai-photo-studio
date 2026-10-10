# VYRO production backend configuration

Keep these values server-side. Never put service-account JSON, OpenAI keys, or Apple private keys in Flutter.

Required existing variables:
- OPENAI_API_KEY
- FIREBASE_SERVICE_ACCOUNT_JSON
- FIREBASE_STORAGE_BUCKET

Recommended:
- OPENAI_MODEL=gpt-image-2.5-sunburst
- OPENAI_SIZE=1024x1536
- OPENAI_TIMEOUT=240
- MAX_UPLOAD_MB=20
- REWARDED_AD_UNIT_ID=ca-app-pub-7694497723149363/4824354140
- ENABLE_TEST_OUTPUT=false

Google Play purchase verification:
- ANDROID_PACKAGE_NAME=<your real Android applicationId>
- GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=<path to a Google Play API service-account JSON file>

The Google service account must have the required Play Console/API permissions for purchase verification.

AdMob SSV:
- In AdMob, configure the rewarded ad unit's server-side verification callback URL as:
  https://YOUR_CLOUD_RUN_HOST/v1/rewards/admob-ssv
- Set the reward amount in AdMob to 5 and the reward item to a stable value such as credits.
- The backend independently enforces AD_REWARD_CREDITS=5.

Apple IAP:
The backend exposes `/v1/iap/apple/verify` and fails closed until all of the
following are configured server-side. Store the private key in Secret Manager;
never put it in Flutter or a committed `.env` file.

- `APPLE_APP_ID`: numeric App Store Connect Apple ID for this app (required for
  production signed-data verification).
- `APPLE_IAP_BUNDLE_ID=com.agdevelops.ainotescanner`.
- `APPLE_IAP_KEY_ID`: key ID for an App Store Connect In-App Purchase key.
- `APPLE_IAP_ISSUER_ID`: issuer ID shown with that key.
- `APPLE_IAP_PRIVATE_KEY`: the downloaded `.p8` private key, injected from
  Secret Manager.
- `APPLE_ROOT_CERTIFICATES_B64`: comma-separated Base64 DER bytes for Apple's
  current App Store root certificates from Apple PKI.
- `APPLE_IAP_SANDBOX_UID_ALLOWLIST`: comma-separated Firebase UIDs allowed to
  receive sandbox/TestFlight credit grants. Leave empty outside a controlled
  test. Sandbox transactions are otherwise rejected.

The endpoint verifies the submitted JWS using Apple's Python App Store Server
Library, looks up and verifies Apple's current transaction status, checks app,
product, consumable type, revocation, quantity, and the UID-bound app account
token, then grants credits with an atomic Firestore transaction. The
transaction record is idempotent across retries and app restarts. No Apple
credential or client-supplied credit amount is trusted by the app.

Create these App Store Connect in-app purchases as **consumable** products with
exact identifiers `com.agdevelops.vyro.credits250` and
`com.agdevelops.vyro.credits800`. Configure localized storefront pricing in
App Store Connect; the app displays the price returned by StoreKit.

The existing Play product IDs and Android purchase code remain in place. The
checked-in backend currently does not contain the Google Play verification
route referenced by the Flutter screen; verify the deployed backend's Android
route before relying on Play billing from this repository build.
