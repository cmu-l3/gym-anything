#!/bin/bash
echo "=== Exporting Configure Variable Speed Signs Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Stat tripinfos.xml (Simulation Output)
TRIPINFOS="$SCENARIO_DIR/tripinfos.xml"
if [ -f "$TRIPINFOS" ]; then
    TRIPINFOS_EXISTS="true"
    TRIPINFOS_MTIME=$(stat -c %Y "$TRIPINFOS" 2>/dev/null || echo "0")
    TRIPINFOS_SIZE=$(stat -c %s "$TRIPINFOS" 2>/dev/null || echo "0")
else
    TRIPINFOS_EXISTS="false"
    TRIPINFOS_MTIME="0"
    TRIPINFOS_SIZE="0"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tripinfos_exists": $TRIPINFOS_EXISTS,
    "tripinfos_mtime": $TRIPINFOS_MTIME,
    "tripinfos_size": $TRIPINFOS_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written."
echo "=== Export complete ==="