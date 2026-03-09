#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Locate the portfolio file
# Note: "UnitedState" is the directory name used by JStock, not "UnitedStates"
PORTFOLIO_PATH="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 3. Check file status
PORTFOLIO_EXISTS="false"
PORTFOLIO_MODIFIED="false"
PORTFOLIO_CONTENT=""
PORTFOLIO_SIZE="0"

if [ -f "$PORTFOLIO_PATH" ]; then
    PORTFOLIO_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PORTFOLIO_MODIFIED="true"
    fi
    
    PORTFOLIO_SIZE=$(stat -c %s "$PORTFOLIO_PATH" 2>/dev/null || echo "0")
    
    # Read content safely (escape quotes for JSON)
    # python script is safer for escaping than sed for complex CSVs
    PORTFOLIO_CONTENT=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" < "$PORTFOLIO_PATH")
else
    PORTFOLIO_CONTENT="\"\""
fi

# 4. Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock" > /dev/null && echo "true" || echo "false")

# 5. Capture final screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || \
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png" 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 6. Create JSON result
# We use a python script to generate the JSON to avoid quoting hell with CSV content
python3 << PYEOF > /tmp/task_result.json
import json
import os

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "portfolio_exists": $PORTFOLIO_EXISTS,
    "portfolio_modified": $PORTFOLIO_MODIFIED,
    "portfolio_size": $PORTFOLIO_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "portfolio_content_str": $PORTFOLIO_CONTENT
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# 7. Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="