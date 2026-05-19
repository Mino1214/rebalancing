# Rebalancing Observer

Read-only Flutter app for watching the autonomous rebalancing engine.

## Run

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://engine.medicalnewshub.info
```

Or build and serve web locally:

```bash
flutter build web --dart-define=API_BASE_URL=https://engine.medicalnewshub.info
python -m http.server 8789 --directory build/web --bind 127.0.0.1
```

Open:

```text
http://127.0.0.1:8789
```

## API

The app reads:

```text
GET /status
```

from `API_BASE_URL`. If the API is not available yet, it shows sample fallback data.

This app intentionally has no manual order controls.

