#!/bin/bash
echo "=== Exporting add_foreground_service task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/AndroidStudioProjects/SyncApp"
SERVICE_PATH="$PROJECT_DIR/app/src/main/java/com/example/syncapp/service/DataSyncService.kt"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Try to run Gradle build (verification compile) ---
echo "Running Gradle build to check for compilation errors..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true

    # Try a quick compile first
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && export ANDROID_SDK_ROOT=/opt/android-sdk && ./gradlew compileDebugKotlin --no-daemon" > /tmp/gradle_build_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build succeeded!"
    else
        echo "Build failed. Check /tmp/gradle_build_output.log"
    fi
    
    BUILD_OUTPUT=$(tail -50 /tmp/gradle_build_output.log 2>/dev/null)
fi

# --- Check file existence and changes ---

SERVICE_EXISTS="false"
if [ -f "$SERVICE_PATH" ]; then
    SERVICE_EXISTS="true"
fi

# Check for alternate service location
if [ "$SERVICE_EXISTS" = "false" ]; then
    ALTERNATE_PATH=$(find "$PROJECT_DIR/app/src/main/java" -name "DataSyncService.kt" | head -1)
    if [ -n "$ALTERNATE_PATH" ]; then
        SERVICE_EXISTS="true"
        SERVICE_PATH="$ALTERNATE_PATH"
        echo "Found service at alternate path: $ALTERNATE_PATH"
    fi
fi

# Compare manifest
MANIFEST_CHANGED="false"
if [ -f "$MANIFEST_PATH" ] && [ -f "/tmp/initial_manifest.xml" ]; then
    # Simple diff check
    if ! diff -q "$MANIFEST_PATH" "/tmp/initial_manifest.xml" >/dev/null; then
        MANIFEST_CHANGED="true"
    fi
fi

# Check for new Kotlin files
NEW_FILES_CREATED="false"
find "$PROJECT_DIR/app/src/main/java" -name "*.kt" | sort > /tmp/final_kotlin_files.txt
if ! diff -q /tmp/initial_kotlin_files.txt /tmp/final_kotlin_files.txt >/dev/null; then
    NEW_FILES_CREATED="true"
fi

# --- Escape content for JSON ---
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# --- Create result JSON ---
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_exists": $SERVICE_EXISTS,
    "service_path": "$SERVICE_PATH",
    "manifest_changed": $MANIFEST_CHANGED,
    "new_files_created": $NEW_FILES_CREATED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="