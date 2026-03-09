#!/bin/bash
echo "=== Exporting Espresso UI Tests Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/TipCalculatorApp"
TEST_DIR="$PROJECT_DIR/app/src/androidTest/java/com/example/tipcalculator"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Attempt to build and check for Android Test compilation
echo "Running assembleAndroidTest..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    
    # We use a timeout to prevent hanging if Gradle gets stuck
    timeout 300 su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleAndroidTest --no-daemon" > /tmp/gradle_test_build.log 2>&1
    RET=$?
    
    if [ $RET -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 50 /tmp/gradle_test_build.log)
fi

# 2. Extract build.gradle content
BUILD_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/app/build.gradle" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle")
fi

# 3. Find test file and extract content
TEST_FILE_EXISTS="false"
TEST_FILE_CONTENT=""
TEST_FILE_PATH=""

# Find any Kotlin file in the androidTest directory
FOUND_TEST=$(find "$TEST_DIR" -name "*Test.kt" | head -n 1)

if [ -n "$FOUND_TEST" ]; then
    TEST_FILE_EXISTS="true"
    TEST_FILE_PATH="$FOUND_TEST"
    TEST_FILE_CONTENT=$(cat "$FOUND_TEST")
fi

# 4. Check timestamps for anti-gaming (file creation > task start)
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ "$TEST_FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$TEST_FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Prepare JSON Result
# Helper to escape JSON string safely
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

ESC_BUILD_GRADLE=$(escape_json "$BUILD_GRADLE_CONTENT")
ESC_TEST_CONTENT=$(escape_json "$TEST_FILE_CONTENT")
ESC_BUILD_OUTPUT=$(escape_json "$BUILD_OUTPUT")

cat > /tmp/json_temp.json <<EOF
{
  "build_success": $BUILD_SUCCESS,
  "test_file_exists": $TEST_FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "build_gradle_content": $ESC_BUILD_GRADLE,
  "test_file_content": $ESC_TEST_CONTENT,
  "build_output": $ESC_BUILD_OUTPUT,
  "screenshot_path": "/tmp/task_final.png",
  "task_start_time": $TASK_START,
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/json_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"