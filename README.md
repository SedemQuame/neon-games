# GameHub

GameHub is the main repository for **Glory Grid**, a Flutter app backed by a Go-based game and wallet platform. The project combines:

- a Flutter client for mobile and web in `game_trader_app/`
- a multi-service backend in `apis/`
- supporting product, marketing, and strategy docs in the repo root

## What Is In This Repo

### App clients

The Flutter app includes:

- Firebase Auth with Google, Apple, and X SSO (plus anonymous guest mode)
- wallet and ledger views
- deposit and withdrawal flows
- trading-game screens
- rankings, profile, and app logs

### Backend

The backend is organized as service modules:

- `auth-service`
- `game-session-service`
- `payment-gateway`
- `wallet-service`
- `trader-pool`
- `gateway`

For the current deployment model, these services are packaged into a **single Docker image** with:

- an internal Go gateway on port `80`
- embedded Redis
- external MongoDB via `MONGO_URI`

## Repository Layout

```text
.
├── README.md
├── BACKEND_SPEC.md
├── THIRD_PARTY_SETUP.md
├── apis/
├── game_trader_app/
├── marketing/
├── scripts/
├── strategy/
└── unity-mcp/
```

Key directories:

- `game_trader_app/` - Flutter client
- `apis/` - backend services, Docker packaging, and deployment assets
- `marketing/` - marketing site assets/content
- `strategy/` - planning and product direction

## Prerequisites

- Flutter SDK
- Xcode for iOS builds
- Android Studio / Android SDK for Android builds
- Docker with Compose v2
- A working MongoDB connection string for the backend

## Quick Start

### 1. Start the backend

Use the current backend workflow in `apis/`:

```bash
cd apis
make setup
# edit .env with real credentials
make up
make logs
```

Default local endpoints:

| Service | URL |
|---|---|
| Gateway | `http://localhost:80` |
| Auth Service | `http://localhost:8001` |
| Game Session Service | `http://localhost:8002` |
| Payment Gateway | `http://localhost:8003` |
| Wallet Service | `http://localhost:8004` |
| Trader Pool | `http://localhost:8005` |

Useful commands:

- `make ps` - show container status
- `make down` - stop the backend
- `make clean` - remove the backend container and Redis volume

### 2. Run the Flutter app (mobile)

```bash
cd game_trader_app
flutter pub get
dart pub global activate flutterfire_cli
flutterfire configure --project=glory-grid-b90a3
flutter run --dart-define=GAMEHUB_BASE_URL=http://127.0.0.1
```

The app reads its API base URL from `GAMEHUB_BASE_URL`. If you do not pass it, the default is:

```text
http://127.0.0.1
```

For a physical device, pass a base URL the phone can actually reach, such as a LAN IP or tunnel URL.

### 3. Run the Flutter web app

```bash
cd game_trader_app
flutter run -d chrome \
  --web-hostname localhost \
  --web-port 7357 \
  --dart-define=GAMEHUB_BASE_URL=http://127.0.0.1
```

### 4. Run the web app via Docker (prebuilt artifact)

If you prefer to build once and serve that exact build artifact:

```bash
cd game_trader_app
flutter build web --release --dart-define=GAMEHUB_BASE_URL=http://127.0.0.1
docker build --target prebuilt -t gamehub-web .
docker run --rm -p 8080:80 gamehub-web
```

Then open `http://localhost:8080`.

For Firebase token verification in auth-service, set:

```text
FIREBASE_PROJECT_ID=<your_firebase_project_id>
```

## Mobile Build Commands

### iOS

```bash
cd game_trader_app
flutter build ios --simulator
flutter build ios --release --no-codesign
```

The iOS project targets `iOS 13.0+`.

### Android

```bash
cd game_trader_app
flutter build apk
```

If you need to generate a signing keystore:

```bash
keytool -genkey -v -keystore ~/key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gamehub
```

## Important Docs

- [`BACKEND_SPEC.md`](./BACKEND_SPEC.md) - architecture and system design
- [`THIRD_PARTY_SETUP.md`](./THIRD_PARTY_SETUP.md) - Deriv, Flutterwave, Tatum, Resend, and related integrations
- [`apis/DEPLOYMENT.md`](./apis/DEPLOYMENT.md) - current backend packaging and deployment notes
- [`apis/.env.example`](./apis/.env.example) - backend environment template

## Notes

- Prefer `apis/Makefile` and `apis/DEPLOYMENT.md` for the current backend workflow.
- The root `setup.sh` still contains older development helpers and should be treated as legacy unless you are intentionally using that path.
- Development JWT keys are stored under `apis/infra/dev-secrets/`.
