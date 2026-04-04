#!/bin/bash
echo "=== Exporting reduce_apk_size result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/NewsReaderApp"
BLOAT_FILE="$PROJECT_DIR/app/src/main/assets/onboarding_deprecated.mp4"
APK_PATH="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check if bloat file still exists
BLOAT_FILE_EXISTS="false"
if [ -f "$BLOAT_FILE" ]; then
    BLOAT_FILE_EXISTS="true"
    echo "Bloat file still found."
else
    echo "Bloat file removed."
fi

# 3. Check if project builds and get new APK size
BUILD_SUCCESS="false"
APK_SIZE_BYTES=0

echo "Running verification build..."
cd "$PROJECT_DIR"
# Clean first to ensure we aren't measuring an old artifact
# But don't do full clean to save time, just delete the apk
rm -f "$APK_PATH"

BUILD_OUTPUT=$(su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew assembleDebug --no-daemon" 2>&1)
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
    if [ -f "$APK_PATH" ]; then
        APK_SIZE_BYTES=$(stat -c %s "$APK_PATH")
    fi
else
    echo "Build failed."
fi

# 4. Check if Android Studio is running (anti-gaming: did they assume they could just delete file in terminal?)
APP_RUNNING=$(pgrep -f "android" > /dev/null && echo "true" || echo "false")

# 5. Escape output for JSON
BUILD_OUTPUT_ESCAPED=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()[-500:]))" 2>/dev/null || echo '""')

# 6. Write result JSON
cat > /tmp/task_result_temp.json << EOF
{
    "bloat_file_exists": $BLOAT_FILE_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "apk_size_bytes": $APK_SIZE_BYTES,
    "app_running": $APP_RUNNING,
    "build_output_tail": $BUILD_OUTPUT_ESCAPED,
    "task_timestamp": $(date +%s)
}
EOF

# Safe move
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. APK Size: $APK_SIZE_BYTES bytes"