#!/bin/bash
set -e
echo "=== Exporting implement_room_migration result ==="

source /workspace/scripts/task_utils.sh

# Project config
PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskMaster"
PACKAGE_PATH="app/src/main/java/com/example/taskmaster/data"
TASK_FILE="$PROJECT_DIR/$PACKAGE_PATH/Task.kt"
DB_FILE="$PROJECT_DIR/$PACKAGE_PATH/AppDatabase.kt"
RESULT_JSON="/tmp/task_result.json"

# Capture final state
take_screenshot /tmp/task_end.png

# Initialize result vars
TASK_KT_EXISTS="false"
DB_FILE_EXISTS="false"
TASK_KT_CONTENT=""
DB_FILE_CONTENT=""
BUILD_SUCCESS="false"
TESTS_PASSED="false"
MIGRATION_REGISTERED="false"

# 1. Read File Contents
if [ -f "$TASK_FILE" ]; then
    TASK_KT_EXISTS="true"
    TASK_KT_CONTENT=$(cat "$TASK_FILE")
fi

if [ -f "$DB_FILE" ]; then
    DB_FILE_EXISTS="true"
    DB_FILE_CONTENT=$(cat "$DB_FILE")
fi

# 2. Check for compile/test success
# We attempt to run the test provided. If it passes, high confidence the task is done.
echo "Running tests..."
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    
    # Run test
    set +e
    GRADLE_OUTPUT=$(su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; ./gradlew :app:testDebugUnitTest --no-daemon 2>&1")
    EXIT_CODE=$?
    set -e
    
    echo "$GRADLE_OUTPUT" > /tmp/gradle_test_output.log
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
        # Check if tests actually ran and passed
        if echo "$GRADLE_OUTPUT" | grep -q "BUILD SUCCESSFUL"; then
            TESTS_PASSED="true"
        fi
    fi
else
    echo "gradlew not found, skipping dynamic test check"
fi

# 3. Check modification times
TASK_MTIME=$(stat -c %Y "$TASK_FILE" 2>/dev/null || echo "0")
DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILES_MODIFIED="false"
if [ "$TASK_MTIME" -gt "$START_TIME" ] && [ "$DB_MTIME" -gt "$START_TIME" ]; then
    FILES_MODIFIED="true"
fi

# 4. JSON Export
# Escape content helper
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

ESC_TASK_CONTENT=$(escape_json "$TASK_KT_CONTENT")
ESC_DB_CONTENT=$(escape_json "$DB_FILE_CONTENT")

cat > "$RESULT_JSON" <<EOF
{
    "task_kt_exists": $TASK_KT_EXISTS,
    "db_file_exists": $DB_FILE_EXISTS,
    "task_kt_content": $ESC_TASK_CONTENT,
    "db_file_content": $ESC_DB_CONTENT,
    "build_success": $BUILD_SUCCESS,
    "tests_passed": $TESTS_PASSED,
    "files_modified": $FILES_MODIFIED,
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": $(date +%s)
}
EOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true
echo "Export complete."