#!/bin/bash
echo "=== Exporting Legacy CSV Import Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if output files exist
OUTPUT_DIR="/home/ga/hl7_import"
FILE_COUNT=$(ls -1 "$OUTPUT_DIR" 2>/dev/null | wc -l)
echo "Found $FILE_COUNT files in output directory."

# 2. Check if channel exists via DB
CHANNEL_NAME="Legacy_CSV_Import"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_EXISTS="false"
CHANNEL_STATUS="unknown"
SOURCE_TYPE="unknown"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    # Check status
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    
    # Check config for Delimited Text source
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
    if echo "$CHANNEL_XML" | grep -qi "DelimitedTextBatchAdaptor"; then
        SOURCE_TYPE="DelimitedText"
    elif echo "$CHANNEL_XML" | grep -qi "Delimited Text"; then
        SOURCE_TYPE="DelimitedText"
    else
        SOURCE_TYPE="Other"
    fi
fi

# 3. Create Archive of Output Files for Verifier
# We zip/tar the output directory so the python verifier can analyze the actual content
# of the generated HL7 files on the host side.
cd /home/ga
tar -czf /tmp/hl7_output.tar.gz -C /home/ga hl7_import 2>/dev/null || true

# 4. Check timestamps of output files (Anti-gaming)
# Check if at least one file was modified after task start
FILES_CREATED_DURING_TASK="false"
if [ "$FILE_COUNT" -gt 0 ]; then
    NEWEST_FILE=$(ls -t "$OUTPUT_DIR" | head -1)
    NEWEST_MTIME=$(stat -c %Y "$OUTPUT_DIR/$NEWEST_FILE" 2>/dev/null || echo "0")
    if [ "$NEWEST_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_name": "$CHANNEL_NAME",
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "source_type": "$SOURCE_TYPE",
    "output_file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "output_archive_path": "/tmp/hl7_output.tar.gz",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy ground truth to tmp if it exists (created in setup)
if [ -f /tmp/ground_truth.json ]; then
    chmod 666 /tmp/ground_truth.json 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"
echo "Output archive saved to /tmp/hl7_output.tar.gz"
echo "=== Export complete ==="