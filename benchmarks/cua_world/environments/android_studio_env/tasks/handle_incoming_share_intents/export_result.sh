#!/bin/bash
echo "=== Exporting Handle Incoming Share Intents result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/AndroidStudioProjects/SimpleNotes"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
ACTIVITY_PATH="$PROJECT_DIR/app/src/main/java/com/example/simplenotes/MainActivity.kt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result variables
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
ACTIVITY_EXISTS="false"
ACTIVITY_CONTENT=""
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

# 1. Capture File Content
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

if [ -f "$ACTIVITY_PATH" ]; then
    ACTIVITY_EXISTS="true"
    ACTIVITY_CONTENT=$(cat "$ACTIVITY_PATH")
fi

# 2. Verify Build
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running gradle build verification..."
    cd "$PROJECT_DIR"
    
    # Run assembleDebug to check if code compiles
    chmod +x gradlew
    
    # Use ga user context for build to match environment
    su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && export ANDROID_SDK_ROOT=/opt/android-sdk && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Capture tail of build log
    BUILD_OUTPUT=$(tail -n 50 /tmp/gradle_build_output.log)
fi

# 3. Create JSON Result
# Helper to safely escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

MANIFEST_JSON=$(escape_json "$MANIFEST_CONTENT")
ACTIVITY_JSON=$(escape_json "$ACTIVITY_CONTENT")
BUILD_OUT_JSON=$(escape_json "$BUILD_OUTPUT")

JSON_CONTENT=$(cat <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content": $MANIFEST_JSON,
    "activity_exists": $ACTIVITY_EXISTS,
    "activity_content": $ACTIVITY_JSON,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_JSON
}
EOF
)

write_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="