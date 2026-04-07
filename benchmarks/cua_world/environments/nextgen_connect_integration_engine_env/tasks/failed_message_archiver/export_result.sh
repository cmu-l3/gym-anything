#!/bin/bash
echo "=== Exporting Failed Message Archiver Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
CHANNEL_EXISTS="false"
CHANNEL_ID=""
QUEUE_DISABLED="false"
RETRY_ZERO="false"
ERROR_STAT_INCREMENTED="false"
FILE_ARCHIVED="false"
ARCHIVED_FILE_MATCH="false"
SCRIPT_DETECTED="false"

# 1. Verify Channel Existence & Configuration
CHANNEL_DATA=$(query_postgres "SELECT id, channel FROM channel WHERE name = 'Fail_Safe_Archiver';" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | cut -d'|' -f1)
    CHANNEL_XML=$(echo "$CHANNEL_DATA" | cut -d'|' -f2-)
    
    # Check Queue Settings (XML parsing via grep/python)
    # Looking for <queueConnector>false</queueConnector> OR <rotate>false</rotate> depending on version/connector
    # In 4.x TCP Sender:
    # <queueConnector>false</queueConnector> -> Queue: Never
    # <sendFirst>false</sendFirst> -> also relevant
    # <retryCount>0</retryCount>
    
    if echo "$CHANNEL_XML" | grep -q "<queueConnector>false</queueConnector>"; then
        QUEUE_DISABLED="true"
    fi
    
    if echo "$CHANNEL_XML" | grep -q "<retryCount>0</retryCount>"; then
        RETRY_ZERO="true"
    fi

    # Check for Post-Processor Script
    # The script is stored in the <code> tag of a <channelScript> where type is 'Postprocessor'
    # Simplified check: look for FileUtil.write or similar in the channel XML
    if echo "$CHANNEL_XML" | grep -qiE "FileUtil\.write|FileWriter|FileOutputStream"; then
        SCRIPT_DETECTED="true"
    fi
    
    # 2. Check Channel Statistics (Did it error?)
    if [ -n "$CHANNEL_ID" ]; then
        STATS_JSON=$(curl -sk -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            "https://localhost:8443/api/channels/$CHANNEL_ID/statistics" 2>/dev/null)
        
        ERROR_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('channelStatistics', {}).get('error', 0))" 2>/dev/null || echo "0")
        
        if [ "$ERROR_COUNT" -gt 0 ]; then
            ERROR_STAT_INCREMENTED="true"
        fi
    fi
fi

# 3. Verify Archived File
# List files in container dir
FILE_LIST=$(docker exec nextgen-connect ls /tmp/failed_messages/ 2>/dev/null || true)

if [ -n "$FILE_LIST" ]; then
    FILE_ARCHIVED="true"
    FIRST_FILE=$(echo "$FILE_LIST" | head -n1)
    
    # Read content
    ARCHIVED_CONTENT=$(docker exec nextgen-connect cat "/tmp/failed_messages/$FIRST_FILE" 2>/dev/null)
    ORIGINAL_CONTENT=$(cat /home/ga/sample.hl7)
    
    # Normalize for comparison (remove whitespace/newlines)
    NORM_ARCH=$(echo "$ARCHIVED_CONTENT" | tr -d '[:space:]')
    NORM_ORIG=$(echo "$ORIGINAL_CONTENT" | tr -d '[:space:]')
    
    if [[ "$NORM_ARCH" == *"$NORM_ORIG"* ]]; then
        ARCHIVED_FILE_MATCH="true"
    fi
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "queue_disabled": $QUEUE_DISABLED,
    "retry_zero": $RETRY_ZERO,
    "script_detected": $SCRIPT_DETECTED,
    "error_stat_incremented": $ERROR_STAT_INCREMENTED,
    "file_archived": $FILE_ARCHIVED,
    "archived_file_match": $ARCHIVED_FILE_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="