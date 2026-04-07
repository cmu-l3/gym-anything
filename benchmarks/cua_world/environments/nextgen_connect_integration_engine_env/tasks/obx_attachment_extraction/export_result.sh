#!/bin/bash
echo "=== Exporting OBX Extraction Result ==="

source /workspace/scripts/task_utils.sh

# Record export time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. SEND TEST MESSAGE (Verification Step)
# We deliberately send the test message NOW to verify the channel actually works
# even if the agent didn't test it themselves.
echo "Sending verification test message..."
if [ -f "/home/ga/test_data/test_oru_message.hl7" ]; then
    # Wrap in MLLP characters (VT ... FS CR)
    # \x0b is VT, \x1c is FS, \x0d is CR
    printf '\x0b' > /tmp/mllp_msg.dat
    cat /home/ga/test_data/test_oru_message.hl7 >> /tmp/mllp_msg.dat
    printf '\x1c\x0d' >> /tmp/mllp_msg.dat
    
    # Send to port 6661
    nc -w 2 localhost 6661 < /tmp/mllp_msg.dat > /tmp/nc_response.txt 2>&1 || true
    echo "Message sent to port 6661"
else
    echo "Test message not found!"
fi

# Give it a moment to process
sleep 5

# 2. CAPTURE FINAL SCREENSHOT
take_screenshot /tmp/task_final.png

# 3. CHECK CHANNEL STATUS via API
CHANNEL_INFO="{}"
CHANNEL_ID=$(get_channel_id "Lab_Report_Extractor")
CHANNEL_STATUS="UNKNOWN"
CHANNEL_STATS_RECEIVED=0

if [ -n "$CHANNEL_ID" ]; then
    echo "Found channel ID: $CHANNEL_ID"
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    
    # Get statistics
    STATS_JSON=$(get_channel_stats_api "$CHANNEL_ID")
    CHANNEL_STATS_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
    
    # Get configuration to check port
    CHANNEL_XML=$(api_call GET "/channels/$CHANNEL_ID")
    LISTENER_PORT=$(echo "$CHANNEL_XML" | grep -oP '<port>\K\d+' | head -1 || echo "")
else
    echo "Channel 'Lab_Report_Extractor' not found."
fi

# 4. CHECK OUTPUT FILE
OUTPUT_DIR="/home/ga/lab_reports"
FOUND_FILE=""
FILE_CREATED_DURING_TASK="false"
IS_VALID_PDF="false"
HAS_MRN="false"

# Look for any PDF file in output dir
# We sort by time to get the most recent one
LATEST_PDF=$(find "$OUTPUT_DIR" -name "*.pdf" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

if [ -n "$LATEST_PDF" ]; then
    echo "Found output PDF: $LATEST_PDF"
    FOUND_FILE="$LATEST_PDF"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$LATEST_PDF")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check content (Magic bytes)
    if head -c 4 "$LATEST_PDF" | grep -q "%PDF"; then
        IS_VALID_PDF="true"
    fi
    
    # Check filename for MRN "PAT78432"
    FILENAME=$(basename "$LATEST_PDF")
    if [[ "$FILENAME" == *"PAT78432"* ]]; then
        HAS_MRN="true"
    fi
fi

# 5. COMPILE RESULT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_id": "${CHANNEL_ID:-}",
    "channel_status": "${CHANNEL_STATUS:-UNKNOWN}",
    "listener_port": "${LISTENER_PORT:-}",
    "messages_received": ${CHANNEL_STATS_RECEIVED:-0},
    "output_file_found": $([ -n "$FOUND_FILE" ] && echo "true" || echo "false"),
    "output_file_path": "${FOUND_FILE:-}",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_pdf": $IS_VALID_PDF,
    "filename_has_mrn": $HAS_MRN,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json