#!/bin/bash
echo "=== Exporting implement_encrypted_shared_preferences result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SecureNotes"
TOKEN_MANAGER_PATH="$PROJECT_DIR/app/src/main/java/com/example/securenotes/data/TokenManager.kt"
BUILD_GRADLE_PATH="$PROJECT_DIR/app/build.gradle.kts"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result variables
TOKEN_MANAGER_CONTENT=""
BUILD_GRADLE_CONTENT=""
TEST_SUCCESS="false"
TEST_OUTPUT=""
FILE_MODIFIED="false"

# 1. Read File Content
if [ -f "$TOKEN_MANAGER_PATH" ]; then
    TOKEN_MANAGER_CONTENT=$(cat "$TOKEN_MANAGER_PATH" 2>/dev/null)
fi

if [ -f "$BUILD_GRADLE_PATH" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE_PATH" 2>/dev/null)
fi

# 2. Check Timestamp (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_TIME=$(stat -c %Y "$TOKEN_MANAGER_PATH" 2>/dev/null || echo "0")
if [ "$FILE_TIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 3. Run Tests
echo "Running Unit Tests..."
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    
    # Run specific test
    TEST_CMD="./gradlew :app:testDebugUnitTest --tests com.example.securenotes.TokenManagerTest --no-daemon"
    
    TEST_OUTPUT=$(su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && $TEST_CMD 2>&1")
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        TEST_SUCCESS="true"
    fi
else
    TEST_OUTPUT="Gradle wrapper not found"
fi

# 4. Prepare JSON Result
# Helper to escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

ESC_TM_CONTENT=$(escape_json "$TOKEN_MANAGER_CONTENT")
ESC_BG_CONTENT=$(escape_json "$BUILD_GRADLE_CONTENT")
ESC_TEST_OUTPUT=$(escape_json "$TEST_OUTPUT")

JSON_CONTENT=$(cat <<EOF
{
    "token_manager_content": $ESC_TM_CONTENT,
    "build_gradle_content": $ESC_BG_CONTENT,
    "test_success": $TEST_SUCCESS,
    "test_output": $ESC_TEST_OUTPUT,
    "file_modified_during_task": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "=== Export complete ==="