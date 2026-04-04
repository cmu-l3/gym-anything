#!/bin/bash
echo "=== Exporting add_dependency_implement result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/student-records"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture file contents
POM_CONTENT=""
IMPL_CONTENT=""

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null)
fi

if [ -f "$PROJECT_DIR/src/main/java/com/example/export/JsonExporter.java" ]; then
    IMPL_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/example/export/JsonExporter.java" 2>/dev/null)
fi

# Check file modification timestamps
POM_MTIME=$(stat -c %Y "$PROJECT_DIR/pom.xml" 2>/dev/null || echo "0")
IMPL_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/example/export/JsonExporter.java" 2>/dev/null || echo "0")

POM_MODIFIED="false"
IMPL_MODIFIED="false"

if [ "$POM_MTIME" -gt "$TASK_START" ]; then POM_MODIFIED="true"; fi
if [ "$IMPL_MTIME" -gt "$TASK_START" ]; then IMPL_MODIFIED="true"; fi

# Run Maven tests
TEST_RESULT="unknown"
COMPILE_SUCCESS="false"
TEST_OUTPUT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_ERRORS=0

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    
    # Run tests and capture output
    echo "Running tests..."
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dtest=JsonExporterTest 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        TEST_RESULT="pass"
        COMPILE_SUCCESS="true"
    else
        TEST_RESULT="fail"
        # Check if it was a compilation error
        if echo "$TEST_OUTPUT" | grep -q "BUILD SUCCESS"; then
            COMPILE_SUCCESS="true"
        elif ! echo "$TEST_OUTPUT" | grep -q "Compilation failure"; then
             # If tests failed but build didn't explicitly say compilation failure, 
             # check if classes exist
             if [ -f "$PROJECT_DIR/target/classes/com/example/export/JsonExporter.class" ]; then
                 COMPILE_SUCCESS="true"
             fi
        fi
    fi

    # Parse Surefire reports for detailed stats
    REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
    if [ -d "$REPORT_DIR" ]; then
        for report in "$REPORT_DIR"/*.xml; do
            if [ -f "$report" ]; then
                TR=$(grep -oP 'tests="\K[0-9]+' "$report" | head -1)
                TF=$(grep -oP 'failures="\K[0-9]+' "$report" | head -1)
                TE=$(grep -oP 'errors="\K[0-9]+' "$report" | head -1)
                TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
                TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
                TESTS_ERRORS=$((TESTS_ERRORS + ${TE:-0}))
            fi
        done
        TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_ERRORS))
    fi
fi

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
IMPL_ESCAPED=$(echo "$IMPL_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Build JSON result
RESULT_JSON=$(cat << EOF
{
    "pom_content": $POM_ESCAPED,
    "impl_content": $IMPL_ESCAPED,
    "pom_modified": $POM_MODIFIED,
    "impl_modified": $IMPL_MODIFIED,
    "compile_success": $COMPILE_SUCCESS,
    "test_result": "$TEST_RESULT",
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_errors": $TESTS_ERRORS,
    "test_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Safe write to /tmp/task_result.json
write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="