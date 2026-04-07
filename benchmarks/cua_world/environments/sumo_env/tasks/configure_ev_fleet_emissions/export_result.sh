#!/bin/bash
echo "=== Exporting Configure EV Fleet Emissions result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUT_DIR="/home/ga/SUMO_Output"

# File Paths
VTYPE_FILE="$WORK_DIR/ev_vtypes.add.xml"
ROUTE_FILE="$WORK_DIR/acosta_fleet.rou.xml"
CFG_FILE="$WORK_DIR/ev_run.sumocfg"
EMISSIONS_FILE="$OUT_DIR/emissions.xml"
TRIPINFO_FILE="$OUT_DIR/ev_tripinfo.xml"
REPORT_FILE="$OUT_DIR/ev_fleet_report.txt"

# Helper function to check file stats
get_file_stats() {
    local path=$1
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Collect stats
VTYPE_STATS=$(get_file_stats "$VTYPE_FILE")
ROUTE_STATS=$(get_file_stats "$ROUTE_FILE")
CFG_STATS=$(get_file_stats "$CFG_FILE")
EMISSION_STATS=$(get_file_stats "$EMISSIONS_FILE")
TRIPINFO_STATS=$(get_file_stats "$TRIPINFO_FILE")
REPORT_STATS=$(get_file_stats "$REPORT_FILE")

# Copy user files to /tmp/ for verifier to easily read
rm -f /tmp/vtypes.xml /tmp/cfg.xml /tmp/report.txt /tmp/emissions_head.xml 2>/dev/null || true

if [ -f "$VTYPE_FILE" ]; then cp "$VTYPE_FILE" /tmp/vtypes.xml; chmod 666 /tmp/vtypes.xml; fi
if [ -f "$CFG_FILE" ]; then cp "$CFG_FILE" /tmp/cfg.xml; chmod 666 /tmp/cfg.xml; fi
if [ -f "$REPORT_FILE" ]; then cp "$REPORT_FILE" /tmp/report.txt; chmod 666 /tmp/report.txt; fi

# For emissions.xml, it might be large. Just grab the first 5000 lines for structural verification
if [ -f "$EMISSIONS_FILE" ]; then
    head -n 5000 "$EMISSIONS_FILE" > /tmp/emissions_head.xml
    # Make sure it's valid XML by appending closing tags if cut off
    echo -e "\n</timestep>\n</emissions>" >> /tmp/emissions_head.xml
    chmod 666 /tmp/emissions_head.xml
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "vtypes": $VTYPE_STATS,
        "routes": $ROUTE_STATS,
        "cfg": $CFG_STATS,
        "emissions": $EMISSION_STATS,
        "tripinfo": $TRIPINFO_STATS,
        "report": $REPORT_STATS
    }
}
EOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="