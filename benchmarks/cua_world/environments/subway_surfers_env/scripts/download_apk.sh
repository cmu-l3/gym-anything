#!/bin/bash
# Script to download Subway Surfers APK automatically
# This runs on the HOST before the environment starts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_DIR="$SCRIPT_DIR/apks"
APK_PATH="$APK_DIR/subway_surfers.apk"

# Create apks directory if it doesn't exist
mkdir -p "$APK_DIR"

# Check if APK already exists
if [ -f "$APK_PATH" ]; then
    echo "Subway Surfers APK already exists at $APK_PATH"
    exit 0
fi

echo "Downloading Subway Surfers APK..."

# Try multiple sources for reliability
# Source 1: APKPure direct link (these change, so we try multiple)
APKPURE_URL="https://d.apkpure.com/b/APK/com.kiloo.subwaysurf?version=latest"

# Source 2: APKMirror (backup)
# Note: APKMirror requires parsing HTML, so we use a direct download approach

# Try downloading from APKPure
echo "Attempting download from APKPure..."
if curl -L -o "$APK_PATH.tmp" \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
    --connect-timeout 30 \
    --max-time 300 \
    "$APKPURE_URL" 2>/dev/null; then

    # Verify it's a valid APK (ZIP file with AndroidManifest.xml)
    if file "$APK_PATH.tmp" | grep -q "Zip archive"; then
        if unzip -l "$APK_PATH.tmp" 2>/dev/null | grep -q "AndroidManifest.xml"; then
            mv "$APK_PATH.tmp" "$APK_PATH"
            echo "Successfully downloaded Subway Surfers APK"
            ls -la "$APK_PATH"
            exit 0
        fi
    fi
    rm -f "$APK_PATH.tmp"
fi

# Alternative: Try using wget with different user agent
echo "Trying alternative download method..."
if wget -O "$APK_PATH.tmp" \
    --user-agent="Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36" \
    --timeout=60 \
    "https://d.apkpure.com/b/APK/com.kiloo.subwaysurf?version=latest" 2>/dev/null; then

    if file "$APK_PATH.tmp" | grep -q "Zip archive"; then
        mv "$APK_PATH.tmp" "$APK_PATH"
        echo "Successfully downloaded Subway Surfers APK (method 2)"
        exit 0
    fi
    rm -f "$APK_PATH.tmp"
fi

echo "ERROR: Failed to download Subway Surfers APK automatically"
echo "Please manually download and place at: $APK_PATH"
exit 1
