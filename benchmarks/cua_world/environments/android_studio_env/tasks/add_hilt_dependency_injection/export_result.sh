#!/bin/bash
set -e

echo "=== Exporting add_hilt_dependency_injection result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/BookTrackerApp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# === Capture file contents for verification ===

# We will read files directly in Python via copy_from_env, but we can also
# store key indicators in the result JSON for easier debugging.

# 1. Run Gradle Build to check if project compiles
echo "Running Gradle build..."
BUILD_SUCCESS="false"
BUILD_OUTPUT_FILE="/tmp/build_output.log"

# Use compileDebugJavaWithJavac to save time vs full assemble, 
# but for Hilt we need kapt processing, so assembleDebug is safer.
cd "$PROJECT_DIR"
if su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > "$BUILD_OUTPUT_FILE" 2>&1; then
    BUILD_SUCCESS="true"
    echo "Build succeeded"
else
    echo "Build failed"
fi

# 2. Check for existence of BookTrackerApplication.kt
APP_CLASS_EXISTS="false"
if [ -f "$PROJECT_DIR/app/src/main/java/com/example/booktracker/BookTrackerApplication.kt" ]; then
    APP_CLASS_EXISTS="true"
fi

# 3. Check modification times vs task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MAIN_ACTIVITY_MTIME=$(stat -c %Y "$PROJECT_DIR/app/src/main/java/com/example/booktracker/MainActivity.kt" 2>/dev/null || echo "0")
FILES_MODIFIED="false"
if [ "$MAIN_ACTIVITY_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 4. Prepare Result JSON
# Escaping for JSON string safety
BUILD_LOG_TAIL=$(tail -n 20 "$BUILD_OUTPUT_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Create JSON
cat > /tmp/task_result.json << EOF
{
    "build_success": $BUILD_SUCCESS,
    "app_class_exists": $APP_CLASS_EXISTS,
    "files_modified": $FILES_MODIFIED,
    "build_log_tail": $BUILD_LOG_TAIL,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json