#!/bin/bash
echo "=== Exporting record_portfolio_deposits results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
DEPOSIT_FILE="${PORTFOLIO_DIR}/depositsummary.csv"

# Check if output file exists and get stats
if [ -f "$DEPOSIT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DEPOSIT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$DEPOSIT_FILE" 2>/dev/null || echo "0")
    
    # Read file content safely (escape double quotes for JSON embedding)
    # We use python to escape it properly to avoid bash string hell
    FILE_CONTENT=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" < "$DEPOSIT_FILE")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_CONTENT="null"
fi

# Check if JStock is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "app_running": $APP_RUNNING,
    "file_content_json": $FILE_CONTENT,
    "initial_lines": $(cat /tmp/initial_deposit_lines.txt 2>/dev/null || echo "1")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="