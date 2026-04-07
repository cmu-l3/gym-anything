#!/bin/bash
echo "=== Exporting evaluate_bus_dwell_time_impact result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

BUS_FILE="${SCENARIO_DIR}/pasubio_busses_slow.rou.xml"
CFG_FILE="${SCENARIO_DIR}/run_slow_buses.sumocfg"

# Handle potential agent path variations
TRIP_FILE="${OUTPUT_DIR}/tripinfos_slow.xml"
if [ ! -f "$TRIP_FILE" ] && [ -f "${SCENARIO_DIR}/tripinfos_slow.xml" ]; then
    TRIP_FILE="${SCENARIO_DIR}/tripinfos_slow.xml"
fi

REPORT_FILE="${OUTPUT_DIR}/bus_impact_report.txt"
if [ ! -f "$REPORT_FILE" ] && [ -f "${SCENARIO_DIR}/bus_impact_report.txt" ]; then
    REPORT_FILE="${SCENARIO_DIR}/bus_impact_report.txt"
fi

# Clear out any previous temp files
rm -f /tmp/pasubio_busses_slow.rou.xml /tmp/run_slow_buses.sumocfg /tmp/tripinfos_slow.xml /tmp/bus_impact_report.txt

# File existence tracking
BUS_EXISTS="false"
CFG_EXISTS="false"
TRIP_EXISTS="false"
REPORT_EXISTS="false"

# Copy files to /tmp for the verifier to safely read
if [ -f "$BUS_FILE" ]; then
    cp "$BUS_FILE" /tmp/pasubio_busses_slow.rou.xml
    chmod 666 /tmp/pasubio_busses_slow.rou.xml
    BUS_EXISTS="true"
fi

if [ -f "$CFG_FILE" ]; then
    cp "$CFG_FILE" /tmp/run_slow_buses.sumocfg
    chmod 666 /tmp/run_slow_buses.sumocfg
    CFG_EXISTS="true"
fi

if [ -f "$TRIP_FILE" ]; then
    cp "$TRIP_FILE" /tmp/tripinfos_slow.xml
    chmod 666 /tmp/tripinfos_slow.xml
    TRIP_EXISTS="true"
fi

if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/bus_impact_report.txt
    chmod 666 /tmp/bus_impact_report.txt
    REPORT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bus_file_exists": $BUS_EXISTS,
    "cfg_file_exists": $CFG_EXISTS,
    "tripinfo_exists": $TRIP_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="