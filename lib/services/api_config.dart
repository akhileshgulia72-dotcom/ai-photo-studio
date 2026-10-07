/// Set this public API origin when building/running the app, for example:
/// Override with --dart-define=GENERATION_API_BASE_URL=https://your-service.run.app
const generationApiBaseUrl = String.fromEnvironment(
  'GENERATION_API_BASE_URL',
  defaultValue: 'https://vyro-api-jnz6yqjl4a-el.a.run.app',
);
