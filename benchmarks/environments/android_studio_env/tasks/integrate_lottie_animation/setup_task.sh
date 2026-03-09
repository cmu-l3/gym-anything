#!/bin/bash
set -e
echo "=== Setting up integrate_lottie_animation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ------------------------------------------------------------------
# 1. Prepare the Asset (Real Data)
# ------------------------------------------------------------------
ASSET_DIR="/home/ga/Documents/assets"
mkdir -p "$ASSET_DIR"

LOTTIE_URL="https://raw.githubusercontent.com/airbnb/lottie-android/master/sample/src/main/assets/AndroidWave.json"
ASSET_PATH="$ASSET_DIR/android_wave.json"

echo "Downloading real Lottie asset..."
wget -q "$LOTTIE_URL" -O "$ASSET_PATH" || {
    echo "Download failed, creating fallback valid Lottie JSON..."
    # Fallback minimal valid Lottie JSON to ensure task is solvable even if network fails
    cat > "$ASSET_PATH" << EOF
{"v":"5.5.2","fr":60,"ip":0,"op":60,"w":100,"h":100,"nm":"Fallback Wave","ddd":0,"assets":[],"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"Shape Layer 1","sr":1,"ks":{"o":{"a":0,"k":100,"ix":11},"r":{"a":0,"k":0,"ix":10},"p":{"a":0,"k":[50,50,0],"ix":2},"a":{"a":0,"k":[0,0,0],"ix":1},"s":{"a":0,"k":[100,100,100],"ix":6}},"ao":0,"shapes":[{"ty":"rc","d":1,"s":{"a":0,"k":[50,50],"ix":2},"p":{"a":0,"k":[0,0],"ix":3},"r":{"a":0,"k":0,"ix":4},"nm":"Rectangle Path 1","mn":"ADBE Vector Shape - Rect","hd":false},{"ty":"fl","c":{"a":0,"k":[1,0,0,1],"ix":4},"o":{"a":0,"k":100,"ix":5},"r":1,"bm":0,"nm":"Fill 1","mn":"ADBE Vector Graphic - Fill","hd":false}],"ip":0,"op":60,"st":0,"bm":0}]}
EOF
}

chown -R ga:ga "/home/ga/Documents"

# ------------------------------------------------------------------
# 2. Prepare the BasicApp Project
# ------------------------------------------------------------------
# We will use the SunflowerApp as a base but strip it down to look like a "BasicApp"
# This ensures we have a valid Gradle wrapper and project structure.

PROJECT_DIR="/home/ga/AndroidStudioProjects/BasicApp"
SOURCE_TEMPLATE="/workspace/data/SunflowerApp"

echo "Preparing BasicApp project..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects

if [ -d "$SOURCE_TEMPLATE" ]; then
    cp -r "$SOURCE_TEMPLATE" "$PROJECT_DIR"
else
    # Fallback if specific template missing, try to find any project
    ANY_PROJECT=$(find /workspace/data -maxdepth 2 -name "build.gradle.kts" | head -1 | xargs dirname | xargs dirname)
    if [ -n "$ANY_PROJECT" ]; then
        cp -r "$ANY_PROJECT" "$PROJECT_DIR"
    else
        echo "ERROR: No base project template found."
        exit 1
    fi
fi

# Clean up the project to look like a fresh "Empty Activity" app
echo "Resetting project to basic state..."
cd "$PROJECT_DIR"

# Reset Manifest
PACKAGE_NAME="com.google.samples.apps.sunflower" # Keeping original package to avoid refactoring hell in setup
# We will just pretend it's BasicApp in the UI title
sed -i 's/android:label="@string\/app_name"/android:label="BasicApp"/' app/src/main/AndroidManifest.xml 2>/dev/null || true

# Reset Layout to simple Hello World
LAYOUT_FILE="app/src/main/res/layout/activity_main.xml"
# Find where activity_main is if path differs
LAYOUT_FILE=$(find . -name "activity_main.xml" | head -1)

if [ -n "$LAYOUT_FILE" ]; then
    cat > "$LAYOUT_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:text="Hello World!" />

</FrameLayout>
EOF
else
    echo "WARNING: Could not find activity_main.xml to reset"
fi

# Reset build.gradle.kts (remove existing libs but keep kotlin/android basics)
BUILD_GRADLE="app/build.gradle.kts"
if [ -f "$BUILD_GRADLE" ]; then
    # We want to remove any complex dependencies but ensure basic Android ones remain
    # This is a bit risky with sed, so we'll append to the end if we can't parse safely
    # Ideally, the agent just ADDS to this file.
    true
fi

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# 3. Launch Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "BasicApp" 120

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="