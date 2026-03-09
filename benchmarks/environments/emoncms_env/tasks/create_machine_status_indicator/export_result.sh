#!/bin/bash
# Export script for Create Machine Status Indicator task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Machine Status Task Results ==="

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Stop the simulation
if [ -f /tmp/sim_pid.txt ]; then
    kill $(cat /tmp/sim_pid.txt) 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 1. Check Dashboard Existence
# -----------------------------------------------------------------------
DASH_NAME="Factory Monitor"
DASH_DATA=$(db_query "SELECT id, content FROM dashboard WHERE name='$DASH_NAME' AND userid=1" 2>/dev/null)
DASH_EXISTS="false"
DASH_CONTENT="{}"

if [ -n "$DASH_DATA" ]; then
    DASH_EXISTS="true"
    # Extract content JSON (everything after the ID and tab)
    # MySQL output with -N is tab separated. Content is the 2nd column.
    # Note: Content might contain tabs, so we act carefully.
    # Simpler approach: fetch just content
    DASH_CONTENT=$(db_query "SELECT content FROM dashboard WHERE name='$DASH_NAME' AND userid=1" 2>/dev/null)
fi

# -----------------------------------------------------------------------
# 2. Check Feed Existence and Data
# -----------------------------------------------------------------------
FEED_NAME="press_running"
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='$FEED_NAME' AND userid=1" 2>/dev/null | head -1)
FEED_EXISTS="false"
FEED_VALUES="[]"

if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    APIKEY=$(get_apikey_read)
    # Fetch last 60 seconds of data (10s interval = ~6 points)
    # We want to see if we have 0s and 1s.
    # API: feed/data.json?id=ID&start=START&end=END&interval=10
    
    # Use python to fetch and format because bash JSON handling is painful
    FEED_VALUES=$(python3 -c "
import requests, json, time
try:
    end = int(time.time())
    start = end - 120
    url = '${EMONCMS_URL}/feed/data.json?apikey=${APIKEY}&id=${FEED_ID}&start='+str(start)+'&end='+str(end)+'&interval=10'
    r = requests.get(url)
    data = r.json()
    # data format: [[time, val], [time, val]...]
    # Extract just values, filter nulls
    vals = [x[1] for x in data if x[1] is not None]
    print(json.dumps(vals))
except:
    print('[]')
")
fi

# -----------------------------------------------------------------------
# 3. Check Input Processing Config (Optional but helpful)
# -----------------------------------------------------------------------
INPUT_PROCESS=$(db_query "SELECT processList FROM input WHERE name='press_power' AND userid=1" 2>/dev/null)

# -----------------------------------------------------------------------
# 4. Create Result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dashboard_exists": $DASH_EXISTS,
    "dashboard_content": $(echo "$DASH_CONTENT" | jq -R .),
    "feed_exists": $FEED_EXISTS,
    "feed_values": $FEED_VALUES,
    "input_process_list": "$INPUT_PROCESS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json