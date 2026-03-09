#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
PORTFOLIO_SOURCE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
EXPORT_CSV="/tmp/final_portfolio.csv"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
FILE_EXISTS="false"

if [ -f "$PORTFOLIO_SOURCE" ]; then
    FILE_EXISTS="true"
    # Copy file to temp for verifier to read
    cp "$PORTFOLIO_SOURCE" "$EXPORT_CSV"
    chmod 644 "$EXPORT_CSV"

    # Check modification time
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_SOURCE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if JStock is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "csv_path": "$EXPORT_CSV",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"