#!/bin/bash
echo "=== Exporting configure_custom_broker result ==="

# Define paths
JSTOCK_DIR="/home/ga/.jstock/1.0.7"
PORTFOLIO_CSV="${JSTOCK_DIR}/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
CONFIG_DIR="${JSTOCK_DIR}"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data

# A. Transaction Data
# Read the portfolio file. We'll embed the content in the JSON.
if [ -f "$PORTFOLIO_CSV" ]; then
    PORTFOLIO_CONTENT=$(cat "$PORTFOLIO_CSV" | base64 -w 0)
    PORTFOLIO_EXISTS="true"
else
    PORTFOLIO_CONTENT=""
    PORTFOLIO_EXISTS="false"
fi

# B. Configuration Data (The tricky part - searching for NeoTrade)
# Search for 'NeoTrade' in all xml files in the config dir
CONFIG_MATCH=$(grep -l "NeoTrade" "${CONFIG_DIR}"/*.xml 2>/dev/null | head -n 1)
if [ -n "$CONFIG_MATCH" ]; then
    CONFIG_FOUND="true"
    CONFIG_FILENAME=$(basename "$CONFIG_MATCH")
    # Read the file content (base64 to handle xml safely in json)
    CONFIG_CONTENT=$(cat "$CONFIG_MATCH" | base64 -w 0)
    
    # Get file timestamp for anti-gaming
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_MATCH")
else
    CONFIG_FOUND="false"
    CONFIG_FILENAME=""
    CONFIG_CONTENT=""
    CONFIG_MTIME="0"
fi

# Get CSV timestamp
if [ -f "$PORTFOLIO_CSV" ]; then
    CSV_MTIME=$(stat -c %Y "$PORTFOLIO_CSV")
else
    CSV_MTIME="0"
fi

# Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# App Running Status
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 3. Create JSON
# We use Python to write the JSON to ensure proper escaping/formatting
python3 -c "
import json
import os

data = {
    'portfolio_exists': $PORTFOLIO_EXISTS,
    'portfolio_content_b64': '$PORTFOLIO_CONTENT',
    'portfolio_mtime': $CSV_MTIME,
    'config_found': $CONFIG_FOUND,
    'config_filename': '$CONFIG_FILENAME',
    'config_content_b64': '$CONFIG_CONTENT',
    'config_mtime': $CONFIG_MTIME,
    'task_start': $TASK_START,
    'app_running': $APP_RUNNING
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# 4. Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"