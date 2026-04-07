#!/bin/bash
echo "=== Exporting Publication Montage Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_FILE="/home/ga/AstroImages/publication/eagle_montage.png"

# Gather statistics about the output file
FILE_EXISTS="false"
FILE_SIZE_BYTES="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Read dimensions using ImageMagick
    if command -v identify >/dev/null 2>&1; then
        IMAGE_WIDTH=$(identify -format "%w" "$OUTPUT_FILE" 2>/dev/null || echo "0")
        IMAGE_HEIGHT=$(identify -format "%h" "$OUTPUT_FILE" 2>/dev/null || echo "0")
    else
        # Fallback using python if identify is missing
        DIMS=$(python3 -c "import struct; f=open('$OUTPUT_FILE','rb'); f.read(16); print(','.join(map(str, struct.unpack('>LL', f.read(8)))))" 2>/dev/null || echo "0,0")
        IMAGE_WIDTH=$(echo $DIMS | cut -d',' -f1)
        IMAGE_HEIGHT=$(echo $DIMS | cut -d',' -f2)
    fi
fi

# Check if AstroImageJ is still running
AIJ_RUNNING="false"
if is_aij_running; then
    AIJ_RUNNING="true"
fi

# Safely create JSON result
TEMP_JSON=$(mktemp /tmp/montage_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "created_during_task": $CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "aij_running": $AIJ_RUNNING
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="