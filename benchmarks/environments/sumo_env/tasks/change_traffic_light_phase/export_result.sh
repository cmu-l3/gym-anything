#!/bin/bash
echo "=== Exporting change_traffic_light_phase result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
NET_FILE="${WORK_DIR}/acosta_buslanes.net.xml"

# Check if network file was modified
NET_MODIFIED="false"
if [ -f /tmp/initial_network.xml ] && [ -f "$NET_FILE" ]; then
    if ! diff -q /tmp/initial_network.xml "$NET_FILE" > /dev/null 2>&1; then
        NET_MODIFIED="true"
    fi
fi

# Check if netedit is still running
NETEDIT_RUNNING="false"
if is_netedit_running; then
    NETEDIT_RUNNING="true"
fi

# Check for phase duration of 45 in the network file
HAS_45_DURATION="false"
if grep -q 'duration="45' "$NET_FILE" 2>/dev/null; then
    HAS_45_DURATION="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "netedit_running": $NETEDIT_RUNNING,
    "network_modified": $NET_MODIFIED,
    "has_45_duration": $HAS_45_DURATION,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="
