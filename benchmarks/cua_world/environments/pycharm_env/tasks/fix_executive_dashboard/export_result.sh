#!/bin/bash
echo "=== Exporting Executive Dashboard Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_executive_dashboard"
PROJECT_DIR="/home/ga/PycharmProjects/executive_dashboard"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take Screenshot
take_screenshot /tmp/${TASK_NAME}_final.png

# 2. Run Tests
echo "Running tests..."
# We run tests as 'ga' user
TEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
TEST_EXIT_CODE=$?

# Parse Test Results
TEST_DATE_PASS=$(echo "$TEST_OUTPUT" | grep -c "test_data_loader_sorts_chronologically PASSED" || true)
TEST_BARS_PASS=$(echo "$TEST_OUTPUT" | grep -c "test_stacked_bars_are_stacked PASSED" || true)
TEST_SCALE_PASS=$(echo "$TEST_OUTPUT" | grep -c "test_y_axis_scaling_matches_label PASSED" || true)
TEST_PIE_PASS=$(echo "$TEST_OUTPUT" | grep -c "test_pie_chart_legend_match PASSED" || true)

# 3. Check for Output File Generation
OUTPUT_PATH="$PROJECT_DIR/output/dashboard.png"
OUTPUT_EXISTS="false"
OUTPUT_NEW="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Check modification time
    MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        OUTPUT_NEW="true"
    fi
fi

# 4. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "timestamp": "$(date -Iseconds)",
    "test_exit_code": $TEST_EXIT_CODE,
    "pass_date_sort": $TEST_DATE_PASS,
    "pass_stacked_bars": $TEST_BARS_PASS,
    "pass_axis_scaling": $TEST_SCALE_PASS,
    "pass_pie_legend": $TEST_PIE_PASS,
    "output_exists": $OUTPUT_EXISTS,
    "output_generated_during_task": $OUTPUT_NEW
}
EOF

# Safe copy/permissions
chmod 666 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"