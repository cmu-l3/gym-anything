#!/bin/bash
set -euo pipefail

echo "=== Exporting hetero_test_robust result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_PATH="/home/ga/Documents/gretl_output/hetero_test_results.txt"
TASK_START_FILE="/tmp/task_start_time.txt"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file status
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"
CONTENT_PREVIEW=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Read first 50 lines for preview/debug logging (sanitized)
    CONTENT_PREVIEW=$(head -n 50 "$OUTPUT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')

    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Gretl is still running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# Generate Ground Truth using gretlcli for verification reference
# This ensures we verify against the exact computation of the installed version
echo "Generating ground truth..."
GT_SCRIPT=$(mktemp)
cat > "$GT_SCRIPT" << EOF
open /home/ga/Documents/gretl_data/food.gdt --quiet
ols food_exp const income --quiet
modtest --white --quiet
modtest --breusch-pagan --quiet
ols food_exp const income --robust --quiet
EOF

GT_OUTPUT="/tmp/ground_truth_output.txt"
gretlcli -b "$GT_SCRIPT" > "$GT_OUTPUT" 2>&1 || echo "Ground truth generation failed"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "$GT_OUTPUT"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup
rm -f "$TEMP_JSON" "$GT_SCRIPT"

echo "Result exported to /tmp/task_result.json"