#!/bin/bash
echo "=== Exporting optimize_inventory_queries Result ==="

PROJECT_DIR="/home/ga/PycharmProjects/inventory_system"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Tests and Capture Output
# We run functional and performance tests separately to parse results better
cd "$PROJECT_DIR"

# Run Functional Tests
FUNCTIONAL_OUT=$(su - ga -c "PYTHONPATH=$PROJECT_DIR python3 -m pytest tests/test_functional.py -v" 2>&1)
FUNCTIONAL_EXIT=$?

# Run Performance Tests (capture stdout to extract query count)
PERFORMANCE_OUT=$(su - ga -c "PYTHONPATH=$PROJECT_DIR python3 -m pytest tests/test_performance.py -v -s" 2>&1)
PERFORMANCE_EXIT=$?

# Extract Query Count from output
# Expected line: "Total Queries Executed: X"
QUERY_COUNT=$(echo "$PERFORMANCE_OUT" | grep "Total Queries Executed:" | awk '{print $NF}' | tr -d '[:space:]')
# Default to high number if not found
if [ -z "$QUERY_COUNT" ]; then
    QUERY_COUNT=9999
fi

# 3. Check file modification
REPORT_FILE="$PROJECT_DIR/inventory/report.py"
FILE_MODIFIED="false"
if [ -f "$REPORT_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Construct JSON Result
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "functional_tests_passed": $([ $FUNCTIONAL_EXIT -eq 0 ] && echo "true" || echo "false"),
    "performance_tests_passed": $([ $PERFORMANCE_EXIT -eq 0 ] && echo "true" || echo "false"),
    "query_count": $QUERY_COUNT,
    "file_modified": $FILE_MODIFIED,
    "functional_output": $(echo "$FUNCTIONAL_OUT" | jq -R -s '.'),
    "performance_output": $(echo "$PERFORMANCE_OUT" | jq -R -s '.')
}
EOF

# Set permissions so verifier can read it
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
echo "Query count: $QUERY_COUNT"
echo "=== Export complete ==="