#!/bin/bash
set -e
echo "=== Exporting refactor_field_injection result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-orders"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/example/orders/service/OrderProcessingService.java"

# Capture task end time and screenshot
TASK_END_TIME=$(date +%s)
take_screenshot /tmp/task_final.png

# 1. Run Compilation and Tests
echo "Running compilation and tests..."
cd "$PROJECT_DIR"
# Clean output first
rm -f /tmp/maven_output.log

# We use mvn test, which implies compile.
set +e # Don't exit on test fail, we want to capture the failure
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test > /tmp/maven_output.log 2>&1
MVN_EXIT_CODE=$?
set -e

# 2. Analyze Maven Output
BUILD_SUCCESS="false"
TESTS_PASSED="false"

if [ $MVN_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
    TESTS_PASSED="true"
else
    # Check if it was just a test failure or a build failure
    if grep -q "COMPILATION ERROR" /tmp/maven_output.log; then
        BUILD_SUCCESS="false"
    elif grep -q "BUILD SUCCESS" /tmp/maven_output.log; then
        # Rare case where build success but exit code non-zero? usually means test fail
        BUILD_SUCCESS="true"
    fi
fi

# 3. Read File Content
FILE_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    FILE_CONTENT=$(cat "$TARGET_FILE")
fi

# 4. Check File Modification
FILE_MODIFIED="false"
if [ -f /tmp/initial_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 5. Extract Maven Log Tail
MVN_LOG_TAIL=$(tail -n 20 /tmp/maven_output.log | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
FILE_CONTENT_JSON=$(echo "$FILE_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# 6. Create Result JSON
cat > /tmp/result_data.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "task_end_time": $TASK_END_TIME,
    "build_success": $BUILD_SUCCESS,
    "tests_passed": $TESTS_PASSED,
    "file_modified": $FILE_MODIFIED,
    "target_file_content": $FILE_CONTENT_JSON,
    "maven_log_tail": $MVN_LOG_TAIL,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"