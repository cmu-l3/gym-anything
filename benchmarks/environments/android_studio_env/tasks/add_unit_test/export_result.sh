#!/bin/bash
echo "=== Exporting add_unit_test result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/NotepadApp"
TEST_DIR="$PROJECT_DIR/app/src/test/java/com/example/notepad"
TEST_RESULTS_DIR="$PROJECT_DIR/app/build/test-results/testDebugUnitTest"
TEST_REPORT_DIR="$PROJECT_DIR/app/build/reports/tests/testDebugUnitTest"

# Check for each expected test file
VALIDATOR_TEST_EXISTS="false"
FORMATTER_TEST_EXISTS="false"
NOTE_TEST_EXISTS="false"
VALIDATOR_TEST_CONTENT=""
FORMATTER_TEST_CONTENT=""
NOTE_TEST_CONTENT=""

if [ -f "$TEST_DIR/NoteValidatorTest.kt" ]; then
    VALIDATOR_TEST_EXISTS="true"
    VALIDATOR_TEST_CONTENT=$(cat "$TEST_DIR/NoteValidatorTest.kt" 2>/dev/null | head -200)
fi

if [ -f "$TEST_DIR/NoteFormatterTest.kt" ]; then
    FORMATTER_TEST_EXISTS="true"
    FORMATTER_TEST_CONTENT=$(cat "$TEST_DIR/NoteFormatterTest.kt" 2>/dev/null | head -200)
fi

if [ -f "$TEST_DIR/NoteTest.kt" ]; then
    NOTE_TEST_EXISTS="true"
    NOTE_TEST_CONTENT=$(cat "$TEST_DIR/NoteTest.kt" 2>/dev/null | head -200)
fi

# Count @Test annotations in each file
VALIDATOR_TEST_COUNT=0
FORMATTER_TEST_COUNT=0
NOTE_TEST_COUNT=0

if [ "$VALIDATOR_TEST_EXISTS" = "true" ]; then
    VALIDATOR_TEST_COUNT=$(grep -c '@Test' "$TEST_DIR/NoteValidatorTest.kt" 2>/dev/null || echo "0")
fi
if [ "$FORMATTER_TEST_EXISTS" = "true" ]; then
    FORMATTER_TEST_COUNT=$(grep -c '@Test' "$TEST_DIR/NoteFormatterTest.kt" 2>/dev/null || echo "0")
fi
if [ "$NOTE_TEST_EXISTS" = "true" ]; then
    NOTE_TEST_COUNT=$(grep -c '@Test' "$TEST_DIR/NoteTest.kt" 2>/dev/null || echo "0")
fi

# Try to run the tests via Gradle
echo "Running ./gradlew test..."
GRADLE_EXIT_CODE=1
GRADLE_OUTPUT=""
TESTS_RAN="false"

cd "$PROJECT_DIR"
GRADLE_OUTPUT=$(su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; ./gradlew testDebugUnitTest --no-daemon 2>&1" 2>&1) || true
GRADLE_EXIT_CODE=$?

if [ $GRADLE_EXIT_CODE -eq 0 ]; then
    TESTS_RAN="true"
fi

# Save gradle output for debugging
echo "$GRADLE_OUTPUT" > /tmp/gradle_test_output.log 2>/dev/null || true

# Parse test report XML files
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
TEST_REPORTS_FOUND="false"

if [ -d "$TEST_RESULTS_DIR" ]; then
    TEST_REPORTS_FOUND="true"

    # Parse each XML result file
    for xml_file in "$TEST_RESULTS_DIR"/*.xml; do
        if [ -f "$xml_file" ]; then
            # Extract test counts from XML attributes: tests="N" failures="N" errors="N" skipped="N"
            FILE_TESTS=$(grep -oP 'tests="\K[0-9]+' "$xml_file" 2>/dev/null | head -1 || echo "0")
            FILE_FAILURES=$(grep -oP 'failures="\K[0-9]+' "$xml_file" 2>/dev/null | head -1 || echo "0")
            FILE_ERRORS=$(grep -oP 'errors="\K[0-9]+' "$xml_file" 2>/dev/null | head -1 || echo "0")
            FILE_SKIPPED=$(grep -oP 'skipped="\K[0-9]+' "$xml_file" 2>/dev/null | head -1 || echo "0")

            TOTAL_TESTS=$((TOTAL_TESTS + FILE_TESTS))
            FAILED_TESTS=$((FAILED_TESTS + FILE_FAILURES + FILE_ERRORS))
            SKIPPED_TESTS=$((SKIPPED_TESTS + FILE_SKIPPED))
        fi
    done

    PASSED_TESTS=$((TOTAL_TESTS - FAILED_TESTS - SKIPPED_TESTS))
    if [ $PASSED_TESTS -lt 0 ]; then
        PASSED_TESTS=0
    fi
fi

# Check if gradle output indicates compilation success
COMPILES="false"
if echo "$GRADLE_OUTPUT" | grep -q "BUILD SUCCESSFUL"; then
    COMPILES="true"
elif echo "$GRADLE_OUTPUT" | grep -q "compileDebugUnitTestKotlin.*UP-TO-DATE\|compileDebugUnitTestKotlin.*SUCCESS"; then
    COMPILES="true"
fi

# Also check: if tests ran at all, compilation must have succeeded
if [ "$TESTS_RAN" = "true" ] && [ $TOTAL_TESTS -gt 0 ]; then
    COMPILES="true"
fi

# Escape content for JSON (replace newlines, quotes, backslashes)
escape_json() {
    local input="$1"
    printf '%s' "$input" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

VALIDATOR_CONTENT_JSON=$(escape_json "$VALIDATOR_TEST_CONTENT")
FORMATTER_CONTENT_JSON=$(escape_json "$FORMATTER_TEST_CONTENT")
NOTE_CONTENT_JSON=$(escape_json "$NOTE_TEST_CONTENT")

RESULT_JSON=$(cat << EOF
{
    "validator_test_exists": $VALIDATOR_TEST_EXISTS,
    "formatter_test_exists": $FORMATTER_TEST_EXISTS,
    "note_test_exists": $NOTE_TEST_EXISTS,
    "validator_test_count": $VALIDATOR_TEST_COUNT,
    "formatter_test_count": $FORMATTER_TEST_COUNT,
    "note_test_count": $NOTE_TEST_COUNT,
    "validator_test_content": $VALIDATOR_CONTENT_JSON,
    "formatter_test_content": $FORMATTER_CONTENT_JSON,
    "note_test_content": $NOTE_CONTENT_JSON,
    "tests_compile": $COMPILES,
    "tests_ran": $TESTS_RAN,
    "gradle_exit_code": $GRADLE_EXIT_CODE,
    "test_reports_found": $TEST_REPORTS_FOUND,
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "skipped_tests": $SKIPPED_TESTS,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="
echo "Validator tests: $VALIDATOR_TEST_COUNT, Formatter tests: $FORMATTER_TEST_COUNT, Note tests: $NOTE_TEST_COUNT"
echo "Gradle exit code: $GRADLE_EXIT_CODE, Total: $TOTAL_TESTS, Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
