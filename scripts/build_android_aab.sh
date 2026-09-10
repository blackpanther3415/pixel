#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Pixel — Android AAB Build (Play Store) ==="
echo ""

if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter not found. Install Flutter SDK and add to PATH."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/android/key.properties" ]; then
    echo "ERROR: android/key.properties not found."
    echo ""
    echo "For Play Store uploads, you MUST sign with a release keystore."
    echo "Generate one:"
    echo "  keytool -genkey -v -keystore pixel-key.jks \\"
    echo "    -keyalg RSA -keysize 2048 -validity 10000 -alias pixel"
    echo ""
    echo "Then create android/key.properties with your passwords."
    exit 1
fi

cd "$PROJECT_DIR"

echo "[1/3] Getting dependencies..."
flutter pub get

echo "[2/3] Running tests..."
flutter test --no-pub || echo "WARNING: Some tests failed. Continuing build..."

echo "[3/3] Building AAB..."
flutter build appbundle --release --no-pub

AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB_PATH" ]; then
    SIZE=$(du -h "$AAB_PATH" | cut -f1)
    echo ""
    echo "=== BUILD SUCCESSFUL ==="
    echo "AAB: $PROJECT_DIR/$AAB_PATH"
    echo "Size: $SIZE"
    echo ""
    echo "Upload to Play Console:"
    echo "  https://play.google.com/console"
    echo "  → App → Production → Create new release → Upload AAB"
else
    echo "ERROR: AAB not found at expected path."
    exit 1
fi
