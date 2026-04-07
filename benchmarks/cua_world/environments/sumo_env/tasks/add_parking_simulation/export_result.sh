#!/bin/bash
echo "=== Exporting add_parking_simulation task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Function to safely stat file modification time
get_mtime() {
    if [ -f "$1" ]; then
        stat -c %Y "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to safely stat file size
get_size() {
    if [ -f "$1" ]; then
        stat -c %s "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Gather file metrics
PARKING_XML_EXISTS=$([ -f "$SCENARIO_DIR/pasubio_parking.add.xml" ] && echo "true" || echo "false")
VEHICLES_XML_EXISTS=$([ -f "$SCENARIO_DIR/parking_vehicles.rou.xml" ] && echo "true" || echo "false")
CONFIG_XML_EXISTS=$([ -f "$SCENARIO_DIR/run_parking.sumocfg" ] && echo "true" || echo "false")
PARKING_OUT_EXISTS=$([ -f "$OUTPUT_DIR/parking_output.xml" ] && echo "true" || echo "false")
TRIPINFO_OUT_EXISTS=$([ -f "$OUTPUT_DIR/tripinfos_parking.xml" ] && echo "true" || echo "false")
LOG_OUT_EXISTS=$([ -f "$OUTPUT_DIR/sumo_parking_log.txt" ] && echo "true" || echo "false")

PARKING_XML_MTIME=$(get_mtime "$SCENARIO_DIR/pasubio_parking.add.xml")
VEHICLES_XML_MTIME=$(get_mtime "$SCENARIO_DIR/parking_vehicles.rou.xml")
CONFIG_XML_MTIME=$(get_mtime "$SCENARIO_DIR/run_parking.sumocfg")
LOG_OUT_MTIME=$(get_mtime "$OUTPUT_DIR/sumo_parking_log.txt")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "parking_xml": {
            "exists": $PARKING_XML_EXISTS,
            "mtime": $PARKING_XML_MTIME,
            "size": $(get_size "$SCENARIO_DIR/pasubio_parking.add.xml")
        },
        "vehicles_xml": {
            "exists": $VEHICLES_XML_EXISTS,
            "mtime": $VEHICLES_XML_MTIME,
            "size": $(get_size "$SCENARIO_DIR/parking_vehicles.rou.xml")
        },
        "config_xml": {
            "exists": $CONFIG_XML_EXISTS,
            "mtime": $CONFIG_XML_MTIME,
            "size": $(get_size "$SCENARIO_DIR/run_parking.sumocfg")
        },
        "parking_output": {
            "exists": $PARKING_OUT_EXISTS,
            "mtime": $(get_mtime "$OUTPUT_DIR/parking_output.xml"),
            "size": $(get_size "$OUTPUT_DIR/parking_output.xml")
        },
        "tripinfo_output": {
            "exists": $TRIPINFO_OUT_EXISTS,
            "mtime": $(get_mtime "$OUTPUT_DIR/tripinfos_parking.xml"),
            "size": $(get_size "$OUTPUT_DIR/tripinfos_parking.xml")
        },
        "log_output": {
            "exists": $LOG_OUT_EXISTS,
            "mtime": $LOG_OUT_MTIME,
            "size": $(get_size "$OUTPUT_DIR/sumo_parking_log.txt")
        }
    }
}
EOF

# Move to final location
rm -f /tmp/parking_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/parking_task_result.json
chmod 666 /tmp/parking_task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="