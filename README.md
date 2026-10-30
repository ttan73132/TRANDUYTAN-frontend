# TRANDUYTAN Frontend - Flutter

Group 8 employee attendance app. Android ID: `vn.nhom8.tranduytan`. Version: **1.3.1+9**.

- Frontend: https://github.com/ttan73132/TRANDUYTAN-frontend
- Backend: https://github.com/ttan73132/TRANDUYTAN-backend
- Backend upstream: https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api
- Current deployed API: `https://nguyen-hoai-nam-2380601398-api.onrender.com/v1`

Flutter project is at this repository's root. The backend repository preserves the group's original authorship and history. These source repositories do not create a new deployment; the app continues to use the group's running API.

## Features

- Email OTP, pending approval, secure access/refresh tokens.
- Opt-in fingerprint/supported face quick login after OTP, biometric-protected Android Keystore refresh token, app lock after 30 seconds in background (Android 11+).
- Separate camera face quick login: local ML Kit landmarks and OpenCV SFace identity comparison, randomized head-turn challenge, one-time 39 MB model download. Camera 2D is weaker than fingerprint and is not certified anti-spoofing. Enabling it stores the rotating session in encrypted local storage accessible after the app's face check; fingerprint and camera methods then use the same latest session. [Details](docs/LOCAL_FACE.md).
- Settings: persistent font size (85-140%), five background colors, per-account local profile editing. Profile edits do not sync to the group API or change account permissions. [Usage and limitations](docs/SETTINGS-BIOMETRICS.md).
- Admin/manager/employee roles; employee, branch and shift management.
- GPS attendance, motion confirmation, face enrollment/login with OTP.
- Attendance reports, corrections and versioned bilingual handovers.
- Foreground data refresh every 15 seconds.
- On-device camera OCR, speech recognition and translation: Vietnamese, English, Chinese and Japanese.
- Dedicated Vietnamese Zipformer model; Whisper Tiny for English/Chinese/Japanese. Model packages download once. User images/audio are not sent to a translation API.

## Run

Flutter 3.47.4 / Dart 3.13.3; Android 7 or newer.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

The shared API is configured by default. For another deployment with the same contract:

```sh
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com/v1
```

New users verify email and wait for a group administrator to approve the account, assign a branch and schedule shifts. Translation is available before approval.

## Signed Android Build

With Flutter, Java/keytool and Android SDK configured, run from PowerShell:

```powershell
.\scripts\build-apk.ps1
```

The script verifies the app, creates a local signing key only if none exists, and writes `output/TRANDUYTAN.apk`. Keep the signing key for future updates. Signing files, credentials, build output, model weights and user recordings are excluded from Git.

## Documentation

- [API and account setup](docs/SHARED_API.md)
- [Offline translation and model attribution](docs/OFFLINE_TRANSLATION.md)
- [Demo walkthrough](docs/DEMO.md)

Application code matches version 1.2.0+7, which passed 52 Flutter tests in the original project. This repository's workflow independently checks analysis and tests after the split. Live camera was confirmed by the user; the latest Vietnamese microphone accuracy change still requires a user retest. Test fixtures do not prove all device/account workflows.
