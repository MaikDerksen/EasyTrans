# EasyTrans for Android

Kotlin + Jetpack Compose, `minSdk 34` (automatic language detection in `SpeechRecognizer` needs
Android 14), `targetSdk 36`.

| File | Purpose |
|---|---|
| `SpeechEngine.kt` | Continuous listening; restarts the recognizer after each pause, falls back to the online recognizer while offline language packs download |
| `Translator.kt` | ML Kit on-device translation, one client per direction |
| `ConversationViewModel.kt` | Speaker attribution, live/final turns, coalesced live translation |
| `ui/ConversationScreen.kt` | Two halves (top rotated 180°) and the control bar |
| `ui/Glass.kt` | Glass-style surfaces and the hand-drawn icons |

## Requirements

- JDK 17 or newer
- Android SDK with platform 37, build-tools 36 and, for the emulator, an x86_64 Google Play system
  image (`system-images;android-36.1;google_apis_playstore;x86_64`)
- `local.properties` with `sdk.dir=...` (created by Android Studio, git-ignored)

## Build & run

```bash
cd android
./gradlew assembleDebug
adb install -r -g app/build/outputs/apk/debug/app-debug.apk
```

In the emulator, enable the host microphone (`emulator -avd <name> -allow-host-audio`, or
*Extended controls → Microphone*). On first start the app downloads the ML Kit translation models
(about 30 MB per language) and, if needed, triggers the download of the offline speech packs.

## Release

```bash
cp keystore.properties.example keystore.properties   # then fill in
./gradlew bundleRelease
```

Output: `app/build/outputs/bundle/release/app-release.aab`. Keep the keystore and its passwords
backed up outside the repository; you need them for every update. In CI, provide
`EASYTRANS_KEYSTORE_FILE`, `EASYTRANS_KEYSTORE_PASSWORD`, `EASYTRANS_KEY_ALIAS` and
`EASYTRANS_KEY_PASSWORD` instead of the properties file.

R8 keep rules for ML Kit live in `app/proguard-rules.pro`; without them translation fails in
release builds. Store listing and review checklist: [../docs/play-store.md](../docs/play-store.md).
