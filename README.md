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
flutter run --dart-define=GENERATION_API_BASE_URL=https://YOUR_BACKEND
```

The client sends `POST /v1/generations` as multipart form data with fields `templateId`, `prompt`, and `negativePrompt`, an `image` file, and the Firebase ID token in `Authorization: Bearer ...`. A successful backend response must include `outputImageUrl`.

The backend is not included or deployed in this project yet. It must validate Firebase authentication and credits server-side, call the selected image provider (initially FLUX.2 Klein 4B), store output in Firebase Storage, and return the resulting URL. Keep provider keys in the backend secret manager. Without a configured backend URL, Generate shows an explicit setup message.
