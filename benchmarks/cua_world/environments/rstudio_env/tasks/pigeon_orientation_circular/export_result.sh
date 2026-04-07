#!/bin/bash
echo "=== Exporting Pigeon Orientation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check Summary CSV ---
SUMMARY_CSV="$OUTPUT_DIR/pigeon_summary.csv"
SUMMARY_EXISTS="false"
SUMMARY_NEW="false"
SUMMARY_COLS_OK="false"

if [ -f "$SUMMARY_CSV" ]; then
    SUMMARY_EXISTS="true"
    # Check timestamp
    F_TIME=$(stat -c %Y "$SUMMARY_CSV")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        SUMMARY_NEW="true"
    fi
    # Check basic structure (header)
    HEADER=$(head -1 "$SUMMARY_CSV" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"group"* && "$HEADER" == *"mean"* && "$HEADER" == *"rho"* ]]; then
        SUMMARY_COLS_OK="true"
    fi
    # Lenient check for column names if exact names aren't used
    if [[ "$HEADER" == *"group"* && "$HEADER" == *"direction"* ]]; then
        SUMMARY_COLS_OK="true"
    fi
fi

# --- Check Test CSV ---
TEST_CSV="$OUTPUT_DIR/pigeon_test.csv"
TEST_EXISTS="false"
TEST_NEW="false"
TEST_WATSON="false"

if [ -f "$TEST_CSV" ]; then
    TEST_EXISTS="true"
    F_TIME=$(stat -c %Y "$TEST_CSV")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        TEST_NEW="true"
    fi
    CONTENT=$(cat "$TEST_CSV" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONTENT" == *"watson"* ]]; then
        TEST_WATSON="true"
    fi
fi

# --- Check Plot PNG ---
PLOT_PNG="$OUTPUT_DIR/pigeon_rose_plot.png"
PLOT_EXISTS="false"
PLOT_NEW="false"
PLOT_SIZE=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS="true"
    F_TIME=$(stat -c %Y "$PLOT_PNG")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        PLOT_NEW="true"
    fi
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG")
fi

# --- Check Script ---
SCRIPT_PATH="/home/ga/RProjects/pigeon_analysis.R"
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    F_TIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_new": $SUMMARY_NEW,
    "summary_cols_ok": $SUMMARY_COLS_OK,
    "test_exists": $TEST_EXISTS,
    "test_new": $TEST_NEW,
    "test_watson": $TEST_WATSON,
    "plot_exists": $PLOT_EXISTS,
    "plot_new": $PLOT_NEW,
    "plot_size": $PLOT_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="