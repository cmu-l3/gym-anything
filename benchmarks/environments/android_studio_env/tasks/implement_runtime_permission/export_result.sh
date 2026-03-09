#!/bin/bash
echo "=== Exporting implement_runtime_permission result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/QuickSnap"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
MAIN_ACTIVITY_PATH="$PROJECT_DIR/app/src/main/java/com/example/quicksnap/MainActivity.kt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Read Manifest Content
MANIFEST_CONTENT=""
MANIFEST_EXISTS="false"
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

# 2. Read Activity Content
ACTIVITY_CONTENT=""
ACTIVITY_EXISTS="false"
if [ -f "$MAIN_ACTIVITY_PATH" ]; then
    ACTIVITY_EXISTS="true"
    ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY_PATH")
fi

# 3. Check Compilation
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting build..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    
    # Use compileDebugKotlin for speed, or assembleDebug for full check
    if su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew compileDebugKotlin --no-daemon" > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    else
        BUILD_SUCCESS="false"
    fi
    BUILD_OUTPUT=$(tail -n 20 /tmp/gradle_build.log)
fi

# 4. JSON Export
# Use python for safe JSON escaping
python3 -c "
import json
import os

manifest_content = '''$MANIFEST_CONTENT'''
activity_content = '''$ACTIVITY_CONTENT'''
build_output = '''$BUILD_OUTPUT'''

result = {
    'manifest_exists': '$MANIFEST_EXISTS' == 'true',
    'activity_exists': '$ACTIVITY_EXISTS' == 'true',
    'manifest_content': manifest_content,
    'activity_content': activity_content,
    'build_success': '$BUILD_SUCCESS' == 'true',
    'build_output': build_output
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"