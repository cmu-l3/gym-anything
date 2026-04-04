#!/bin/bash
echo "=== Exporting fix_thread_deadlock result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-core"
ACCOUNT_FILE="$PROJECT_DIR/src/main/java/com/bank/core/Account.java"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Tests (with timeout to prevent hanging if deadlock persists)
# We use 'timeout' command because if deadlock exists, 'mvn test' might hang indefinitely
echo "Running verification tests..."
cd "$PROJECT_DIR"

# Clean clean to ensure we recompile
rm -rf target

TEST_OUTPUT_FILE="/tmp/maven_test_output.log"
# 20s timeout is plenty for these small tests; if it takes longer, it's likely deadlocked
if timeout 30s mvn test > "$TEST_OUTPUT_FILE" 2>&1; then
    MAVEN_EXIT_CODE=0
    TIMEOUT_OCCURRED="false"
else
    MAVEN_EXIT_CODE=$?
    if [ $MAVEN_EXIT_CODE -eq 124 ]; then
        TIMEOUT_OCCURRED="true"
        echo "Maven tests timed out (Likely Deadlock)" >> "$TEST_OUTPUT_FILE"
    else
        TIMEOUT_OCCURRED="false"
    fi
fi

# 3. Parse Surefire Reports
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_ERRORS=0

REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
if [ -d "$REPORT_DIR" ]; then
    for report in "$REPORT_DIR"/*.xml; do
        if [ -f "$report" ]; then
            TR=$(grep -oP 'tests="\K[0-9]+' "$report" 2>/dev/null | head -1)
            TF=$(grep -oP 'failures="\K[0-9]+' "$report" 2>/dev/null | head -1)
            TE=$(grep -oP 'errors="\K[0-9]+' "$report" 2>/dev/null | head -1)
            
            TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
            TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
            TESTS_ERRORS=$((TESTS_ERRORS + ${TE:-0}))
        fi
    done
    TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_ERRORS))
fi

# 4. Read Account.java content for analysis
ACCOUNT_CONTENT=""
if [ -f "$ACCOUNT_FILE" ]; then
    ACCOUNT_CONTENT=$(cat "$ACCOUNT_FILE")
fi

# 5. Check if file was modified
FILE_MODIFIED="false"
if [ -f /tmp/initial_account_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$ACCOUNT_FILE" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_account_hash.txt | awk '{print $1}')
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 6. Escape content for JSON
ACCOUNT_ESCAPED=$(echo "$ACCOUNT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_OUTPUT_ESCAPED=$(cat "$TEST_OUTPUT_FILE" | tail -n 50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 7. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "maven_exit_code": $MAVEN_EXIT_CODE,
    "timeout_occurred": $TIMEOUT_OCCURRED,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_errors": $TESTS_ERRORS,
    "file_modified": $FILE_MODIFIED,
    "account_content": $ACCOUNT_ESCAPED,
    "test_output_tail": $TEST_OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="