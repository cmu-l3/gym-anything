#!/bin/bash
echo "=== Exporting bulk_import_historical_data results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# 3. Check Input Existence
INPUT_EXISTS="false"
INPUT_PROCESS_CONFIGURED="false"
INPUT_DATA=$(db_query "SELECT id, processList FROM input WHERE nodeid='building_annex' AND name='power'" 2>/dev/null)

if [ -n "$INPUT_DATA" ]; then
    INPUT_EXISTS="true"
    PROCESS_LIST=$(echo "$INPUT_DATA" | awk '{print $2}')
    if [ -n "$PROCESS_LIST" ] && [ "$PROCESS_LIST" != "NULL" ]; then
        INPUT_PROCESS_CONFIGURED="true"
    fi
fi

# 4. Check Feed Existence & Data
FEED_EXISTS="false"
FEED_ENGINE=""
FEED_INTERVAL=""
FEED_COUNT=0
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='annex_power' AND userid=1" 2>/dev/null | head -1)

if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    FEED_INFO=$(db_query "SELECT engine, importance FROM feeds WHERE id=$FEED_ID" 2>/dev/null)
    FEED_ENGINE=$(echo "$FEED_INFO" | awk '{print $1}')
    # Note: 'importance' column in emoncms feeds table often stores interval for PHPFina? 
    # Actually, interval is in the meta file for PHPFina.
    
    # Let's use API to get data count if possible, or just trust the feed meta if updated.
    # We can fetch the feed meta via API
    APIKEY=$(get_apikey_read)
    FEED_META_JSON=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}")
    
    # Parse JSON to find our feed and get 'npoints' or check data directly
    # Using python to parse robustly
    FEED_STATS=$(python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for feed in data:
        if str(feed['id']) == '$FEED_ID':
            print(json.dumps({
                'engine': feed.get('engine'),
                'interval': feed.get('interval'),
                'value': feed.get('value'),
                'time': feed.get('time')
            }))
            break
except:
    print('{}')
" <<< "$FEED_META_JSON")
    
    FEED_INTERVAL=$(echo "$FEED_STATS" | jq -r .interval)
    
    # To get actual count of data points, we query the feed data range
    # Since we imported data 24h ago, we query start=now-26h, end=now
    NOW=$(date +%s)
    START=$((NOW - 90000))
    # fetch data points (interval 600s to see them all, or skip check count directly)
    # The most reliable way for PHPFina is to check file size or use API
    # 144 points * 4 bytes = 576 bytes. But sparse file...
    # API feed/data.json request
    DATA_RESP=$(curl -s "${EMONCMS_URL}/feed/data.json?apikey=${APIKEY}&id=${FEED_ID}&start=${START}&end=${NOW}&interval=600")
    
    # Count non-null values
    FEED_COUNT=$(echo "$DATA_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for x in data if x[1] is not None)
    print(count)
except:
    print(0)
")
fi

# 5. Check Result File
RESULT_FILE_EXISTS="false"
RESULT_FILE_CONTENT=""
RESULT_FILE_MATCH="false"
RESULT_PATH="/home/ga/annex_import_result.txt"

if [ -f "$RESULT_PATH" ]; then
    RESULT_FILE_EXISTS="true"
    RESULT_FILE_CONTENT=$(cat "$RESULT_PATH")
    # Basic format check
    if echo "$RESULT_FILE_CONTENT" | grep -q "feed_name:annex_power" && echo "$RESULT_FILE_CONTENT" | grep -q "datapoints:"; then
        RESULT_FILE_MATCH="true"
    fi
fi

# 6. Generate JSON Report
TEMP_JSON=$(mktemp /tmp/bulk_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "input_exists": $INPUT_EXISTS,
    "input_process_configured": $INPUT_PROCESS_CONFIGURED,
    "feed_exists": $FEED_EXISTS,
    "feed_id": "${FEED_ID:-0}",
    "feed_count": $FEED_COUNT,
    "feed_engine": "${FEED_ENGINE:-0}",
    "feed_interval": "${FEED_INTERVAL:-0}",
    "result_file_exists": $RESULT_FILE_EXISTS,
    "result_file_match": $RESULT_FILE_MATCH,
    "result_file_content": "${RESULT_FILE_CONTENT//\"/\\\"}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json