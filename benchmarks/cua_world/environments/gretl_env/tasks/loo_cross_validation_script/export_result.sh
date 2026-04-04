#!/bin/bash
echo "=== Exporting LOO Cross-Validation Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_FILE="/home/ga/Documents/gretl_output/cv_results.txt"
PREDICTIONS_FILE="/home/ga/Documents/gretl_output/cv_predictions.csv"

# Check Results File
RESULTS_EXISTS="false"
RESULTS_MTIME="0"
RESULTS_CONTENT=""
if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    # Read first few lines safely
    RESULTS_CONTENT=$(head -n 10 "$RESULTS_FILE" | base64 -w 0)
fi

# Check Predictions File
PREDS_EXISTS="false"
PREDS_MTIME="0"
PREDS_CONTENT=""
if [ -f "$PREDICTIONS_FILE" ]; then
    PREDS_EXISTS="true"
    PREDS_MTIME=$(stat -c %Y "$PREDICTIONS_FILE" 2>/dev/null || echo "0")
    # Read content safely (base64 encoded to handle CSV structure in JSON)
    PREDS_CONTENT=$(cat "$PREDICTIONS_FILE" | base64 -w 0)
fi

# Check timestamps relative to task start
RESULTS_CREATED_DURING_TASK="false"
if [ "$RESULTS_MTIME" -gt "$TASK_START" ]; then
    RESULTS_CREATED_DURING_TASK="true"
fi

PREDS_CREATED_DURING_TASK="false"
if [ "$PREDS_MTIME" -gt "$TASK_START" ]; then
    PREDS_CREATED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "results_file_exists": $RESULTS_EXISTS,
    "results_file_created_during_task": $RESULTS_CREATED_DURING_TASK,
    "results_file_content_b64": "$RESULTS_CONTENT",
    "predictions_file_exists": $PREDS_EXISTS,
    "predictions_file_created_during_task": $PREDS_CREATED_DURING_TASK,
    "predictions_file_content_b64": "$PREDS_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="