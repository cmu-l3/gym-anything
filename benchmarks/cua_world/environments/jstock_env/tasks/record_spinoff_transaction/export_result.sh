#!/bin/bash
echo "=== Exporting record_spinoff_transaction results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
RESULT_JSON="/tmp/task_result.json"

# Check if portfolio file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PORTFOLIO_FILE")
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if JStock is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
# We don't parse the CSV here entirely, we leave the complex logic to the Python verifier.
# We just export metadata.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "portfolio_path": "$PORTFOLIO_FILE"
}
EOF

# Ensure permissions for the verifier to read
chmod 666 "$RESULT_JSON"
chmod 666 "/tmp/task_final.png" 2>/dev/null || true
# We also need to ensure the portfolio file is readable by the verifier (via copy_from_env)
chmod 644 "$PORTFOLIO_FILE" 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_JSON"