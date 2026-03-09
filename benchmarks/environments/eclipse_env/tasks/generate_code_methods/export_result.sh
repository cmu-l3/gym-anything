#!/bin/bash
echo "=== Exporting generate_code_methods results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/eclipse-workspace/EmployeeModel"
EMPLOYEE_FILE="$PROJECT_DIR/src/main/java/com/example/model/Employee.java"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Modification (Anti-gaming)
FILE_MODIFIED="false"
if [ -f "$EMPLOYEE_FILE" ]; then
    CURRENT_HASH=$(md5sum "$EMPLOYEE_FILE" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_employee_hash.txt 2>/dev/null || echo "")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        # Also check timestamp
        FILE_MTIME=$(stat -c %Y "$EMPLOYEE_FILE")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILE_MODIFIED="true"
        fi
    fi
fi

# 3. Attempt Compilation (Check syntax)
COMPILE_SUCCESS="false"
cd "$PROJECT_DIR"
if su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q -DskipTests"; then
    COMPILE_SUCCESS="true"
fi

# 4. Run Tests (Verify behavior)
TESTS_PASSED=0
TESTS_RUN=0
TEST_SUCCESS="false"

# Run maven test and capture output
TEST_OUTPUT_FILE="/tmp/mvn_test_output.txt"
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q" > "$TEST_OUTPUT_FILE" 2>&1 || true

# Parse JUnit output
if [ -f "$PROJECT_DIR/target/surefire-reports/TEST-com.example.model.EmployeeTest.xml" ]; then
    XML_FILE="$PROJECT_DIR/target/surefire-reports/TEST-com.example.model.EmployeeTest.xml"
    TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' "$XML_FILE" | head -1 || echo "0")
    FAILURES=$(grep -oP 'failures="\K[0-9]+' "$XML_FILE" | head -1 || echo "0")
    ERRORS=$(grep -oP 'errors="\K[0-9]+' "$XML_FILE" | head -1 || echo "0")
    
    # Calculate passed tests
    TESTS_PASSED=$((TESTS_RUN - FAILURES - ERRORS))
    
    if [ "$TESTS_RUN" -ge 5 ] && [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
        TEST_SUCCESS="true"
    fi
fi

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "compile_success": $COMPILE_SUCCESS,
    "test_success": $TEST_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="