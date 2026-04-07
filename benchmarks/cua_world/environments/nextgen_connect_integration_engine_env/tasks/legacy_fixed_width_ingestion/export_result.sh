#!/bin/bash
echo "=== Exporting Legacy Ingestion Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Status via API
CHANNEL_NAME="Legacy_Census_Ingest"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_STATUS="UNKNOWN"
CHANNEL_EXISTS="false"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    CHANNEL_STATS=$(get_channel_stats_api "$CHANNEL_ID")
else
    # Fallback: Check if *any* channel was created and matches loosely
    CHANNEL_ID=$(query_postgres "SELECT id FROM channel WHERE name LIKE '%Legacy%' LIMIT 1" 2>/dev/null)
    if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    fi
fi

# 2. Check Container Files (Inbox consumed? Outbox populated?)
CONTAINER_INBOX="/var/spool/mirth/inbox"
CONTAINER_OUTBOX="/var/spool/mirth/outbox"

# Check if input file remains in inbox
INBOX_COUNT=$(docker exec nextgen-connect sh -c "ls $CONTAINER_INBOX/*.dat 2>/dev/null | wc -l")

# Check output files
OUTBOX_COUNT=$(docker exec nextgen-connect sh -c "ls $CONTAINER_OUTBOX/*.json 2>/dev/null | wc -l")

# Extract one JSON file for content verification
SAMPLE_JSON_CONTENT="{}"
if [ "$OUTBOX_COUNT" -gt 0 ]; then
    SAMPLE_FILENAME=$(docker exec nextgen-connect sh -c "ls $CONTAINER_OUTBOX/*.json | head -1")
    if [ -n "$SAMPLE_FILENAME" ]; then
        SAMPLE_JSON_CONTENT=$(docker exec nextgen-connect cat "$SAMPLE_FILENAME")
    fi
fi

# 3. Verify Batch Configuration (Inspect Channel XML)
BATCH_CONFIGURED="false"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID'" 2>/dev/null)
    # Check for Batch properties in Source Connector
    # Looking for <processBatch>true</processBatch> or similar splitting configuration
    # And delimiter config
    if echo "$CHANNEL_XML" | grep -q "<batch>true</batch>" || echo "$CHANNEL_XML" | grep -q "processBatch"; then
        BATCH_CONFIGURED="true"
    fi
fi

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_name": "$CHANNEL_NAME",
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "inbox_file_count": $INBOX_COUNT,
    "outbox_file_count": $OUTBOX_COUNT,
    "sample_json_content": $SAMPLE_JSON_CONTENT,
    "batch_configured": $BATCH_CONFIGURED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json