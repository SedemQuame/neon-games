# Glory Grid Flutter App

The web build uses `GAMEHUB_BASE_URL` at compile time. The production value is:

```text
https://neon-games-production.up.railway.app
```

For local web release builds:

```bash
cp .env.production.example .env.production
../scripts/web_release.sh
```

Or run directly:

```bash
flutter build web --release \
  --dart-define=GAMEHUB_BASE_URL=https://neon-games-production.up.railway.app
```

Do not rely on runtime browser environment variables for Flutter web; the URL is compiled into `build/web/main.dart.js`.
