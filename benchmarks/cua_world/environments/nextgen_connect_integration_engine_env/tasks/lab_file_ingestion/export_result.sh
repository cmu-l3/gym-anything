#!/bin/bash
echo "=== Exporting lab_file_ingestion task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Channel Information
CHANNEL_INFO=$(query_postgres "SELECT id, name, channel FROM channel WHERE LOWER(name) LIKE '%lab%result%' OR LOWER(name) LIKE '%file%ingestion%' OR LOWER(name) LIKE '%lab%file%';" 2>/dev/null || true)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f1)
CHANNEL_NAME=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f2)
CHANNEL_XML=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f3-)

if [ -z "$CHANNEL_ID" ]; then
    # Fallback to latest created channel
    CHANNEL_INFO=$(query_postgres "SELECT id, name, channel FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    CHANNEL_ID=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f2)
    CHANNEL_XML=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f3-)
fi

# 2. Analyze Channel Configuration (XML)
SOURCE_TYPE=""
DEST_TYPE=""
INPUT_DIR=""
OUTPUT_DIR=""
PROCESSED_DIR=""
TRANSFORMER_MATCH="false"

if [ -n "$CHANNEL_XML" ]; then
    # Check Source Type
    if echo "$CHANNEL_XML" | grep -qi "FileReaderProperties"; then
        SOURCE_TYPE="FileReader"
    fi
    
    # Check Dest Type
    if echo "$CHANNEL_XML" | grep -qi "FileDispatcherProperties"; then
        DEST_TYPE="FileWriter"
    fi

    # Extract directories (naive regex, dependent on XML structure)
    # Looking for <host>...</host> inside properties. 
    # This is tricky with regex on raw XML, but sufficient for simple verification
    INPUT_DIR=$(echo "$CHANNEL_XML" | grep -oP "<host>\K[^<]+" | head -1) # Likely source
    
    # Check for processed directory in source properties
    if echo "$CHANNEL_XML" | grep -qi "/opt/mirthdata/processed"; then
        PROCESSED_DIR="Correct"
    fi
    
    # Check for transformer logic
    if echo "$CHANNEL_XML" | grep -qi "LAB_REPOSITORY"; then
        TRANSFORMER_MATCH="true"
    fi
fi

# 3. Check Channel Status
CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")

# 4. Functional Verification (File System Checks inside Container)
# Check input directory creation
DIR_INPUT_EXISTS=$(docker exec nextgen-connect test -d /opt/mirthdata/input && echo "true" || echo "false")
DIR_OUTPUT_EXISTS=$(docker exec nextgen-connect test -d /opt/mirthdata/output && echo "true" || echo "false")
DIR_PROCESSED_EXISTS=$(docker exec nextgen-connect test -d /opt/mirthdata/processed && echo "true" || echo "false")

# Check if output file was created
OUTPUT_FILE_COUNT=$(docker exec nextgen-connect ls /opt/mirthdata/output/ 2>/dev/null | grep -c "\.hl7" || echo "0")
OUTPUT_FILE_CONTENT=""

if [ "$OUTPUT_FILE_COUNT" -gt 0 ]; then
    # Get content of the latest output file
    LATEST_FILE=$(docker exec nextgen-connect ls -t /opt/mirthdata/output/ | head -1)
    OUTPUT_FILE_CONTENT=$(docker exec nextgen-connect cat "/opt/mirthdata/output/$LATEST_FILE")
fi

# Check if source file was moved to processed
PROCESSED_FILE_COUNT=$(docker exec nextgen-connect ls /opt/mirthdata/processed/ 2>/dev/null | grep -c "test_oru" || echo "0")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_name": "$CHANNEL_NAME",
    "channel_id": "$CHANNEL_ID",
    "source_type": "$SOURCE_TYPE",
    "dest_type": "$DEST_TYPE",
    "transformer_match": $TRANSFORMER_MATCH,
    "channel_status": "$CHANNEL_STATUS",
    "dir_input_exists": $DIR_INPUT_EXISTS,
    "dir_output_exists": $DIR_OUTPUT_EXISTS,
    "dir_processed_exists": $DIR_PROCESSED_EXISTS,
    "output_file_count": $OUTPUT_FILE_COUNT,
    "processed_file_count": $PROCESSED_FILE_COUNT,
    "output_content_sample": "$(echo "$OUTPUT_FILE_CONTENT" | tr -d '\n' | sed 's/"/\\"/g' | cut -c 1-500)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json