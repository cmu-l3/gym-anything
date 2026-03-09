#!/bin/bash
echo "=== Exporting complete_todo_implementations result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/todo-utils"
PKG_DIR="src/main/java/com/example/utils"
TEST_PKG_DIR="src/test/java/com/example/utils"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run tests and capture output
echo "Running tests..."
TEST_OUTPUT=""
TEST_EXIT_CODE=0
cd "$PROJECT_DIR"
if [ -f "pom.xml" ]; then
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test 2>&1)
    TEST_EXIT_CODE=$?
else
    TEST_OUTPUT="Error: pom.xml not found"
    TEST_EXIT_CODE=1
fi

# 3. Read source files
STRING_UTILS_CONTENT=""
MATH_UTILS_CONTENT=""
[ -f "$PROJECT_DIR/$PKG_DIR/StringUtils.java" ] && STRING_UTILS_CONTENT=$(cat "$PROJECT_DIR/$PKG_DIR/StringUtils.java")
[ -f "$PROJECT_DIR/$PKG_DIR/MathUtils.java" ] && MATH_UTILS_CONTENT=$(cat "$PROJECT_DIR/$PKG_DIR/MathUtils.java")

# 4. Check file timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED="false"
SU_MTIME=$(stat -c %Y "$PROJECT_DIR/$PKG_DIR/StringUtils.java" 2>/dev/null || echo "0")
MU_MTIME=$(stat -c %Y "$PROJECT_DIR/$PKG_DIR/MathUtils.java" 2>/dev/null || echo "0")

if [ "$SU_MTIME" -gt "$TASK_START" ] || [ "$MU_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 5. Check Test Integrity
CURRENT_CHECKSUM_SU=$(md5sum "$PROJECT_DIR/$TEST_PKG_DIR/StringUtilsTest.java" 2>/dev/null | awk '{print $1}')
CURRENT_CHECKSUM_MU=$(md5sum "$PROJECT_DIR/$TEST_PKG_DIR/MathUtilsTest.java" 2>/dev/null | awk '{print $1}')

# JSON Escape Helper (Python one-liner)
json_escape() {
    echo "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

TEST_OUTPUT_JSON=$(json_escape "$TEST_OUTPUT")
SU_CONTENT_JSON=$(json_escape "$STRING_UTILS_CONTENT")
MU_CONTENT_JSON=$(json_escape "$MATH_UTILS_CONTENT")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "test_exit_code": $TEST_EXIT_CODE,
    "test_output": $TEST_OUTPUT_JSON,
    "string_utils_content": $SU_CONTENT_JSON,
    "math_utils_content": $MU_CONTENT_JSON,
    "files_modified_during_task": $FILES_MODIFIED,
    "current_test_checksums": {
        "StringUtilsTest": "$CURRENT_CHECKSUM_SU",
        "MathUtilsTest": "$CURRENT_CHECKSUM_MU"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"