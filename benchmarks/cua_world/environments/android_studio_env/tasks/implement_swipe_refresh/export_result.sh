#!/bin/bash
echo "=== Exporting implement_swipe_refresh result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/AndroidStudioProjects/BookStream"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/bookstream/MainActivity.kt"

# Initialize variables
BUILD_GRADLE_EXISTS="false"
LAYOUT_FILE_EXISTS="false"
MAIN_ACTIVITY_EXISTS="false"
BUILD_SUCCESS="false"
BUILD_GRADLE_CONTENT=""
LAYOUT_CONTENT=""
MAIN_ACTIVITY_CONTENT=""

# Check File Existence & Read Content
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_EXISTS="true"
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_FILE_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

if [ -f "$MAIN_ACTIVITY" ]; then
    MAIN_ACTIVITY_EXISTS="true"
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY")
fi

# Try to compile to verify syntax correctness
# We use compileDebugKotlin to save time compared to full assemble
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle compilation..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build successful"
    else
        echo "Build failed"
    fi
fi

# Helper for JSON escaping
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

BUILD_GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
LAYOUT_JSON=$(escape_json "$LAYOUT_CONTENT")
MAIN_ACTIVITY_JSON=$(escape_json "$MAIN_ACTIVITY_CONTENT")
GRADLE_OUTPUT_JSON=$(escape_json "$(cat /tmp/gradle_output.log 2>/dev/null | tail -50)")

# Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "build_gradle_exists": $BUILD_GRADLE_EXISTS,
    "layout_file_exists": $LAYOUT_FILE_EXISTS,
    "main_activity_exists": $MAIN_ACTIVITY_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "build_gradle_content": $BUILD_GRADLE_JSON,
    "layout_content": $LAYOUT_JSON,
    "main_activity_content": $MAIN_ACTIVITY_JSON,
    "gradle_output": $GRADLE_OUTPUT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Save result safely
write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="