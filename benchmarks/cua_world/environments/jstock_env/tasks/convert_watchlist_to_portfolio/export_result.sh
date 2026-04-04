#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
TARGET_PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/Starter_Positions"
TARGET_CSV="${TARGET_PORTFOLIO_DIR}/buyportfolio.csv"
RESULT_JSON="/tmp/task_result.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if application is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and stats
PORTFOLIO_EXISTS="false"
CSV_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE="0"

if [ -d "$TARGET_PORTFOLIO_DIR" ]; then
    PORTFOLIO_EXISTS="true"
fi

if [ -f "$TARGET_CSV" ]; then
    CSV_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_CSV" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_CSV" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy the CSV to /tmp/ for easier retrieval by verifier
    # (Avoiding permissions issues by copying to world-writable /tmp)
    cp "$TARGET_CSV" /tmp/exported_portfolio.csv
    chmod 666 /tmp/exported_portfolio.csv
fi

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "portfolio_dir_exists": $PORTFOLIO_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_path": "/tmp/exported_portfolio.csv",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"