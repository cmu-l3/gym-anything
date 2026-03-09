#!/bin/bash
# Export results for calculate_solar_fraction task

source /workspace/scripts/task_utils.sh

echo "=== Exporting calculate_solar_fraction results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic file checks
REPORT_PATH="/home/ga/solar_fraction_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 3. Calculate Ground Truth values
# Load feed IDs saved during setup
source /tmp/task_feed_ids.sh 2>/dev/null || true

GT_HOUSE_TOTAL="0"
GT_SOLAR_TOTAL="0"
GT_FRACTION="0"

if [ -n "$HOUSE_KWH_ID" ] && [ -n "$SOLAR_KWH_ID" ] && [ -n "$APIKEY" ]; then
    # Use python to fetch min/max values from API and compute totals
    # Emoncms API: /feed/data.json?id=X&start=START&end=END&interval=INTERVAL
    # To get min/max of a cumulative feed, we look at the endpoints of the data range.
    
    python3 << PYEOF > /tmp/gt_values.json
import urllib.request
import json
import sys

apikey = "$APIKEY"
base_url = "http://localhost"
house_id = "$HOUSE_KWH_ID"
solar_id = "$SOLAR_KWH_ID"

def get_feed_bounds(feed_id):
    try:
        # Get meta data to find start time
        meta_url = f"{base_url}/feed/aget.json?id={feed_id}&apikey={apikey}"
        with urllib.request.urlopen(meta_url) as r:
            meta = json.loads(r.read())
        
        start_time = int(meta.get('start_time', 0)) * 1000
        # Use a future end time
        end_time = 9999999999000
        
        # We need the first non-null value and the last non-null value
        # This is tricky with strictly intervals. 
        # Strategy: Fetch daily data to cover range, then pick first/last.
        # Interval: 1 day = 86400s.
        
        data_url = f"{base_url}/feed/data.json?id={feed_id}&start={start_time}&end={end_time}&interval=86400&apikey={apikey}"
        with urllib.request.urlopen(data_url) as r:
            data = json.loads(r.read())
            
        # Filter nulls
        valid_points = [p for p in data if p[1] is not None]
        
        if not valid_points:
            return 0.0
            
        first_val = valid_points[0][1]
        last_val = valid_points[-1][1]
        
        return last_val - first_val
    except Exception as e:
        sys.stderr.write(f"Error calculating feed {feed_id}: {e}\n")
        return 0.0

house_total = get_feed_bounds(house_id)
solar_total = get_feed_bounds(solar_id)
fraction = (solar_total / house_total * 100) if house_total > 0 else 0

print(json.dumps({
    "gt_house_total": house_total,
    "gt_solar_total": solar_total,
    "gt_fraction": fraction
}))
PYEOF

    # Load the python output variables
    if [ -f /tmp/gt_values.json ]; then
        GT_HOUSE_TOTAL=$(jq -r '.gt_house_total' /tmp/gt_values.json)
        GT_SOLAR_TOTAL=$(jq -r '.gt_solar_total' /tmp/gt_values.json)
        GT_FRACTION=$(jq -r '.gt_fraction' /tmp/gt_values.json)
    fi
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "ground_truth": {
        "house_total": $GT_HOUSE_TOTAL,
        "solar_total": $GT_SOLAR_TOTAL,
        "fraction": $GT_FRACTION
    }
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="