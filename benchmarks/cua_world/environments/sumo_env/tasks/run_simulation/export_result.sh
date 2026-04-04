#!/bin/bash
echo "=== Exporting run_simulation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if sumo-gui is still running
SUMO_RUNNING="false"
if is_sumo_gui_running; then
    SUMO_RUNNING="true"
fi

# Check for tripinfo output (generated when simulation runs)
TRIPINFO_EXISTS="false"
TRIPINFO_SIZE=0
if [ -f /home/ga/SUMO_Scenarios/bologna_acosta/tripinfos.xml ]; then
    TRIPINFO_EXISTS="true"
    TRIPINFO_SIZE=$(stat -c%s /home/ga/SUMO_Scenarios/bologna_acosta/tripinfos.xml 2>/dev/null || echo "0")
fi

# Check for sumo log
LOG_EXISTS="false"
if [ -f /home/ga/SUMO_Scenarios/bologna_acosta/sumo_log.txt ]; then
    LOG_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sumo_running": $SUMO_RUNNING,
    "tripinfo_exists": $TRIPINFO_EXISTS,
    "tripinfo_size_bytes": $TRIPINFO_SIZE,
    "log_exists": $LOG_EXISTS,
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
