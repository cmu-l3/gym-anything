#!/bin/bash
echo "=== Exporting Compute Heat Pump COP Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
REPORT_PATH="/home/ga/cop_report.txt"
GROUND_TRUTH_PATH="/var/lib/emoncms/cop_ground_truth.json"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    # Parse report lines into JSON structure for verifier
    R_ID=$(sed -n '1p' "$REPORT_PATH" | tr -d ' \r\n')
    R_COUNT=$(sed -n '2p' "$REPORT_PATH" | tr -d ' \r\n')
    R_AVG=$(sed -n '3p' "$REPORT_PATH" | tr -d ' \r\n')
    R_MAX=$(sed -n '4p' "$REPORT_PATH" | tr -d ' \r\n')
    R_MIN=$(sed -n '5p' "$REPORT_PATH" | tr -d ' \r\n')
else
    R_ID="0"
    R_COUNT="0"
    R_AVG="0"
    R_MAX="0"
    R_MIN="0"
fi

# 2. Check COP Feed in Database
# Agent should have created 'heatpump_cop'
COP_FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='heatpump_cop' AND tag='heatpump'" 2>/dev/null | head -1)
FEED_EXISTS="false"
DB_ROW_COUNT="0"
DB_AVG="0"

if [ -n "$COP_FEED_ID" ]; then
    FEED_EXISTS="true"
    
    # Verify feed type (PHPFina = 5)
    FEED_ENGINE=$(db_query "SELECT engine FROM feeds WHERE id=$COP_FEED_ID" 2>/dev/null | head -1)
    
    # Calculate stats from actual data in the feed
    # We use a python script to query the feed data API to be accurate
    cat > /tmp/calc_feed_stats.py << PYTHON_EOF
import urllib.request
import json
import sys

try:
    apikey = "$(get_apikey_read)"
    feed_id = "$COP_FEED_ID"
    # Get feed meta to find start time
    meta_url = f"http://localhost/feed/get.json?apikey={apikey}&id={feed_id}"
    with urllib.request.urlopen(meta_url) as r:
        meta = json.loads(r.read().decode())
    
    start = meta.get('start_time', 0)
    end = start + (24*3600*2) # Look ahead plenty
    
    # Get data
    data_url = f"http://localhost/feed/data.json?apikey={apikey}&id={feed_id}&start={start}&end={end}&interval=60"
    with urllib.request.urlopen(data_url) as r:
        data = json.loads(r.read().decode())
    
    # Filter nulls
    values = [float(p[1]) for p in data if p[1] is not None]
    
    if not values:
        print(json.dumps({"count": 0}))
    else:
        print(json.dumps({
            "count": len(values),
            "avg": sum(values) / len(values),
            "max": max(values),
            "min": min(values),
            "sample_values": values[:5]
        }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYTHON_EOF

    FEED_STATS_JSON=$(python3 /tmp/calc_feed_stats.py)
else
    FEED_STATS_JSON='{"count": 0}'
    FEED_ENGINE="0"
fi

# 3. Load Ground Truth
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH_JSON=$(cat "$GROUND_TRUTH_PATH")
else
    GROUND_TRUTH_JSON="{}"
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_data": {
        "id": "$R_ID",
        "count": "$R_COUNT",
        "avg": "$R_AVG",
        "max": "$R_MAX",
        "min": "$R_MIN"
    },
    "feed_exists": $FEED_EXISTS,
    "feed_id": "${COP_FEED_ID:-0}",
    "feed_engine": "${FEED_ENGINE:-0}",
    "feed_stats": $FEED_STATS_JSON,
    "ground_truth": $GROUND_TRUTH_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="