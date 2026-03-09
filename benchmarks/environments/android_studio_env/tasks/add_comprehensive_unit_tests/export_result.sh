#!/bin/bash
echo "=== Exporting add_comprehensive_unit_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/FinancialCalcApp"
TEST_DIR="$PROJECT_DIR/app/src/test/java/com/example/financialcalc"

take_screenshot /tmp/task_end.png

# Find all test files created by the agent
TEST_FILES=$(find "$TEST_DIR" -name "*Test*.kt" -o -name "*Tests*.kt" -o -name "*Spec*.kt" 2>/dev/null | sort)
TEST_FILE_COUNT=$(echo "$TEST_FILES" | grep -c ".kt" 2>/dev/null || true)
[ -z "$TEST_FILE_COUNT" ] || ! [[ "$TEST_FILE_COUNT" =~ ^[0-9]+$ ]] && TEST_FILE_COUNT=0

# Read each test file content (up to 4 files)
TEST_CONTENTS=""
FILE_NAMES=""
idx=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    idx=$((idx+1))
    [ $idx -gt 4 ] && break
    content=$(cat "$f" 2>/dev/null)
    name=$(basename "$f")
    FILE_NAMES="$FILE_NAMES $name"
    TEST_CONTENTS="$TEST_CONTENTS\n\n// FILE: $name\n$content"
done <<< "$TEST_FILES"

# Run tests
TEST_SUCCESS="false"
TEST_PASSED=0
TEST_FAILED=0
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew test --no-daemon > /tmp/test_output.log 2>&1
    if [ $? -eq 0 ]; then
        TEST_SUCCESS="true"
    fi
    # Parse test results from XML if available
    XML_RESULTS=$(find "$PROJECT_DIR" -name "TEST-*.xml" 2>/dev/null | head -5)
    if [ -n "$XML_RESULTS" ]; then
        for xml in $XML_RESULTS; do
            p=$(grep -o 'tests="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
            f=$(grep -o 'failures="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
            e=$(grep -o 'errors="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
            TEST_PASSED=$((TEST_PASSED + ${p:-0}))
            TEST_FAILED=$((TEST_FAILED + ${f:-0} + ${e:-0}))
        done
    fi
fi
TEST_OUTPUT=$(tail -50 /tmp/test_output.log 2>/dev/null)

# Count @Test annotations in test files
TEST_ANNOTATION_COUNT=$(echo "$TEST_CONTENTS" | grep -c "@Test" 2>/dev/null || true)
[ -z "$TEST_ANNOTATION_COUNT" ] || ! [[ "$TEST_ANNOTATION_COUNT" =~ ^[0-9]+$ ]] && TEST_ANNOTATION_COUNT=0

# Escape for JSON
CONTENTS_ESC=$(printf '%s' "$TEST_CONTENTS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FILES_ESC=$(printf '%s' "$FILE_NAMES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
TEST_OUT_ESC=$(printf '%s' "$TEST_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "test_file_count": $TEST_FILE_COUNT,
    "test_file_names": $FILES_ESC,
    "test_contents": $CONTENTS_ESC,
    "test_annotation_count": $TEST_ANNOTATION_COUNT,
    "test_success": $TEST_SUCCESS,
    "test_passed": $TEST_PASSED,
    "test_failed": $TEST_FAILED,
    "test_output": $TEST_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
