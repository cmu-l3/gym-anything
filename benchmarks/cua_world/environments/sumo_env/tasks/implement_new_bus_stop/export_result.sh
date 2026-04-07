#!/bin/bash
echo "=== Exporting implement_new_bus_stop result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUT_DIR="/home/ga/SUMO_Output"

# Capture final state screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# Function to safely get file modification time
get_mtime() {
    if [ -f "$1" ]; then
        stat -c %Y "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Copy the critical files to /tmp/ for the verifier to safely access
echo "Copying files for verifier..."
if [ -f "$WORK_DIR/run.sumocfg" ]; then
    cp "$WORK_DIR/run.sumocfg" /tmp/run.sumocfg.xml
    chmod 666 /tmp/run.sumocfg.xml
fi

if [ -f "$WORK_DIR/pasubio_bus_stops.add.xml" ]; then
    cp "$WORK_DIR/pasubio_bus_stops.add.xml" /tmp/pasubio_bus_stops.add.xml
    chmod 666 /tmp/pasubio_bus_stops.add.xml
fi

if [ -f "$WORK_DIR/pasubio_busses.rou.xml" ]; then
    cp "$WORK_DIR/pasubio_busses.rou.xml" /tmp/pasubio_busses.rou.xml
    chmod 666 /tmp/pasubio_busses.rou.xml
fi

if [ -f "$OUT_DIR/stopinfos.xml" ]; then
    cp "$OUT_DIR/stopinfos.xml" /tmp/stopinfos.xml
    chmod 666 /tmp/stopinfos.xml
fi

if [ -f "$OUT_DIR/new_stop_report.txt" ]; then
    cp "$OUT_DIR/new_stop_report.txt" /tmp/new_stop_report.txt
    chmod 666 /tmp/new_stop_report.txt
fi

# Create JSON result object with metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sumocfg_exists": $([ -f "/tmp/run.sumocfg.xml" ] && echo "true" || echo "false"),
    "sumocfg_mtime": $(get_mtime "/tmp/run.sumocfg.xml"),
    "bus_stops_exists": $([ -f "/tmp/pasubio_bus_stops.add.xml" ] && echo "true" || echo "false"),
    "bus_stops_mtime": $(get_mtime "/tmp/pasubio_bus_stops.add.xml"),
    "busses_exists": $([ -f "/tmp/pasubio_busses.rou.xml" ] && echo "true" || echo "false"),
    "busses_mtime": $(get_mtime "/tmp/pasubio_busses.rou.xml"),
    "stopinfos_exists": $([ -f "/tmp/stopinfos.xml" ] && echo "true" || echo "false"),
    "stopinfos_mtime": $(get_mtime "/tmp/stopinfos.xml"),
    "report_exists": $([ -f "/tmp/new_stop_report.txt" ] && echo "true" || echo "false"),
    "report_mtime": $(get_mtime "/tmp/new_stop_report.txt")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="