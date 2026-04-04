#!/bin/bash
echo "=== Exporting generate_daily_usage_report result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/daily_usage_report.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Calculate Ground Truth
# We do this here inside the container where we have direct API access.
# -----------------------------------------------------------------------
cat > /tmp/calculate_ground_truth.py << 'PYTHON_EOF'
import sys
import json
import urllib.request
import urllib.parse
import datetime
import time

apikey = sys.argv[1]
base_url = "http://localhost"
feed_name = "use"

def api_call(endpoint, params):
    params['apikey'] = apikey
    query = urllib.parse.urlencode(params)
    url = f"{base_url}/{endpoint}?{query}"
    try:
        with urllib.request.urlopen(url) as response:
            return json.loads(response.read())
    except Exception as e:
        return None

# Find feed ID
feeds = api_call("feed/list.json", {})
feed_id = None
for f in feeds:
    if f['name'] == feed_name:
        feed_id = f['id']
        break

if not feed_id:
    print(json.dumps({"error": "Feed not found"}))
    sys.exit(0)

# Calculate expected date range (last 7 COMPLETE UTC days)
# If today is 2023-10-10, we want 2023-10-03 to 2023-10-09
today = datetime.datetime.now(datetime.timezone.utc).date()
ground_truth = []

for i in range(7, 0, -1):
    target_date = today - datetime.timedelta(days=i)
    
    # Start of day UTC
    ts_start = int(datetime.datetime(target_date.year, target_date.month, target_date.day, 0, 0, 0, tzinfo=datetime.timezone.utc).timestamp())
    # End of day UTC
    ts_end = ts_start + 86400
    
    # Get data: we use interval=3600 (1 hour) for rough check, or matches the generation interval
    # Better: fetch "dm" (daily mode) or manual integration
    # Let's manual integrate with decent resolution (e.g., 300s matches generation)
    interval = 300
    
    data = api_call("feed/data.json", {
        "id": feed_id,
        "start": ts_start * 1000,
        "end": ts_end * 1000,
        "interval": interval
    })
    
    if not data or not isinstance(data, list):
        kwh = 0
    else:
        # data format: [[time_ms, value], ...]
        total_power = 0
        count = 0
        for point in data:
            if point[1] is not None:
                total_power += point[1]
                count += 1
        
        # Simple integration: Average Power * 24h
        # If count is low (missing data), this might be inaccurate, but valid for generated data
        if count > 0:
            avg_power_watts = total_power / count
            kwh = (avg_power_watts * 24) / 1000
        else:
            kwh = 0
            
    ground_truth.append({
        "date": target_date.isoformat(),
        "kwh": round(kwh, 4)  # High precision for comparison
    })

print(json.dumps(ground_truth))
PYTHON_EOF

# Run ground truth calculation
APIKEY_READ=$(get_apikey_read)
GROUND_TRUTH_JSON=$(python3 /tmp/calculate_ground_truth.py "$APIKEY_READ")

# Check agent output
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
AGENT_CONTENT="[]"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content if it's valid JSON
    if jq -e . "$OUTPUT_PATH" >/dev/null 2>&1; then
        AGENT_CONTENT=$(cat "$OUTPUT_PATH")
    else
        AGENT_CONTENT="null" # Invalid JSON
    fi
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "agent_content": $AGENT_CONTENT,
    "ground_truth": $GROUND_TRUTH_JSON
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="