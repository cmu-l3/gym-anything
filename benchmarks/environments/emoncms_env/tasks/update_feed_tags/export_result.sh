#!/bin/bash
# export_result.sh — Verify the update_feed_tags task
source /workspace/scripts/task_utils.sh

echo "=== Exporting update_feed_tags results ==="

APIKEY=$(get_apikey_write)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Get current feed state from BOTH API and database for robustness
# -----------------------------------------------------------------------
curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" 2>/dev/null > /tmp/feed_list_final.json

# Also query directly from MySQL for cross-validation
# Output format: name <tab> tag
db_query "SELECT name, tag FROM feeds WHERE name IN ('North_Wing_Power','North_Wing_Temp','Rooftop_Solar','Parking_EV_Charger')" \
    > /tmp/feed_tags_db.txt 2>/dev/null

# -----------------------------------------------------------------------
# Process results into a single JSON file
# -----------------------------------------------------------------------
python3 << 'PYEOF'
import json
import os
import time

task_start = 0
try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = int(f.read().strip())
except:
    pass

# Load initial state
initial_state = {}
try:
    with open("/tmp/initial_feed_tags.json") as f:
        initial_state = json.load(f)
except:
    pass

# Load final API state
final_api_state = {}
try:
    with open("/tmp/feed_list_final.json") as f:
        feeds = json.load(f)
        for feed in feeds:
            final_api_state[feed['name']] = feed.get('tag', '')
except Exception as e:
    print(f"Error loading API results: {e}")

# Load final DB state
final_db_state = {}
try:
    with open("/tmp/feed_tags_db.txt") as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                final_db_state[parts[0]] = parts[1]
except Exception as e:
    print(f"Error loading DB results: {e}")

# Check for changes (anti-gaming)
changes_detected = False
feed_results = {}

targets = ["North_Wing_Power", "North_Wing_Temp", "Rooftop_Solar", "Parking_EV_Charger"]

for name in targets:
    init_tag = initial_state.get(name, {}).get("tag", "")
    
    # Prefer API state, fallback to DB
    curr_tag = final_api_state.get(name, final_db_state.get(name, "NOT_FOUND"))
    
    # Check if changed
    if init_tag != "" and curr_tag != "NOT_FOUND" and init_tag != curr_tag:
        changes_detected = True
        
    feed_results[name] = {
        "initial": init_tag,
        "current": curr_tag,
        "source": "api" if name in final_api_state else "db"
    }

# Construct result object
result = {
    "task_start": task_start,
    "task_end": int(time.time()),
    "feeds": feed_results,
    "changes_detected": changes_detected,
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

# Write to temp file then move
with open("/tmp/result_temp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="