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
The Flutter client deliberately does not complete iOS purchases until a server-side Apple verification path is configured. Do not change that safety behavior.
For production iOS billing, configure Apple's App Store Server API credentials and Apple root certificates on the backend, then add an /v1/iap/apple/verify endpoint using Apple's official App Store Server Library.
