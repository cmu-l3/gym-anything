#!/bin/bash
echo "=== Exporting optimize_transcript_service result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="optimize_transcript_service"
PROJECT_DIR="/home/ga/PycharmProjects/transcript_engine"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Run tests and capture output
echo "Running tests to verify optimization..."
PYTEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/test_transcript.py -v -s" 2>&1)
PYTEST_EXIT_CODE=$?

# Extract query count from pytest output
# Expecting output line: "Total SQL Queries Executed: X"
QUERY_COUNT=$(echo "$PYTEST_OUTPUT" | grep "Total SQL Queries Executed:" | awk '{print $NF}' | tr -d '\r')
if [ -z "$QUERY_COUNT" ]; then
    QUERY_COUNT=999 # Fallback if not found
fi

# Check test status
CORRECTNESS_PASSED="false"
PERFORMANCE_PASSED="false"

if echo "$PYTEST_OUTPUT" | grep -q "test_transcript_correctness PASSED"; then
    CORRECTNESS_PASSED="true"
fi

if echo "$PYTEST_OUTPUT" | grep -q "test_query_count PASSED"; then
    PERFORMANCE_PASSED="true"
fi

# Analyze the code for hardcoding or cheating
# Check if joinedload or selectinload is used (Good signs)
CODE_CONTENT=$(cat "$PROJECT_DIR/services/transcript.py")
USED_EAGER_LOADING="false"
if echo "$CODE_CONTENT" | grep -qE "joinedload|selectinload|options\(|subqueryload"; then
    USED_EAGER_LOADING="true"
fi

# Check for explicit JOINs (Also a valid optimization)
USED_JOINS="false"
if echo "$CODE_CONTENT" | grep -qE "\.join\(|\.outerjoin\("; then
    USED_JOINS="true"
fi

# Serialize Code Content
CODE_ESCAPED=$(echo "$CODE_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
PYTEST_OUTPUT_ESCAPED=$(echo "$PYTEST_OUTPUT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# Create JSON result
cat > /tmp/result_gen.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "correctness_passed": $CORRECTNESS_PASSED,
    "performance_passed": $PERFORMANCE_PASSED,
    "query_count": $QUERY_COUNT,
    "used_eager_loading": $USED_EAGER_LOADING,
    "used_joins": $USED_JOINS,
    "code_content": $CODE_ESCAPED,
    "pytest_output": $PYTEST_OUTPUT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
mv /tmp/result_gen.json "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "Export complete. Query count: $QUERY_COUNT"