#!/bin/bash
# Script to download Flight Crew View APK
# This runs on the HOST before the environment starts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_DIR="$SCRIPT_DIR/apks"
APK_PATH="$APK_DIR/flight_crew_view.apk"

# Create apks directory if it doesn't exist
mkdir -p "$APK_DIR"

# Check if APK already exists
if [ -f "$APK_PATH" ]; then
    echo "Flight Crew View APK already exists at $APK_PATH"
    ls -la "$APK_PATH"
    exit 0
fi

echo "Downloading Flight Crew View APK..."

# Try APKPure.net
echo "Attempting download from APKPure.net..."
if curl -sL -o "$APK_PATH.tmp" \
    -H "User-Agent: Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36" \
    --connect-timeout 30 \
    --max-time 300 \
    "https://d.apkpure.net/b/APK/com.robert.fcView?version=latest" 2>/dev/null; then

    # Verify it's a valid APK (ZIP file with AndroidManifest.xml)
    if file "$APK_PATH.tmp" | grep -q "Zip archive"; then
        if unzip -l "$APK_PATH.tmp" 2>/dev/null | grep -q "AndroidManifest.xml"; then
            mv "$APK_PATH.tmp" "$APK_PATH"
            echo "Successfully downloaded Flight Crew View APK"
            ls -la "$APK_PATH"
            exit 0
        fi
    fi
    rm -f "$APK_PATH.tmp"
fi

echo "ERROR: Failed to download Flight Crew View APK automatically"
echo "Please manually download from Google Play Store or APK mirror sites"
echo "Package name: com.robert.fcView"
echo "Place the APK at: $APK_PATH"
exit 1
