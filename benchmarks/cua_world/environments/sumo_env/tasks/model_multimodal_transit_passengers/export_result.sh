#!/bin/bash
echo "=== Exporting model_multimodal_transit_passengers result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
PED_FILE="$WORK_DIR/pedestrians.rou.xml"
CFG_FILE="$WORK_DIR/run.sumocfg"
OUT_FILE="/home/ga/SUMO_Output/personinfo.xml"

# Check output file status
OUT_EXISTS="false"
OUT_MTIME="0"
OUT_SIZE="0"
if [ -f "$OUT_FILE" ]; then
    OUT_EXISTS="true"
    OUT_MTIME=$(stat -c %Y "$OUT_FILE" 2>/dev/null || echo "0")
    OUT_SIZE=$(stat -c %s "$OUT_FILE" 2>/dev/null || echo "0")
    # Copy to /tmp/ for easy access by verifier
    cp "$OUT_FILE" /tmp/personinfo.xml
    chmod 666 /tmp/personinfo.xml
fi

# Check pedestrian file status
PED_EXISTS="false"
PED_MTIME="0"
if [ -f "$PED_FILE" ]; then
    PED_EXISTS="true"
    PED_MTIME=$(stat -c %Y "$PED_FILE" 2>/dev/null || echo "0")
    cp "$PED_FILE" /tmp/pedestrians.rou.xml
    chmod 666 /tmp/pedestrians.rou.xml
fi

# Check config modification
CFG_EXISTS="false"
CFG_MTIME="0"
if [ -f "$CFG_FILE" ]; then
    CFG_EXISTS="true"
    CFG_MTIME=$(stat -c %Y "$CFG_FILE" 2>/dev/null || echo "0")
    cp "$CFG_FILE" /tmp/run.sumocfg
    chmod 666 /tmp/run.sumocfg
fi

# Determine if files were genuinely created/modified during task
FILES_MODIFIED_DURING_TASK="false"
if [ "$OUT_MTIME" -gt "$TASK_START" ] || [ "$PED_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ped_file_exists": $PED_EXISTS,
    "cfg_file_exists": $CFG_EXISTS,
    "out_file_exists": $OUT_EXISTS,
    "out_file_size": $OUT_SIZE,
    "files_modified_during_task": $FILES_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="