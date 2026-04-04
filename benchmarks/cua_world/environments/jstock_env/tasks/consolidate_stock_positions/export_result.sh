#!/bin/bash
echo "=== Exporting task results ==="

# Source task variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PORTFOLIO_PATH="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
if [ -f "$PORTFOLIO_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$PORTFOLIO_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$PORTFOLIO_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
    
    # Make a safe copy for the verifier to read
    cp "$PORTFOLIO_PATH" /tmp/buyportfolio_final.csv
    chmod 666 /tmp/buyportfolio_final.csv
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_MODIFIED="false"
fi

# 3. Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "portfolio_csv_path": "/tmp/buyportfolio_final.csv"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json