#!/bin/bash
echo "=== Exporting relocate_bus_stop_farside result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Copy essential files to /tmp/ for the verifier to extract via copy_from_env
cp $SCENARIO_DIR/pasubio_bus_stops.add.xml /tmp/agent_bus_stops.add.xml 2>/dev/null || true
cp $SCENARIO_DIR/pasubio_bus_stops.add.xml.bak /tmp/orig_bus_stops.add.xml 2>/dev/null || true
cp $SCENARIO_DIR/pasubio_busses.rou.xml.bak /tmp/orig_busses.rou.xml 2>/dev/null || true

[ -f "$OUTPUT_DIR/baseline_tripinfos.xml" ] && cp "$OUTPUT_DIR/baseline_tripinfos.xml" /tmp/baseline_tripinfos.xml
[ -f "$OUTPUT_DIR/modified_tripinfos.xml" ] && cp "$OUTPUT_DIR/modified_tripinfos.xml" /tmp/modified_tripinfos.xml
[ -f "$OUTPUT_DIR/bus_stop_relocation_report.txt" ] && cp "$OUTPUT_DIR/bus_stop_relocation_report.txt" /tmp/agent_report.txt

# File existence & anti-gaming checks
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
MOD_MTIME=$(stat -c%Y "$OUTPUT_DIR/modified_tripinfos.xml" 2>/dev/null || echo "0")

MODIFIED_DURING_TASK="false"
if [ "$MOD_MTIME" -ge "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# Create metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "baseline_exists": $([ -f "$OUTPUT_DIR/baseline_tripinfos.xml" ] && echo "true" || echo "false"),
    "modified_exists": $([ -f "$OUTPUT_DIR/modified_tripinfos.xml" ] && echo "true" || echo "false"),
    "modified_during_task": $MODIFIED_DURING_TASK,
    "report_exists": $([ -f "$OUTPUT_DIR/bus_stop_relocation_report.txt" ] && echo "true" || echo "false")
}
EOF

# Move metadata to final readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Fix permissions on /tmp files so host verifier can read them easily
chmod 666 /tmp/agent_bus_stops.add.xml /tmp/orig_bus_stops.add.xml /tmp/orig_busses.rou.xml /tmp/baseline_tripinfos.xml /tmp/modified_tripinfos.xml /tmp/agent_report.txt 2>/dev/null || true

echo "=== Export complete ==="