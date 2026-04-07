#!/bin/bash
echo "=== Exporting City 30 Noise Impact task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Required files
FILES=(
    "baseline_tripinfo.xml"
    "baseline_noise.xml"
    "pasubio_city30.net.xml"
    "city30_tripinfo.xml"
    "city30_noise.xml"
)

# Collect file stats
JSON_FILES_ARRAY="["
FIRST=true

for file in "${FILES[@]}"; do
    PATH="/home/ga/SUMO_Output/$file"
    EXISTS="false"
    SIZE=0
    CREATED_DURING_TASK="false"
    
    if [ -f "$PATH" ]; then
        EXISTS="true"
        SIZE=$(stat -c %s "$PATH" 2>/dev/null || echo "0")
        MTIME=$(stat -c %Y "$PATH" 2>/dev/null || echo "0")
        
        if [ "$MTIME" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        JSON_FILES_ARRAY="$JSON_FILES_ARRAY,"
    fi
    
    JSON_FILES_ARRAY="$JSON_FILES_ARRAY {
        \"filename\": \"$file\",
        \"path\": \"$PATH\",
        \"exists\": $EXISTS,
        \"size_bytes\": $SIZE,
        \"created_during_task\": $CREATED_DURING_TASK
    }"
done
JSON_FILES_ARRAY="$JSON_FILES_ARRAY ]"

# Check if SUMO tools were used
SUMO_PROCESSES_RAN="false"
if grep -q "sumo" ~/.bash_history 2>/dev/null || grep -q "netconvert" ~/.bash_history 2>/dev/null || pgrep -f "sumo" > /dev/null; then
    SUMO_PROCESSES_RAN="true"
fi

# Write results to temporary JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": $JSON_FILES_ARRAY,
    "sumo_processes_ran": $SUMO_PROCESSES_RAN
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="