#!/bin/bash
echo "=== Exporting record_inter_portfolio_transfer results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths to the specific files we need to check
SAFE_WITHDRAWAL_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Safe Harbor/withdrawalsummary.csv"
GROWTH_DEPOSIT_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Growth Fund/depositsummary.csv"

# Check if Safe Harbor withdrawal file exists and was modified
SAFE_EXISTS="false"
SAFE_MODIFIED="false"
SAFE_CONTENT=""
if [ -f "$SAFE_WITHDRAWAL_FILE" ]; then
    SAFE_EXISTS="true"
    SAFE_MTIME=$(stat -c %Y "$SAFE_WITHDRAWAL_FILE" 2>/dev/null || echo "0")
    if [ "$SAFE_MTIME" -gt "$TASK_START" ]; then
        SAFE_MODIFIED="true"
    fi
    # Read content, encoding safe for JSON (base64 is safest but we'll try simple cat for text)
    # We only care about the last few lines usually
    SAFE_CONTENT=$(cat "$SAFE_WITHDRAWAL_FILE")
fi

# Check if Growth Fund deposit file exists and was modified
GROWTH_EXISTS="false"
GROWTH_MODIFIED="false"
GROWTH_CONTENT=""
if [ -f "$GROWTH_DEPOSIT_FILE" ]; then
    GROWTH_EXISTS="true"
    GROWTH_MTIME=$(stat -c %Y "$GROWTH_DEPOSIT_FILE" 2>/dev/null || echo "0")
    if [ "$GROWTH_MTIME" -gt "$TASK_START" ]; then
        GROWTH_MODIFIED="true"
    fi
    GROWTH_CONTENT=$(cat "$GROWTH_DEPOSIT_FILE")
fi

# App state
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# Construct JSON result using Python to handle string escaping safely
python3 -c "
import json
import os
import sys

safe_content = '''$SAFE_CONTENT'''
growth_content = '''$GROWTH_CONTENT'''

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING,
    'safe_harbor': {
        'exists': $SAFE_EXISTS,
        'modified': $SAFE_MODIFIED,
        'content': safe_content
    },
    'growth_fund': {
        'exists': $GROWTH_EXISTS,
        'modified': $GROWTH_MODIFIED,
        'content': growth_content
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="