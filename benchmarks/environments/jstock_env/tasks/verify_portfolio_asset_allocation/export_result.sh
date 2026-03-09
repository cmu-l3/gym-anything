#!/bin/bash
echo "=== Exporting verify_portfolio_asset_allocation results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOCS_DIR="/home/ga/Documents"
CHART_FILE="$DOCS_DIR/allocation_chart.png"
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 1. Check Screenshot existence and timestamp
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$CHART_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$CHART_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$CHART_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Extract Portfolio Data (CSV content)
# We read the file content to JSON for Python processing
PORTFOLIO_CONTENT=""
if [ -f "$PORTFOLIO_FILE" ]; then
    # Read file, escape quotes/backslashes for JSON safety
    # Using python to safely dump to json string
    PORTFOLIO_CONTENT=$(python3 -c "import json; print(json.dumps(open('$PORTFOLIO_FILE').read()))")
else
    PORTFOLIO_CONTENT="null"
fi

# 3. Check if App is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Take final system screenshot (for VLM debug if needed)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_size": $SCREENSHOT_SIZE,
    "screenshot_path": "$CHART_FILE",
    "app_running": $APP_RUNNING,
    "portfolio_content": $PORTFOLIO_CONTENT
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"