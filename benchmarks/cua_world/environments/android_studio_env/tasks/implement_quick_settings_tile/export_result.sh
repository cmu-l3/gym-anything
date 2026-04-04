#!/bin/bash
echo "=== Exporting implement_quick_settings_tile result ==="

source /workspace/scripts/task_utils.sh

# Project configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/DevTools"
SERVICE_FILE="$PROJECT_DIR/app/src/main/java/com/example/devtools/DemoModeTileService.kt"
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result variables
SERVICE_EXISTS="false"
SERVICE_CONTENT=""
MANIFEST_CONTENT=""
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

# 1. Check Service File
if [ -f "$SERVICE_FILE" ]; then
    SERVICE_EXISTS="true"
    SERVICE_CONTENT=$(cat "$SERVICE_FILE" 2>/dev/null)
fi

# 2. Check Manifest File
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_FILE" 2>/dev/null)
fi

# 3. Attempt to Build (to verify code correctness)
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR" && \
    chmod +x gradlew 2>/dev/null || true
    
    # Run assembleDebug
    # We use 'assembleDebug' to verify the code compiles and manifest is valid
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 50 /tmp/gradle_output.log 2>/dev/null)
fi

# 4. JSON Helper for escaping
escape_json() {
    printf '%s' "$1" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

SERVICE_CONTENT_JSON=$(escape_json "$SERVICE_CONTENT")
MANIFEST_CONTENT_JSON=$(escape_json "$MANIFEST_CONTENT")
BUILD_OUTPUT_JSON=$(escape_json "$BUILD_OUTPUT")

# 5. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_exists": $SERVICE_EXISTS,
    "service_content": $SERVICE_CONTENT_JSON,
    "manifest_content": $MANIFEST_CONTENT_JSON,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_JSON,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"