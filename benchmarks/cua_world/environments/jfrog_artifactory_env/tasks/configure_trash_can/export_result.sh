#!/bin/bash
echo "=== Exporting Configure Trash Can results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Current System Configuration
# This is the source of truth for verification
echo "Fetching final system configuration..."
CONFIG_XML=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/system/configuration")

# 3. Parse Final State
# Extract specific trash can settings
FINAL_STATE_JSON=$(python3 -c "
import sys, xml.etree.ElementTree as ET, json
try:
    tree = ET.fromstring(sys.stdin.read())
    trash_config = tree.find('.//trashCanConfig')
    if trash_config is not None:
        enabled = trash_config.findtext('enabled')
        days = trash_config.findtext('retentionPeriodDays')
        print(json.dumps({'enabled': enabled == 'true', 'days': int(days) if days else 0}))
    else:
        print(json.dumps({'enabled': False, 'days': 0, 'error': 'No trashCanConfig found'}))
except Exception as e:
    print(json.dumps({'enabled': False, 'days': 0, 'error': str(e)}))
" <<< "$CONFIG_XML")

# 4. Read Initial State
if [ -f /tmp/initial_config.json ]; then
    INITIAL_STATE_JSON=$(cat /tmp/initial_config.json)
else
    INITIAL_STATE_JSON="{}"
fi

# 5. Construct Result JSON
# Combine start time, initial state, and final state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON using a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": $INITIAL_STATE_JSON,
    "final_state": $FINAL_STATE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to safe location for verification
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="