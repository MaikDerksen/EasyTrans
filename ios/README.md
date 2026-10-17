# EasyTrans for iOS

SwiftUI app for iOS 26+ (Liquid Glass), packaged as a SwiftPM library and built with
[xtool](https://xtool.sh), so it builds on Linux/Windows (WSL) without Xcode.

| File | Purpose |
|---|---|
| `Sources/EasyTrans/SpeechPipeline.swift` | Microphone → two `SpeechAnalyzer`s (one `SpeechTranscriber` per language) |
| `Sources/EasyTrans/ConversationModel.swift` | Picks the speaking language per time range, live/final turns, live translation |
| `Sources/EasyTrans/Translator.swift` | Apple Translation sessions, one per direction |
| `Sources/EasyTrans/ContentView.swift` | Two halves (top rotated 180°) and the glass control bar |
| `xtool.yml`, `Info.plist` | Bundle ID, permissions texts, portrait lock |

## Toolchain (Windows via WSL)

```bash
wsl -d Ubuntu-22.04 -- bash ios/scripts/setup-wsl.sh     # Swift, usbmuxd, xtool (asks for sudo)
xtool sdk install /mnt/c/Users/<you>/Downloads/Xcode_27.1.xip
```

Download the Xcode `.xip` from <https://developer.apple.com/download/all/?q=Xcode> with your Apple ID.

## Build

```bash
wsl -d Ubuntu-22.04 -- bash ios/scripts/build-wsl.sh    # writes ios/build/EasyTrans.ipa (unsigned)
```

The script syncs the package into the WSL filesystem first; SwiftPM is much faster there than on
`/mnt/c`.

## Signing & install

With a working Apple login, `xtool dev` builds, signs and installs over USB (pass the iPhone to WSL
with [scripts/attach-iphone.ps1](scripts/attach-iphone.ps1) and usbipd-win).

**Known issue (October 2026):** Apple currently rejects SMS-based two-factor login from third-party
tools (xtool, AltServer, Sideloadly, iloader). Options:

- Use an Apple ID that has a trusted Apple device (code arrives as a push).
- Use a paid Apple Developer Program membership and log in with an App Store Connect API key
  (`xtool auth login`, mode 0), which bypasses the password login entirely.
- `scripts/build-limd.sh` and `scripts/build-xtool-fixed.sh` build xtool from source with the open
  login fixes and an extra `xtool sign --udid` command, which signs an IPA for a device that is not
  connected (install it later with any tool that installs signed IPAs).

Free Apple IDs sign for 7 days; reinstall after that.

## No simulator on Windows

The iOS Simulator only exists inside Xcode on macOS. For UI review there is a clickable mock in
[../docs/ui-preview/](../docs/ui-preview/).
