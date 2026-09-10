#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Pixel — Android APK Build ==="
echo ""

# Check prerequisites
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter not found. Install Flutter SDK and add to PATH."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/android/key.properties" ]; then
    echo "WARNING: android/key.properties not found."
    echo "  The APK will be signed with debug keys."
    echo "  For production signing, create android/key.properties."
    echo ""
    read -p "Continue with debug signing? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

cd "$PROJECT_DIR"

echo "[1/3] Getting dependencies..."
flutter pub get

echo "[2/3] Running tests..."
flutter test --no-pub || echo "WARNING: Some tests failed. Continuing build..."

echo "[3/3] Building APK..."
flutter build apk --release --no-pub

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo ""
    echo "=== BUILD SUCCESSFUL ==="
    echo "APK: $PROJECT_DIR/$APK_PATH"
    echo "Size: $SIZE"
    echo ""
    echo "Install on device:"
    echo "  adb install $APK_PATH"
    echo ""
    echo "Or transfer the APK to your phone and install it."
else
    echo "ERROR: APK not found at expected path."
    exit 1
fi
