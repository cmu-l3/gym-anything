#!/bin/bash
echo "=== Exporting implement_parcelable_intent result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
PROJECT_DIR="/home/ga/AndroidStudioProjects/InventoryManager"
ITEM_FILE="$PROJECT_DIR/app/src/main/java/com/example/inventory/model/Item.kt"
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Attempt to Build the Project (Verification)
# We use the gradle wrapper if available, or fall back to system gradle.
# Since we created a dummy gradlew, we might need to rely on the environment's gradle if the wrapper wasn't fully set up.
# However, `setup_task.sh` created gradle-wrapper.properties, so if the environment has a global gradle, we can use `gradle wrapper` to fix it,
# OR we can just try running `gradle assembleDebug`.
# The environment `install_android_studio.sh` installs Android Studio which typically bundles plugins, but for command line we want reliability.
# Let's assume the agent might have fixed the wrapper or we use the system one.

echo "Running Gradle Build..."
cd "$PROJECT_DIR"

# Ensure gradlew exists and is executable (agent might have generated it)
if [ ! -f "./gradlew" ] || [ ! -x "./gradlew" ]; then
    gradle wrapper --gradle-version 8.2 2>/dev/null || true
fi

BUILD_SUCCESS="false"
BUILD_OUTPUT=""

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=/opt/android-sdk

# Run build
if ./gradlew assembleDebug --no-daemon > /tmp/build_output.log 2>&1; then
    BUILD_SUCCESS="true"
    echo "Build Succeeded"
else
    echo "Build Failed"
fi
BUILD_OUTPUT=$(cat /tmp/build_output.log | tail -n 50)

# 2. Capture File Contents
ITEM_CONTENT=""
if [ -f "$ITEM_FILE" ]; then
    ITEM_CONTENT=$(cat "$ITEM_FILE")
fi

BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_FILE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_FILE")
fi

# 3. Check modification times
FILE_MODIFIED="false"
if [ -f "$ITEM_FILE" ]; then
    ITEM_MTIME=$(stat -c %Y "$ITEM_FILE" 2>/dev/null || echo "0")
    if [ "$ITEM_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. JSON Generation
# Python helper to escape JSON strings safely
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

ITEM_ESCAPED=$(escape_json "$ITEM_CONTENT")
BUILD_GRADLE_ESCAPED=$(escape_json "$BUILD_GRADLE_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

JSON_CONTENT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_success": $BUILD_SUCCESS,
    "file_modified_during_task": $FILE_MODIFIED,
    "item_content": $ITEM_ESCAPED,
    "build_gradle_content": $BUILD_GRADLE_ESCAPED,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "Result exported to /tmp/task_result.json"