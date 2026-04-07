#!/bin/bash
echo "=== Exporting evaluate_phased_evacuation result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

WORK_DIR="/home/ga/SUMO_Scenarios/evacuation"
OUTPUT_FILES=(
    "uncoordinated.rou.xml"
    "wave1.rou.xml"
    "wave2.rou.xml"
    "uncoordinated.sumocfg"
    "phased.sumocfg"
    "tripinfo_uncoordinated.xml"
    "tripinfo_phased.xml"
    "evacuation_metrics.json"
)

# Prepare result payload
CREATED_DURING_TASK="true"
MISSING_FILES=0

# Clean up /tmp destination first
rm -f /tmp/evac_*.xml /tmp/evac_*.sumocfg /tmp/evac_metrics.json

# Copy files to /tmp for the verifier to safely read via copy_from_env
for FILE in "${OUTPUT_FILES[@]}"; do
    FILE_PATH="$WORK_DIR/$FILE"
    SAFE_NAME=$(echo "$FILE" | tr '/' '_')
    
    if [ -f "$FILE_PATH" ]; then
        MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        if [ "$MTIME" -lt "$TASK_START" ]; then
            CREATED_DURING_TASK="false"
        fi
        cp "$FILE_PATH" "/tmp/evac_$SAFE_NAME"
        chmod 666 "/tmp/evac_$SAFE_NAME"
    else
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

DIR_EXISTS="false"
if [ -d "$WORK_DIR" ]; then
    DIR_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dir_exists": $DIR_EXISTS,
    "files_created_during_task": $CREATED_DURING_TASK,
    "missing_files_count": $MISSING_FILES,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="