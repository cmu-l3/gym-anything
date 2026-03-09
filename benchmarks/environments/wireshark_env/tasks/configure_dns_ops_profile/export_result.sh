#!/bin/bash
echo "=== Exporting Configure DNS Ops Profile result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROFILE_DIR="/home/ga/.config/wireshark/profiles/DNS_Ops"
PREFS_FILE="$PROFILE_DIR/preferences"
RULES_FILE="$PROFILE_DIR/coloring_rules"
SCREENSHOT_PATH="/home/ga/Documents/dns_ops_view.png"

# Check Profile Existence
PROFILE_EXISTS="false"
PROFILE_CREATED_DURING_TASK="false"

if [ -d "$PROFILE_DIR" ]; then
    PROFILE_EXISTS="true"
    # Check directory timestamp
    DIR_MTIME=$(stat -c %Y "$PROFILE_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        PROFILE_CREATED_DURING_TASK="true"
    fi
fi

# Read Preferences Content (Columns)
PREFS_CONTENT=""
if [ -f "$PREFS_FILE" ]; then
    # Extract the column format line specifically
    PREFS_CONTENT=$(grep "gui.column.format" "$PREFS_FILE" 2>/dev/null || echo "")
fi

# Read Coloring Rules Content
RULES_CONTENT=""
if [ -f "$RULES_FILE" ]; then
    RULES_CONTENT=$(cat "$RULES_FILE")
fi

# Check Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Take final system screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

data = {
    'profile_exists': sys.argv[1] == 'true',
    'profile_created_during_task': sys.argv[2] == 'true',
    'prefs_content': sys.argv[3],
    'rules_content': sys.argv[4],
    'screenshot_exists': sys.argv[5] == 'true',
    'task_start': int(sys.argv[6]),
    'task_end': int(sys.argv[7]),
    'timestamp': sys.argv[8]
}

with open(sys.argv[9], 'w') as f:
    json.dump(data, f, indent=4)
" "$PROFILE_EXISTS" "$PROFILE_CREATED_DURING_TASK" "$PREFS_CONTENT" "$RULES_CONTENT" "$SCREENSHOT_EXISTS" "$TASK_START" "$TASK_END" "$(date -Iseconds)" "$TEMP_JSON"

# Move result to safe location
safe_json_write "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="