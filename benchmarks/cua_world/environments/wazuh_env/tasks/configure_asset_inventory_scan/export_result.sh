#!/bin/bash
echo "=== Exporting configure_asset_inventory_scan results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if socat is installed in the container
SOCAT_INSTALLED="false"
if wazuh_exec dpkg -l socat | grep -q "^ii.*socat"; then
    SOCAT_INSTALLED="true"
    echo "Verified: socat is installed."
else
    echo "Verified: socat is NOT installed."
fi

# 3. Extract syscollector interval from ossec.conf
# We grep the file content.
CONFIG_CONTENT=$(wazuh_exec cat /var/ossec/etc/ossec.conf)
# We look for the syscollector block and the interval within it
# Since parsing XML with regex is fragile, we'll dump the whole file for the python verifier
# but also do a quick check here.
# Simple extraction:
SYSCOLLECTOR_INTERVAL=$(echo "$CONFIG_CONTENT" | grep -A 10 '<wodle name="syscollector">' | grep "<interval>" | sed -e 's/^[ \t]*//' -e 's/<[^>]*>//g')
echo "Detected syscollector interval: $SYSCOLLECTOR_INTERVAL"

# 4. Check output JSON file
OUTPUT_FILE="/home/ga/socat_inventory.json"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check timestamps
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check Manager Uptime (to verify restart)
# We check the PID start time of ossec-monitord or wazuh-modulesd
MANAGER_PID_CTIME=$(wazuh_exec stat -c %Z /proc/1/cmdline 2>/dev/null || echo "0") 
# Actually, better to check the wazuh-modulesd process inside the container
MODULESD_PID=$(wazuh_exec pgrep wazuh-modulesd | head -n 1)
if [ -n "$MODULESD_PID" ]; then
    # Get elapsed time in seconds
    MODULESD_ELAPSED=$(wazuh_exec ps -p "$MODULESD_PID" -o etimes= | tr -d ' ')
    echo "Wazuh modulesd uptime: $MODULESD_ELAPSED seconds"
else
    MODULESD_ELAPSED="99999"
    echo "Wazuh modulesd not running"
fi

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "socat_installed": $SOCAT_INSTALLED,
    "config_interval_raw": "$SYSCOLLECTOR_INTERVAL",
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "manager_uptime_seconds": $MODULESD_ELAPSED,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "screenshot_path": "/tmp/task_final.png",
    "full_config_snapshot": "See python verifier for content analysis"
}
EOF

# Append the actual output content as a JSON string (escaping quotes)
# Using python to safely embed the content and config
python3 -c "
import json
import sys

# Load base result
with open('$TEMP_JSON', 'r') as f:
    result = json.load(f)

# Add output content
try:
    with open('$OUTPUT_FILE', 'r') as f:
        result['output_content'] = f.read()
except FileNotFoundError:
    result['output_content'] = ''

# Add config content
result['ossec_config'] = '''$CONFIG_CONTENT'''

# Save back
with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."