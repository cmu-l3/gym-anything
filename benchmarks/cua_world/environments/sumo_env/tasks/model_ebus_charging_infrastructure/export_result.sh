#!/bin/bash
echo "=== Exporting ebus charging task results ==="

# Record end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare a dedicated directory to export files for the verifier
EXPORT_DIR="/tmp/ebus_export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Check what outputs the agent created and copy them securely
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

FILES_TO_EXPORT=(
    "$SCENARIO_DIR/charging_stations.add.xml"
    "$SCENARIO_DIR/pasubio_vtypes.add.xml"
    "$SCENARIO_DIR/pasubio_busses.rou.xml"
    "$SCENARIO_DIR/run.sumocfg"
    "$OUTPUT_DIR/battery_output.xml"
    "$OUTPUT_DIR/battery_report.txt"
)

# Copy files and check their timestamps
FILE_METADATA="{ "
FIRST_ENTRY=true

for FILE in "${FILES_TO_EXPORT[@]}"; do
    FILENAME=$(basename "$FILE")
    EXISTS="false"
    MTIME=0
    CREATED_DURING_TASK="false"
    SIZE=0

    if [ -f "$FILE" ]; then
        EXISTS="true"
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        SIZE=$(stat -c %s "$FILE" 2>/dev/null || echo "0")
        cp "$FILE" "$EXPORT_DIR/$FILENAME"
        
        if [ "$MTIME" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi

    if [ "$FIRST_ENTRY" = true ]; then
        FIRST_ENTRY=false
    else
        FILE_METADATA+=","
    fi
    
    FILE_METADATA+="\"$FILENAME\": {"
    FILE_METADATA+="\"exists\": $EXISTS,"
    FILE_METADATA+="\"size\": $SIZE,"
    FILE_METADATA+="\"created_during_task\": $CREATED_DURING_TASK"
    FILE_METADATA+="}"
done

FILE_METADATA+=" }"

# Package results into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": $FILE_METADATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Make sure permissions allow the verifier to read it
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod -R 777 "$EXPORT_DIR"
rm -f "$TEMP_JSON"

echo "Task metadata exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="