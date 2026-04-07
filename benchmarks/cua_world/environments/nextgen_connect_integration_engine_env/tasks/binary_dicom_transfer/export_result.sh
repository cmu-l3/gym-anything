#!/bin/bash
echo "=== Exporting Binary DICOM Transfer Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Retrieve timestamps and initial data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MD5=$(cat /tmp/initial_dicom_md5.txt 2>/dev/null || echo "")

INPUT_FILE="/home/ga/dicom_input/CT_small.dcm"
OUTPUT_DIR="/home/ga/dicom_output"

# 2. Find Output File
# Look for any file in output dir that ends with .dcm
FOUND_FILE=$(find "$OUTPUT_DIR" -name "*.dcm" -type f | head -n 1)

OUTPUT_EXISTS="false"
OUTPUT_FILENAME=""
OUTPUT_MD5=""
FILE_CREATED_DURING_TASK="false"
MD5_MATCH="false"
FILENAME_CORRECT="false"

if [ -n "$FOUND_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_FILENAME=$(basename "$FOUND_FILE")
    OUTPUT_MD5=$(md5sum "$FOUND_FILE" | cut -d' ' -f1)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check MD5 integrity
    if [ "$OUTPUT_MD5" = "$INITIAL_MD5" ]; then
        MD5_MATCH="true"
    fi

    # Check filename pattern
    if [[ "$OUTPUT_FILENAME" == *"_migrated.dcm" ]]; then
        FILENAME_CORRECT="true"
    fi
fi

# 3. Check Channel Status
CHANNEL_NAME="DICOM_Migration"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_EXISTS="false"
CHANNEL_STATE="UNKNOWN"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    # Get status via API
    CHANNEL_STATE=$(get_channel_status_api "$CHANNEL_ID")
fi

# 4. Create JSON Result
JSON_CONTENT=$(cat <<EOF
{
    "task_start": $TASK_START,
    "input_md5": "$INITIAL_MD5",
    "output_exists": $OUTPUT_EXISTS,
    "output_filename": "$OUTPUT_FILENAME",
    "output_md5": "$OUTPUT_MD5",
    "md5_match": $MD5_MATCH,
    "filename_correct": $FILENAME_CORRECT,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_state": "$CHANNEL_STATE"
}
EOF
)

# Write result safely
write_result_json "/tmp/dicom_task_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/dicom_task_result.json"
cat /tmp/dicom_task_result.json
echo "=== Export Complete ==="