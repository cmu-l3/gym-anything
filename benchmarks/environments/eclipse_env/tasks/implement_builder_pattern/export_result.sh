#!/bin/bash
echo "=== Exporting implement_builder_pattern result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/hr-core"
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/acme/hr/model/Employee.java"
TEST_FILE="$PROJECT_DIR/src/test/java/com/acme/hr/model/EmployeeBuilderTest.java"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence and timestamps
SOURCE_EXISTS="false"
SOURCE_MODIFIED="false"
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_EXISTS="true"
    MTIME=$(stat -c %Y "$SOURCE_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SOURCE_MODIFIED="true"
    fi
fi

TEST_EXISTS="false"
TEST_CREATED="false"
if [ -f "$TEST_FILE" ]; then
    TEST_EXISTS="true"
    MTIME=$(stat -c %Y "$TEST_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TEST_CREATED="true"
    fi
fi

# 2. Run Maven verification (Ground Truth Check)
# We run this to verify the code actually compiles and passes tests, 
# independent of what the agent sees in Eclipse.
echo "Running Maven verification..."
cd "$PROJECT_DIR"

COMPILE_SUCCESS="false"
TEST_SUCCESS="false"
TESTS_RUN=0
TESTS_FAILURES=0
TESTS_ERRORS=0

# Clean compile
if sudo -u ga mvn clean compile -B > /tmp/mvn_compile.log 2>&1; then
    COMPILE_SUCCESS="true"
    echo "Maven compile succeeded"
else
    echo "Maven compile failed"
fi

# Run tests if compile succeeded
if [ "$COMPILE_SUCCESS" = "true" ]; then
    if sudo -u ga mvn test -B > /tmp/mvn_test.log 2>&1; then
        # Check surefire reports
        REPORT_FILE="$PROJECT_DIR/target/surefire-reports/TEST-com.acme.hr.model.EmployeeBuilderTest.xml"
        if [ -f "$REPORT_FILE" ]; then
            TEST_SUCCESS="true"
            # Extract stats
            TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' "$REPORT_FILE" | head -1 || echo "0")
            TESTS_FAILURES=$(grep -oP 'failures="\K[0-9]+' "$REPORT_FILE" | head -1 || echo "0")
            TESTS_ERRORS=$(grep -oP 'errors="\K[0-9]+' "$REPORT_FILE" | head -1 || echo "0")
            echo "Tests run: $TESTS_RUN, Failures: $TESTS_FAILURES, Errors: $TESTS_ERRORS"
        else
            echo "No surefire report found"
        fi
    else
        echo "Maven test failed"
    fi
fi

# 3. Capture content for python verifier
# We need to escape newlines and quotes for JSON
escape_json() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))"
}

SOURCE_CONTENT=""
if [ "$SOURCE_EXISTS" = "true" ]; then
    SOURCE_CONTENT=$(cat "$SOURCE_FILE" | escape_json)
else
    SOURCE_CONTENT='""'
fi

TEST_CONTENT=""
if [ "$TEST_EXISTS" = "true" ]; then
    TEST_CONTENT=$(cat "$TEST_FILE" | escape_json)
else
    TEST_CONTENT='""'
fi

# 4. Construct Result JSON
# Using python to create JSON is safer than bash string concatenation
python3 << EOF > /tmp/task_result.json
import json

result = {
    "source_exists": $SOURCE_EXISTS,
    "source_modified": $SOURCE_MODIFIED,
    "test_exists": $TEST_EXISTS,
    "test_created": $TEST_CREATED,
    "compile_success": $COMPILE_SUCCESS,
    "test_success": $TEST_SUCCESS,
    "tests_run": int("$TESTS_RUN"),
    "tests_failures": int("$TESTS_FAILURES"),
    "tests_errors": int("$TESTS_ERRORS"),
    "source_content_json": $SOURCE_CONTENT,
    "test_content_json": $TEST_CONTENT
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json