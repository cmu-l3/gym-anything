#!/bin/bash
echo "=== Exporting implement_rtl_support result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/GlobalNews"
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_profile.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Attempt Build (Check if changes broke compilation)
echo "Running Gradle build..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    # Use assembleDebug to verify resources link correctly
    if su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_output.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi

# 2. Capture File Contents
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_FILE")
fi

LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

# 3. Create Result JSON
# Use Python to safely escape JSON strings
TEMP_JSON=$(mktemp)
python3 -c "
import json
import os

manifest_content = '''$MANIFEST_CONTENT'''
layout_content = '''$LAYOUT_CONTENT'''
build_success = '$BUILD_SUCCESS' == 'true'

result = {
    'manifest_content': manifest_content,
    'layout_content': layout_content,
    'build_success': build_success,
    'timestamp': $(date +%s)
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move result to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="