#!/bin/bash
# Export script for audit_feed_storage task
set -u

echo "=== Exporting audit_feed_storage results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_FILE="/home/ga/feed_storage_audit.csv"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy agent's CSV to temp for secure export
    cp "$OUTPUT_FILE" /tmp/agent_audit.csv
else
    # Create empty file to prevent errors
    touch /tmp/agent_audit.csv
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate Ground Truth Data
# We run a python script to fetch the actual state of all feeds using the API/DB
# This ensures the verifier compares against the REAL current state.
echo "Generating ground truth data..."

cat > /tmp/generate_ground_truth.py << 'PYTHON_EOF'
import json
import urllib.request
import sys
import os

# Get API Key from environment or file
try:
    with open('/home/ga/emoncms_apikeys.sh', 'r') as f:
        content = f.read()
        for line in content.splitlines():
            if 'EMONCMS_APIKEY_READ' in line:
                apikey = line.split('=')[1].strip().strip('"')
                break
except:
    apikey = ""

if not apikey:
    print(json.dumps({"error": "No API key found"}))
    sys.exit(0)

base_url = "http://localhost"

def get_json(endpoint):
    try:
        url = f"{base_url}/{endpoint}?apikey={apikey}"
        with urllib.request.urlopen(url) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        return []

# Get list of all feeds
feeds = get_json("feed/list.json")
ground_truth = []

for feed in feeds:
    feed_id = feed.get('id')
    # Fetch detailed metadata (storage size, etc)
    # Some versions use feed/aget.json, others include it in list or use getmeta
    # We'll try to use the values from list.json if available, or fetch meta if needed.
    # feed/list.json usually returns 'size', 'npoints', 'start_time', 'interval' in recent versions.
    
    # Explicitly ensure we have the metrics. If list.json lacks them, we might need individual calls,
    # but for Emoncms 11+ list.json is usually sufficient. 
    # Let's trust list.json but normalize keys.
    
    item = {
        "id": int(feed.get('id', 0)),
        "name": str(feed.get('name', '')),
        "tag": str(feed.get('tag', '')),
        "engine": int(feed.get('engine', 0)),
        "interval": int(feed.get('interval', 0)),
        "npoints": int(feed.get('npoints', 0)),
        "start_time": int(feed.get('start_time', 0)),
        "size": int(feed.get('size', 0))
    }
    ground_truth.append(item)

# Sort by ID for consistency
ground_truth.sort(key=lambda x: x['id'])

print(json.dumps(ground_truth))
PYTHON_EOF

# Run the ground truth generation
GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py)

# Assemble final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_feeds": $GROUND_TRUTH_JSON
}
EOF

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="