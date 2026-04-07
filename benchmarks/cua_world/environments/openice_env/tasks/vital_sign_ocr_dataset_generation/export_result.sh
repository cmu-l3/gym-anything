#!/bin/bash
echo "=== Exporting Vital Sign OCR Dataset Generation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DATASET_DIR="/home/ga/Desktop/ocr_data"
RESULTS_ARRAY="[]"

DATASET_EXISTS="false"
if [ -d "$DATASET_DIR" ]; then
    DATASET_EXISTS="true"
    
    # Process each expected sample
    for i in 1 2 3; do
        IMG_FILE="$DATASET_DIR/hr_sample_$i.png"
        TXT_FILE="$DATASET_DIR/hr_sample_$i.txt"
        
        IMG_EXISTS="false"
        TXT_EXISTS="false"
        IMG_WIDTH=0
        IMG_HEIGHT=0
        TXT_CONTENT=""
        FILE_MTIME=0
        CREATED_DURING_TASK="false"
        
        if [ -f "$IMG_FILE" ]; then
            IMG_EXISTS="true"
            # Get dimensions using identify (ImageMagick) or python fallback
            DIMS=$(identify -format "%w %h" "$IMG_FILE" 2>/dev/null || echo "0 0")
            IMG_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
            IMG_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
            
            # Check timestamp
            FILE_MTIME=$(stat -c %Y "$IMG_FILE" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                CREATED_DURING_TASK="true"
            fi
        fi
        
        if [ -f "$TXT_FILE" ]; then
            TXT_EXISTS="true"
            TXT_CONTENT=$(cat "$TXT_FILE" | tr -d '\n\r' | head -c 20) # Read first 20 chars
        fi
        
        # Build JSON object for this sample
        SAMPLE_JSON="{\"id\": $i, \"img_exists\": $IMG_EXISTS, \"txt_exists\": $TXT_EXISTS, \"width\": $IMG_WIDTH, \"height\": $IMG_HEIGHT, \"label\": \"$(escape_json_value "$TXT_CONTENT")\", \"created_during_task\": $CREATED_DURING_TASK, \"img_path\": \"$IMG_FILE\"}"
        
        # Append to array
        if [ "$RESULTS_ARRAY" == "[]" ]; then
            RESULTS_ARRAY="[$SAMPLE_JSON"
        else
            RESULTS_ARRAY="$RESULTS_ARRAY, $SAMPLE_JSON"
        fi
    done
    RESULTS_ARRAY="$RESULTS_ARRAY]"
fi

# Check if Multiparameter Monitor was created (check logs)
MONITOR_CREATED="false"
if grep -iE "multiparameter|multiParam" /home/ga/openice/logs/openice.log 2>/dev/null | tail -n 100 > /dev/null; then
    MONITOR_CREATED="true"
fi
# Also check window titles
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "multiparameter|monitor" > /dev/null; then
    MONITOR_CREATED="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dataset_dir_exists": $DATASET_EXISTS,
    "monitor_created": $MONITOR_CREATED,
    "samples": $RESULTS_ARRAY,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="