# Glory Grid — Android Production Prep

## App Identity
- **Application ID:** `com.legendarypixelsid.glorygrid` (update in `android/app/build.gradle.kts` if you have a reserved Play Console id)
- **Display Name:** Glory Grid
- **Icon:** `assets/icons/app_icon.png` (regenerate platform assets via `flutter pub run flutter_launcher_icons` after changes)
- **Short Description (80 chars max):** "Skill-based arcade trading with live wallet sync and instant wins."
- **Full Description:**
  "Glory Grid combines fast-paced casual games with real-money wallets. Play Kinetic Arcade, Neon Perimeter, Dual Dimension Flip and more, stake dollars securely, and mirror every result back to your vault. Low-latency APIs, multi-game wallets, Deriv-backed settlement, and ngrok-ready tooling make it ideal for field tests and early access launches."

## Release Build & Smoke Test
```
# From repo root
export GAMEHUB_BASE_URL="https://your.ngrok-free.dev"
./scripts/android_release.sh --base-url "$GAMEHUB_BASE_URL"
```
Outputs:
- APK: `game_trader_app/build/app/outputs/flutter-apk/app-release.apk`
- AAB: `game_trader_app/build/app/outputs/bundle/release/app-release.aab`

With a device/emulator connected via `adb`, the script will automatically push the release APK for testing unless `--skip-install` is provided. Use `--device <serial>` if multiple devices are present.

## Play Console / Testing Track
1. Sign in to the Play Console and select *Glory Grid*.
2. Choose **Internal testing** (or Closed/Open testing) track.
3. Upload the generated `.aab` file.
4. Provide the short & full descriptions above, plus screenshots captured from the latest build.
5. Add testers, review content rating, and roll out the release.

## Icon + Branding Reminder
- Source icon: `assets/icons/app_icon.png` (1024×1024, starfield-on-black with glowing `$`).
- Android & iOS launchers are generated via `flutter_launcher_icons` and already baked into `android/mipmap-*` and `ios/Runner/Assets.xcassets/AppIcon.appiconset`.
- Update this file when branding elements (name, description, icon) change.
