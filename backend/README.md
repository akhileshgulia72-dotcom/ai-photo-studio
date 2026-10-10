# VYRO generation API — Google Cloud Run

This FastAPI service runs on Cloud Run in the `ai-note-scanner` Google Cloud
project, alongside Firebase Auth, Firestore, and Storage. Cloud Run is the
Google-hosted runtime for this Python API; Firebase Storage and Firestore rules are deployed
from the project root with firebase deploy --only storage,firestore:rules --project ai-note-scanner.

## Local run

Create `backend/.env` with `OPENAI_API_KEY`, `FIREBASE_STORAGE_BUCKET`, and,
optionally, `FIREBASE_SERVICE_ACCOUNT_JSON` pointing to a local service-account
JSON file. Keep both the `.env` and key out of source control. If the credential
path is omitted, Firebase Admin uses Application Default Credentials.

```powershell
cd backend
.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

## Deploy

Use the Google Cloud CLI against the Firebase project's linked Google Cloud
project. Set up a runtime service account with Firestore access (`roles/datastore.user`),
Storage object access on the `ai-note-scanner.firebasestorage.app` bucket
(`roles/storage.objectAdmin`), and Secret Manager access to the OpenAI key.
Do not create or upload a service-account JSON key for Cloud Run; the attached
runtime identity is used by Firebase Admin through ADC.

Enable the Cloud Run, Cloud Build, Artifact Registry, and Secret Manager APIs:

```powershell
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com --project ai-note-scanner
```

Use the existing vyro-cloud-run@ai-note-scanner.iam.gserviceaccount.com runtime account; grant roles/datastore.user on the project and
roles/storage.objectAdmin on the Firebase Storage bucket.
For Google Play purchases, enable the Google Play Android Developer API and
grant this runtime service account access to the app in Play Console with
permission to view financial/order data and manage orders. The app's Android
package must match `com.agdevelops.ainotescanner` (or set
`ANDROID_PACKAGE_NAME` on Cloud Run). The backend verifies each purchase token,
commits the credit pack exactly once to the existing `users/{uid}` profile,
then consumes the Play product. The token hash is recorded in `play_purchases`
only as an idempotency record; the existing user profile remains the sole
credit balance. No service-account key belongs in Flutter or the repository.
Create these exact Play Console products as one-time consumable in-app products:
`vyro_creator_150` at USD 1.99 and `vyro_pro_500` at USD 4.99. Play may show a
localized price to users in other countries.

For Apple, see `ENVIRONMENT.md` for the App Store Server API credentials and
Apple root certificates required by `/v1/iap/apple/verify`. Create the
consumable products `com.agdevelops.vyro.credits250` and
`com.agdevelops.vyro.credits800` in App Store Connect. Apple prices are fetched
from StoreKit and localized by the storefront.
Store `OPENAI_API_KEY` as a Secret Manager secret and grant this service account
`roles/secretmanager.secretAccessor` on that secret. Add the secret value in the
Google Cloud Console; do not place the key in commands, `.env` committed to Git,
or the container image.

Then deploy from this directory:

```powershell
gcloud config set project ai-note-scanner
gcloud run deploy vyro-api --source . --project ai-note-scanner --region asia-south1 --allow-unauthenticated --service-account vyro-cloud-run@ai-note-scanner.iam.gserviceaccount.com --timeout 600 --memory 2Gi --cpu 2 --concurrency 2 --set-env-vars FIREBASE_STORAGE_BUCKET=ai-note-scanner.firebasestorage.app,OPENAI_TIMEOUT=240 --set-secrets OPENAI_API_KEY=OPENAI_API_KEY:latest
```

Cloud Run currently serves VYRO at `https://vyro-api-jnz6yqjl4a-el.a.run.app`.
The service is
publicly invokable so the Flutter client can reach it; every protected API
route still verifies the Firebase ID token and UID. Configure the app with
that URL and rebuild it:

Image edit quality comes from the authenticated user's backend profile:
Free and Creator use medium, while Pro uses high. The client cannot request a
higher quality by changing request fields. A previous
`OPENAI_QUALITY=low` deployment variable does not override the medium default.

```powershell
flutter build apk --release --dart-define=GENERATION_API_BASE_URL=https://vyro-api-jnz6yqjl4a-el.a.run.app
```

Smoke-check `https://vyro-api-jnz6yqjl4a-el.a.run.app/health`, then sign into VYRO and create
a generation. Confirm the object and the matching `generations` Firestore
document use the same authenticated UID. Cloud Run and Firebase Storage should
be in compatible regions to reduce latency and data-transfer costs; use the
bucket's location when choosing `--region` if possible.
