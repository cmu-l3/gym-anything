#!/bin/bash
set -e
echo "=== Exporting configure_classroom results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Locate the actual active config file
# We look for the most recently modified one
CONFIG_FILES=$(find /home/ga/.config -name "gcompris-qt.conf" -type f 2>/dev/null)
BEST_CONFIG=""
BEST_MTIME=0

for f in $CONFIG_FILES; do
    MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$BEST_MTIME" ]; then
        BEST_MTIME=$MTIME
        BEST_CONFIG=$f
    fi
done

CONFIG_CONTENT=""
CONFIG_MODIFIED_DURING_TASK="false"
CONFIG_PATH="none"

if [ -n "$BEST_CONFIG" ]; then
    CONFIG_PATH="$BEST_CONFIG"
    CONFIG_CONTENT=$(cat "$BEST_CONFIG")
    
    # Check if modified during task
    if [ "$BEST_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_DURING_TASK="true"
    fi
fi

# Get initial config for comparison
INITIAL_CONTENT=$(cat /tmp/initial_gcompris_config.txt 2>/dev/null || echo "")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# We use python to safely escape the config content into JSON
python3 -c "
import json
import os

try:
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'app_running': $APP_RUNNING,
        'config_found': bool('$BEST_CONFIG'),
        'config_path': '$CONFIG_PATH',
        'config_modified_during_task': $CONFIG_MODIFIED_DURING_TASK,
        'config_content': '''$CONFIG_CONTENT''',
        'initial_content': '''$INITIAL_CONTENT''',
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"