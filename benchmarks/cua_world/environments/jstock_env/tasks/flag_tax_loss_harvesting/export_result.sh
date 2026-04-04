#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_CSV="$JSTOCK_DATA_DIR/portfolios/Semiconductors/buyportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if JStock is running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# Check if portfolio file exists
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$PORTFOLIO_CSV" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$PORTFOLIO_CSV")
    FILE_MTIME=$(stat -c%Y "$PORTFOLIO_CSV")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy the portfolio CSV to temp for verifier to access via copy_from_env
    # We rename it to avoid path complexity in verifier
    cp "$PORTFOLIO_CSV" /tmp/result_portfolio.csv
    chmod 666 /tmp/result_portfolio.csv
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json