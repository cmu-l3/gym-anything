#!/bin/bash
# export_result.sh — Mixed Column Layout Flyer

source /workspace/scripts/task_utils.sh

echo "=== Exporting Flyer Task Result ==="

# 1. Take final screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# 2. Check for output file
OUTPUT_ODT="/home/ga/Documents/open_house_flyer.odt"
OUTPUT_DOCX="/home/ga/Documents/open_house_flyer.docx"

OUTPUT_FOUND="false"
OUTPUT_PATH=""
OUTPUT_SIZE=0

if [ -f "$OUTPUT_ODT" ]; then
    OUTPUT_FOUND="true"
    OUTPUT_PATH="$OUTPUT_ODT"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_ODT")
    echo "Found ODT output: $OUTPUT_ODT"
elif [ -f "$OUTPUT_DOCX" ]; then
    OUTPUT_FOUND="true"
    OUTPUT_PATH="$OUTPUT_DOCX"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_DOCX")
    echo "Found DOCX output: $OUTPUT_DOCX (Warning: ODT was requested)"
else
    echo "No output file found."
fi

# 3. Check modification time (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ "$OUTPUT_FOUND" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Export result JSON
cat > /tmp/task_result.json << EOF
{
    "output_found": $OUTPUT_FOUND,
    "output_path": "$OUTPUT_PATH",
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

# 5. Cleanup
# Close Writer politely
if pgrep -f "soffice.bin" > /dev/null; then
    echo "Closing LibreOffice..."
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    # Handle "Save changes?" dialog -> Don't Save
    safe_xdotool ga :1 key alt+d 2>/dev/null || true
fi

echo "=== Export Complete ==="