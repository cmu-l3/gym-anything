#!/bin/bash
echo "=== Exporting stream_brainflow_udp_playback result ==="

# Source utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot BEFORE killing anything
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Stop UDP Listener and Collect Stats
# ============================================================
echo "Stopping UDP listener..."
pkill -SIGTERM -f "udp_listener.py" || true
sleep 1

STATS_FILE="/tmp/udp_listener_stats.json"
PACKET_COUNT=0
IS_JSON="false"
IS_BINARY="false"

if [ -f "$STATS_FILE" ]; then
    echo "Reading stats from $STATS_FILE"
    cat "$STATS_FILE"
    # Parse values using python one-liner for robustness
    PACKET_COUNT=$(python3 -c "import json; print(json.load(open('$STATS_FILE')).get('packet_count', 0))" 2>/dev/null || echo 0)
    IS_JSON=$(python3 -c "import json; print(str(json.load(open('$STATS_FILE')).get('is_json', False)).lower())" 2>/dev/null || echo "false")
    IS_BINARY=$(python3 -c "import json; print(str(json.load(open('$STATS_FILE')).get('is_binary', False)).lower())" 2>/dev/null || echo "false")
else
    echo "WARNING: Stats file not found!"
fi

# ============================================================
# 2. Check Application State
# ============================================================
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "packet_count": $PACKET_COUNT,
    "is_json": $IS_JSON,
    "is_binary": $IS_BINARY,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="