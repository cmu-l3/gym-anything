#!/bin/bash
set -e

echo "=== Setting up import_gradle_project task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ------------------------------------------------------------------
# 1. Clean up previous /tmp artefacts
# ------------------------------------------------------------------
echo "Cleaning up previous task artefacts..."
rm -f /tmp/task_result.json /tmp/screenshot_*.png /tmp/android_studio_task.log 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Kill any existing Android Studio instance so we start fresh
# ------------------------------------------------------------------
echo "Killing any existing Android Studio processes..."
pkill -f "studio" 2>/dev/null || true
sleep 2

# ------------------------------------------------------------------
# 3. Prepare the project directory
# ------------------------------------------------------------------
PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
DATA_SOURCE="/workspace/data/SunflowerApp"

echo "Removing previous SunflowerApp if present..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Ensure parent directory exists
mkdir -p /home/ga/AndroidStudioProjects

echo "Copying project from $DATA_SOURCE to $PROJECT_DIR..."
cp -a "$DATA_SOURCE" "$PROJECT_DIR"

# ------------------------------------------------------------------
# 4. Set ownership and permissions
# ------------------------------------------------------------------
echo "Setting file permissions..."
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true
# Ensure directory execute bits are correct
find "$PROJECT_DIR" -type d -exec chmod 755 {} +

# ------------------------------------------------------------------
# 5. Remove any stale .idea / build caches so the IDE treats this
#    as a fresh import (the agent needs to open it in the IDE)
# ------------------------------------------------------------------
rm -rf "$PROJECT_DIR/.idea" 2>/dev/null || true
rm -rf "$PROJECT_DIR/.gradle" 2>/dev/null || true
rm -rf "$PROJECT_DIR/build" 2>/dev/null || true
rm -rf "$PROJECT_DIR/app/build" 2>/dev/null || true

# ------------------------------------------------------------------
# 6. Wait for Android Studio to be ready (Welcome screen)
# ------------------------------------------------------------------
echo "Waiting for Android Studio Welcome screen..."
wait_for_android_studio 60 || {
    echo "Android Studio not detected, launching it..."
    su - ga -c "export DISPLAY=:1; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; /opt/android-studio/bin/studio.sh > /tmp/android_studio_task.log 2>&1 &"
    sleep 15
    wait_for_android_studio 60 || echo "WARNING: Android Studio may not have started"
}

# ------------------------------------------------------------------
# 7. Dismiss any startup dialogs and focus the window
# ------------------------------------------------------------------
echo "Dismissing dialogs and focusing window..."
dismiss_dialogs 3
focus_android_studio_window || true

# ------------------------------------------------------------------
# 8. Take initial screenshot
# ------------------------------------------------------------------
echo "Taking initial screenshot..."
take_screenshot /tmp/screenshot_initial.png

echo "=== import_gradle_project setup complete ==="
echo "Project staged at: $PROJECT_DIR"
echo "The agent should open this project in Android Studio using the Open dialog."
