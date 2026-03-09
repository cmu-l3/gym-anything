#!/bin/bash
echo "=== Exporting monitor_carbon_footprint result ==="

source /workspace/scripts/task_utils.sh

# Stop data generator
if [ -f /tmp/data_gen_pid.txt ]; then
    kill $(cat /tmp/data_gen_pid.txt) 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Inspect Input Processing
# We need to see the processList for 'facility_main_power'
# processList format in DB: "1:12,2:0.001,..." (processID:arg)
INPUT_JSON=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT name, processList FROM input WHERE name='facility_main_power' AND nodeid='main_meter'" 2>/dev/null)
INPUT_NAME=$(echo "$INPUT_JSON" | cut -f1)
PROCESS_LIST=$(echo "$INPUT_JSON" | cut -f2)

echo "Found Input: $INPUT_NAME"
echo "Process List: $PROCESS_LIST"

# 2. Inspect Created Feed
# Check if 'current_carbon_intensity' exists and has data
FEED_QUERY=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT id, name, tag, engine, value FROM feeds WHERE name='current_carbon_intensity'" 2>/dev/null)
FEED_ID=$(echo "$FEED_QUERY" | awk '{print $1}')
FEED_NAME=$(echo "$FEED_QUERY" | awk '{print $2}')
FEED_TAG=$(echo "$FEED_QUERY" | awk '{print $3}')
FEED_LAST_VALUE=$(echo "$FEED_QUERY" | awk '{print $5}')

FEED_EXISTS="false"
FEED_HAS_DATA="false"
if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    # Check if data table has rows (engine 5 = PHPFina)
    # Usually we can just check if last value is not null/zero or use API
    if [ "$FEED_LAST_VALUE" != "NULL" ]; then
        FEED_HAS_DATA="true"
    fi
fi

# 3. Inspect Dashboard
# Check if dashboard exists and parse its content for widgets
DASH_QUERY=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT id, name, content FROM dashboard WHERE name='Sustainability_Display'" 2>/dev/null)
DASH_ID=$(echo "$DASH_QUERY" | awk '{print $1}')
DASH_NAME=$(echo "$DASH_QUERY" | awk '{print $2}')
# Content is likely a JSON blob in the 3rd column, might contain spaces, so use python to fetch reliably
DASH_CONTENT=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT content FROM dashboard WHERE name='Sustainability_Display'" 2>/dev/null)

DASH_EXISTS="false"
if [ -n "$DASH_ID" ]; then
    DASH_EXISTS="true"
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "input_found": $(if [ -n "$INPUT_NAME" ]; then echo "true"; else echo "false"; fi),
    "process_list": "$PROCESS_LIST",
    "feed_exists": $FEED_EXISTS,
    "feed_name": "$FEED_NAME",
    "feed_tag": "$FEED_TAG",
    "feed_has_data": $FEED_HAS_DATA,
    "feed_last_value": "${FEED_LAST_VALUE:-0}",
    "dashboard_exists": $DASH_EXISTS,
    "dashboard_name": "$DASH_NAME",
    "dashboard_content": $(if [ -n "$DASH_CONTENT" ]; then echo "$DASH_CONTENT"; else echo "{}"; fi),
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="