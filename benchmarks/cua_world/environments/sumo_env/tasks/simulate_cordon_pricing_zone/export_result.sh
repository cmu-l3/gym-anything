#!/bin/bash
echo "=== Exporting simulate_cordon_pricing_zone result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Array of expected output files
FILES=(
    "base_edgedata.xml"
    "pricing_weights.xml"
    "priced_routes.rou.xml"
    "priced_edgedata.xml"
    "pricing_report.txt"
)

# Move files to /tmp/ for verifier access and check their status
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start_time\": $TASK_START," >> "$TEMP_JSON"

for i in "${!FILES[@]}"; do
    FILE="${FILES[$i]}"
    FILE_PATH="/home/ga/SUMO_Output/$FILE"
    SAFE_NAME=$(echo "$FILE" | sed 's/\./_/g')
    
    EXISTS="false"
    CREATED_DURING_TASK="false"
    SIZE=0
    
    if [ -f "$FILE_PATH" ]; then
        EXISTS="true"
        SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
        MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        
        if [ "$MTIME" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
        
        # Copy to tmp so the verifier can read it via copy_from_env
        cp "$FILE_PATH" "/tmp/$FILE" 2>/dev/null || sudo cp "$FILE_PATH" "/tmp/$FILE"
        chmod 644 "/tmp/$FILE" 2>/dev/null || sudo chmod 644 "/tmp/$FILE"
    fi
    
    echo "  \"${SAFE_NAME}_exists\": $EXISTS," >> "$TEMP_JSON"
    echo "  \"${SAFE_NAME}_created\": $CREATED_DURING_TASK," >> "$TEMP_JSON"
    echo "  \"${SAFE_NAME}_size\": $SIZE" >> "$TEMP_JSON"
    
    if [ $i -lt $((${#FILES[@]} - 1)) ]; then
        echo "  ," >> "$TEMP_JSON"
    else
        echo "" >> "$TEMP_JSON"
    fi
done

echo "}" >> "$TEMP_JSON"

# Save main result JSON
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="