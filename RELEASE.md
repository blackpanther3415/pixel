# Pixel v1.0.0 — Deployment Guide

## What you need installed

| Tool | Version | Install |
|------|---------|---------|
| Flutter SDK | 3.47.3+ | https://flutter.dev |
| Android Studio | Latest | https://developer.android.com/studio |
| JDK | 17 | Comes with Android Studio |
| Git | Latest | https://git-scm.com |

## Step 1: Clone and setup

```bash
git clone <your-repo-url>
cd "Pixel OS"
flutter pub get
```

## Step 2: Generate a signing keystore (Android)

```bash
keytool -genkey -v \
  -keystore pixel-key.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias pixel
```

Enter a password when prompted. **Remember it.**

## Step 3: Configure signing

Edit `android/key.properties` and fill in:

```properties
storePassword=YOUR_PASSWORD_HERE
keyPassword=YOUR_PASSWORD_HERE
keyAlias=pixel
storeFile=/full/path/to/pixel-key.jks
```

## Step 4: Build

### APK (sideload or direct install)
```bash
./scripts/build_android.sh
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

### AAB (Google Play Store)
```bash
./scripts/build_android_aab.sh
```
Output: `build/app/outputs/bundle/release/app-release.aab`

### Windows
```bat
scripts\build_windows.bat
```
Output: `build\windows\x64\runner\Release\pixel.exe`

## Step 5: Install

### Android (sideload)
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Android (transfer to phone)
Copy the APK to your phone via USB/email/cloud, then tap to install.

### Windows
Zip the entire `build\windows\x64\runner\Release\` folder and distribute.

## Step 6: Play Store (optional)

1. Go to https://play.google.com/console
2. Create a developer account ($25 one-time)
3. Create new app → fill in store listing
4. Upload `app-release.aab`
5. Fill in content rating, pricing, etc.
6. Submit for review

## Troubleshooting

### "flutter: command not found"
Add Flutter to your PATH:
```bash
export PATH="$PATH:/path/to/flutter/bin"
```

### "ANDROID_HOME not set"
Set it in your shell profile:
```bash
export ANDROID_HOME="$HOME/Android/Sdk"
```

### Build fails with signing error
Make sure `android/key.properties` exists and has correct passwords.

### APK is very large
This is normal for debug builds. Release builds with minification are smaller.
