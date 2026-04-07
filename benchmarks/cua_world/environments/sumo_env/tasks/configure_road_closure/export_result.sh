#!/bin/bash
echo "=== Exporting road closure result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

REROUTER="$SCENARIO_DIR/road_closure.add.xml"
SUMOCFG="$SCENARIO_DIR/closure_run.sumocfg"
TRIPINFO="$SCENARIO_DIR/closure_tripinfo.xml"
REPORT="$OUTPUT_DIR/closure_report.txt"

get_mtime() {
    stat -c %Y "$1" 2>/dev/null || echo "0"
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "rerouter_mtime": $(get_mtime "$REROUTER"),
    "sumocfg_mtime": $(get_mtime "$SUMOCFG"),
    "tripinfo_mtime": $(get_mtime "$TRIPINFO"),
    "report_mtime": $(get_mtime "$REPORT"),
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="