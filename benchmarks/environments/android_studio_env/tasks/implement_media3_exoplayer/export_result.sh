#!/bin/bash
echo "=== Exporting implement_media3_exoplayer result ==="

source /workspace/scripts/task_utils.sh

# Project Configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/VideoPlayerApp"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/videoplayer/MainActivity.kt"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check build.gradle.kts for dependencies
DEPENDENCIES_ADDED="false"
if grep -q "androidx.media3:media3-exoplayer" "$BUILD_GRADLE" && \
   grep -q "androidx.media3:media3-ui" "$BUILD_GRADLE"; then
    DEPENDENCIES_ADDED="true"
fi

# 3. Check layout for PlayerView
LAYOUT_CONFIGURED="false"
if grep -q "androidx.media3.ui.PlayerView" "$LAYOUT_FILE"; then
    LAYOUT_CONFIGURED="true"
fi

# 4. Attempt to compile
echo "Running Gradle build..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    chmod +x "$PROJECT_DIR/gradlew"
    cd "$PROJECT_DIR"
    
    # Run assembleDebug
    # We use a timeout to prevent hanging if agent left gradle in bad state
    timeout 300s su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR; ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
else
    echo "Gradle wrapper not found" > /tmp/gradle_build.log
fi

# 5. Read file contents for verifier analysis
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

MAIN_ACTIVITY_CONTENT=""
if [ -f "$MAIN_ACTIVITY" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY")
fi

BUILD_LOG=""
if [ -f /tmp/gradle_build.log ]; then
    BUILD_LOG=$(tail -n 50 /tmp/gradle_build.log)
fi

# 6. Generate Result JSON
# Using python to ensure safe JSON generation
python3 -c "
import json
import os
import sys

result = {
    'dependencies_added': '$DEPENDENCIES_ADDED' == 'true',
    'layout_configured': '$LAYOUT_CONFIGURED' == 'true',
    'build_success': '$BUILD_SUCCESS' == 'true',
    'build_gradle_content': sys.argv[1],
    'layout_content': sys.argv[2],
    'main_activity_content': sys.argv[3],
    'build_log': sys.argv[4],
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" "$BUILD_GRADLE_CONTENT" "$LAYOUT_CONTENT" "$MAIN_ACTIVITY_CONTENT" "$BUILD_LOG"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="