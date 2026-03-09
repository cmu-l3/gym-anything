#!/bin/bash
echo "=== Exporting Compare and Merge Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_ROOT="/home/ga/eclipse-workspace/MergeTask"
TARGET_FILE="$PROJECT_ROOT/src/main/java/com/acme/util/DataProcessor.java"
LIB_DIR="$PROJECT_ROOT/lib"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence and Timestamps
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Compile Verification (Independent of Eclipse)
COMPILE_SUCCESS="false"
COMPILE_MSG=""

if [ "$FILE_EXISTS" = "true" ]; then
    mkdir -p /tmp/compile_test
    # Try to compile the merged file
    if javac -d /tmp/compile_test "$TARGET_FILE" 2>/tmp/compile.log; then
        COMPILE_SUCCESS="true"
    else
        COMPILE_MSG=$(cat /tmp/compile.log | head -n 5)
    fi
fi

# 4. Run JUnit Tests (Independent of Eclipse)
TESTS_RUN=0
TESTS_FAILED=0
TESTS_PASSED=0
TEST_OUTPUT=""

if [ "$COMPILE_SUCCESS" = "true" ]; then
    # Compile the test file as well
    if javac -d /tmp/compile_test -cp "/tmp/compile_test:$LIB_DIR/junit-platform-console-standalone.jar" "$PROJECT_ROOT/src/test/java/com/acme/util/DataProcessorTest.java"; then
        
        # Run tests
        java -jar "$LIB_DIR/junit-platform-console-standalone.jar" \
            -cp "/tmp/compile_test" \
            -c com.acme.util.DataProcessorTest \
            --reports-dir /tmp/test-reports > /tmp/test_run.log 2>&1
            
        # Parse results
        if [ -f "/tmp/test-reports/TEST-junit-jupiter.xml" ]; then
            TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' /tmp/test-reports/TEST-junit-jupiter.xml | head -1)
            TESTS_FAILED=$(grep -oP 'failures="\K[0-9]+' /tmp/test-reports/TEST-junit-jupiter.xml | head -1)
            TESTS_ERRORS=$(grep -oP 'errors="\K[0-9]+' /tmp/test-reports/TEST-junit-jupiter.xml | head -1)
            TESTS_FAILED=$((TESTS_FAILED + TESTS_ERRORS))
            TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
        fi
        
        TEST_OUTPUT=$(cat /tmp/test_run.log | head -n 20)
    fi
fi

# 5. Read File Content for pattern verification
FILE_CONTENT=""
if [ "$FILE_EXISTS" = "true" ]; then
    FILE_CONTENT=$(cat "$TARGET_FILE")
fi

# 6. JSON Export
# Escape content for JSON safely
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
ESCAPED_COMPILE_MSG=$(echo "$COMPILE_MSG" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "compile_success": $COMPILE_SUCCESS,
    "compile_message": $ESCAPED_COMPILE_MSG,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "file_content": $ESCAPED_CONTENT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json