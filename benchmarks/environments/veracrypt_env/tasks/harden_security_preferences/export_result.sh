#!/bin/bash
echo "=== Exporting harden_security_preferences results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"

# 1. Locate Configuration File
CONFIG_PATH=""
for path in "/home/ga/.config/VeraCrypt/Configuration.xml" \
            "/home/ga/.VeraCrypt/Configuration.xml" \
            "/root/.config/VeraCrypt/Configuration.xml" \
            "/root/.VeraCrypt/Configuration.xml"; do
    if [ -f "$path" ]; then
        CONFIG_PATH="$path"
        echo "Found config at: $CONFIG_PATH"
        break
    fi
done

# 2. Parse Configuration XML using Python (more robust than grep)
# We extract the specific keys we care about
CONFIG_VALUES="{}"
CONFIG_MTIME="0"

if [ -n "$CONFIG_PATH" ]; then
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    
    # Python script to parse XML and output JSON
    CONFIG_VALUES=$(python3 -c "
import xml.etree.ElementTree as ET
import json
import sys

try:
    tree = ET.parse('$CONFIG_PATH')
    root = tree.getroot()
    
    # VeraCrypt config is typically flat: <config key='X'>Y</config>
    settings = {}
    for elem in root.iter('config'):
        key = elem.get('key')
        if key:
            settings[key] = elem.text or ''
            
    print(json.dumps(settings))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
fi

# 3. Check Compliance Report
REPORT_PATH="/home/ga/Documents/security_compliance_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read first 1000 chars for verification, verify readable
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | tr -cd '[:print:]\n' | sed 's/"/\\"/g')
fi

# 4. Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_path": "$CONFIG_PATH",
    "config_found": $([ -n "$CONFIG_PATH" ] && echo "true" || echo "false"),
    "config_mtime": $CONFIG_MTIME,
    "config_values": $CONFIG_VALUES,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content_preview": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location with permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="