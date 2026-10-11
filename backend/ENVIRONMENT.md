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
- `ANDROID_PACKAGE_NAME=com.agdevelops.ainotescanner` (optional; this is the
  default used by the verifier).
- Enable the Google Play Android Developer API in the Cloud project.
- Grant the existing Cloud Run runtime service account access to this app in
  Play Console with permission to view financial/order data and manage orders.
- Cloud Run uses its attached runtime service account through Application
  Default Credentials. Do not upload a service-account JSON key.

`POST /v1/iap/google/verify` accepts the authenticated Flutter client's
`productId` and `purchaseToken` form fields. The backend fetches purchase state
from Google's Android Publisher API, checks the purchase state, product,
quantity, and account binding when present, then atomically grants the
server-owned credits and plan in Firestore. Older purchases created before the
client sent an account binding can be claimed once by the authenticated user;
all retries and cross-account replays are checked against a hashed token
ledger. The purchase is consumed only after the Firestore grant commits.

AdMob SSV:
- In AdMob, configure the rewarded ad unit's server-side verification callback URL as:
  https://YOUR_CLOUD_RUN_HOST/v1/rewards/admob-ssv
- Set the reward amount in AdMob to 5 and the reward item to a stable value such as credits.
- The backend independently enforces AD_REWARD_CREDITS=5.

Apple IAP:
The backend exposes `POST /v1/iap/apple/verify` and fails closed until its
server-side configuration is complete. Keep the endpoint, `signedTransactionJws`
request field, and successful response contract unchanged.

Set these as ordinary Cloud Run environment variables:

- `APPLE_APP_ID`: positive numeric Apple ID from App Store Connect > Apps >
  this app > General > App Information. This is not the bundle ID.
- `APPLE_IAP_BUNDLE_ID`: `com.agdevelops.ainotescanner` (optional; this exact
  bundle ID is the default).
- `APPLE_IAP_KEY_ID`: Key ID for the App Store Connect In-App Purchase key.
- `APPLE_IAP_ISSUER_ID`: Issuer ID shown under Users and Access > Integrations.
- `APPLE_ROOT_CERTIFICATES_B64`: comma-separated Base64-encoded DER X.509 CA
  certificates downloaded from Apple's official PKI source.

Use Secret Manager for these values:

- `APPLE_IAP_PRIVATE_KEY`: the downloaded App Store Connect `.p8` private key.
  Inject it into Cloud Run as an environment variable backed by a Secret Manager
  secret. The parser accepts PEM newlines and escaped `\\n` newlines. Never put
  this key in Flutter, source control, build arguments, logs, or a committed
  `.env` file.
- `APPLE_IAP_SANDBOX_UID_ALLOWLIST`: recommended as a Secret Manager-backed
  environment variable because it contains account identifiers. Its value is a
  comma-separated list of exact Firebase UIDs allowed to receive sandbox or
  TestFlight credits. Never use `*`. An empty list rejects all sandbox credits;
  production purchases are not affected.

Create the In-App Purchase API key in App Store Connect under Users and Access
> Integrations > Keys > In-App Purchase. This requires the Account Holder or
Admin role. Record the Key ID and Issuer ID, download the `.p8` file once, and
store it directly in Secret Manager. The numeric Apple App ID is in the app's
App Information page; do not substitute `com.agdevelops.ainotescanner`.

For `APPLE_ROOT_CERTIFICATES_B64`, download the current Apple Root Certificates
from [Apple PKI](https://www.apple.com/certificateauthority/) (Apple Root
Certificates section only; do not substitute intermediates). For each
downloaded DER `.cer` file, Base64-encode the original bytes without line wraps.
For example in PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('.\AppleRootCA-G3.cer'))
```

If Apple provides a PEM file, first convert it to DER with
`openssl x509 -in AppleRootCA.pem -outform DER -out AppleRootCA.der`, then
Base64-encode the DER file bytes. Join each root's Base64 value with a comma
and set the result as `APPLE_ROOT_CERTIFICATES_B64`. Confirm every configured
certificate is a DER X.509 CA certificate. Do not download certificates from
third-party sources or disable certificate-chain/online verification.

Before TestFlight testing, add only the intended test account's exact Firebase
UID to `APPLE_IAP_SANDBOX_UID_ALLOWLIST`. After testing, remove the UID or empty
the list. A sandbox transaction is rejected unless that authenticated UID is
explicitly allowlisted.

The endpoint verifies the submitted JWS using Apple's Python App Store Server
Library with certificate-chain and online checks enabled, fetches and verifies
the latest transaction from Apple, checks app, product, consumable type,
transaction ID, positive purchase date, revocation, quantity, and the UID-bound
`appAccountToken`, then grants server-defined credits with an atomic Firestore
transaction. The transaction record is idempotent across retries and rejects
cross-account replay. No Apple credential or client-supplied credit amount is
trusted by the app.

Sign in with Apple must be enabled for the iOS App ID in the Apple Developer
portal and as a provider in Firebase Authentication. The Runner target includes
the Apple Sign-In entitlement; refresh the provisioning profile after enabling
the capability. `DELETE /v1/account` removes the Firebase user, profile, saved
generation documents, and Storage files. It retains only a one-way account
fingerprint in Apple purchase records to prevent transaction replay.

Create these App Store Connect in-app purchases as **consumable** products with
exact identifiers `com.agdevelops.vyro.credits250` and
`com.agdevelops.vyro.credits800`. Configure localized storefront pricing in
App Store Connect; the app displays the price returned by StoreKit.

The Google Play purchase verifier is documented separately above. Keep its
Android product IDs, API contract, runtime service-account access, and purchase
consumption behavior unchanged when configuring Apple IAP.
