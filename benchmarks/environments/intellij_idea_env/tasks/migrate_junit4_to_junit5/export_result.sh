#!/bin/bash
echo "=== Exporting migrate_junit4_to_junit5 result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-service"
TEST_DIR="$PROJECT_DIR/src/test/java/com/example/banking"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests using Maven
echo "Running tests..."
cd "$PROJECT_DIR"
# Clean output log
rm -f /tmp/mvn_output.log
# Run test - allow failure (set +e)
set +e
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test > /tmp/mvn_output.log 2>&1
MVN_EXIT_CODE=$?
set -e

# 2. Collect Data
# Read POM
POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null || echo "")

# Read Test Files
ACCOUNT_TEST=$(cat "$TEST_DIR/AccountTest.java" 2>/dev/null || echo "")
TRANS_TEST=$(cat "$TEST_DIR/TransactionServiceTest.java" 2>/dev/null || echo "")

# Parse Maven Output for test counts
TESTS_RUN=$(grep -o "Tests run: [0-9]*" /tmp/mvn_output.log | tail -1 | awk '{print $3}' || echo "0")
FAILURES=$(grep -o "Failures: [0-9]*" /tmp/mvn_output.log | tail -1 | awk '{print $2}' || echo "0")
ERRORS=$(grep -o "Errors: [0-9]*" /tmp/mvn_output.log | tail -1 | awk '{print $2}' || echo "0")

# Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
POM_MTIME=$(stat -c %Y "$PROJECT_DIR/pom.xml" 2>/dev/null || echo "0")
TEST_MTIME=$(stat -c %Y "$TEST_DIR/AccountTest.java" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$POM_MTIME" -gt "$TASK_START" ] || [ "$TEST_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Escape for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
ACCT_TEST_ESCAPED=$(echo "$ACCOUNT_TEST" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
TRANS_TEST_ESCAPED=$(echo "$TRANS_TEST" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
LOG_ESCAPED=$(tail -n 20 /tmp/mvn_output.log | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "mvn_exit_code": $MVN_EXIT_CODE,
  "tests_run": ${TESTS_RUN//,/},
  "failures": ${FAILURES//,/},
  "errors": ${ERRORS//,/},
  "pom_content": $POM_ESCAPED,
  "account_test_content": $ACCT_TEST_ESCAPED,
  "transaction_test_content": $TRANS_TEST_ESCAPED,
  "mvn_log_tail": $LOG_ESCAPED,
  "files_modified_during_task": $FILE_MODIFIED,
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to destination with correct permissions
mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON" | grep "tests_run" # Quick check