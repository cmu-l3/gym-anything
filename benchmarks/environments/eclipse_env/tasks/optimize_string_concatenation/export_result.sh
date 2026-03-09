#!/bin/bash
echo "=== Exporting optimize_string_concatenation result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/MediLogExport"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/medilog/export/HL7MessageBuilder.java"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests (to verify functional correctness)
echo "Running JUnit tests..."
TEST_OUTPUT_FILE="/tmp/mvn_test_output.txt"
cd "$PROJECT_DIR"
# Run Maven test, capture output. We use 'test' goal.
su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; mvn test" > "$TEST_OUTPUT_FILE" 2>&1
mvn_exit_code=$?

echo "Maven exit code: $mvn_exit_code"

# 2. Check for Test Results
TESTS_PASSED="false"
if [ $mvn_exit_code -eq 0 ]; then
    # Double check output for "BUILD SUCCESS" and "Tests run: ..., Failures: 0"
    if grep -q "BUILD SUCCESS" "$TEST_OUTPUT_FILE"; then
        TESTS_PASSED="true"
    fi
fi

# 3. Read Source File Content
SOURCE_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    SOURCE_CONTENT=$(cat "$TARGET_FILE")
fi

# 4. Check File Modification Time
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")

if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 5. Check if initial hash differs (redundant but explicit)
CURRENT_HASH=$(sha256sum "$TARGET_FILE" 2>/dev/null)
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null)
HASH_CHANGED="false"
if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
    HASH_CHANGED="true"
fi

# 6. Escape content for JSON
SOURCE_ESCAPED=$(echo "$SOURCE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
TEST_LOG_ESCAPED=$(cat "$TEST_OUTPUT_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# 7. Create Result JSON
cat > /tmp/temp_result.json << EOF
{
    "file_exists": true,
    "file_modified": $FILE_MODIFIED,
    "hash_changed": $HASH_CHANGED,
    "tests_passed": $TESTS_PASSED,
    "source_content": $SOURCE_ESCAPED,
    "test_output": $TEST_LOG_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

write_json_result "$(cat /tmp/temp_result.json)" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="