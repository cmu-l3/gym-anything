#!/bin/bash
# setup_task.sh — Prepare the update_feed_tags task
source /workspace/scripts/task_utils.sh

echo "=== Setting up update_feed_tags task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms services
wait_for_emoncms

APIKEY=$(get_apikey_write)
if [ -z "$APIKEY" ]; then
    echo "ERROR: Could not retrieve admin API key"
    exit 1
fi
echo "Using API key: ${APIKEY}"

# -----------------------------------------------------------------------
# Helper: create or reset a feed with a specific tag
# -----------------------------------------------------------------------
ensure_feed() {
    local name="$1"
    local tag="$2"
    local unit="$3"

    # Check if feed already exists
    local feed_id
    feed_id=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    feeds = json.load(sys.stdin)
    found = next((f for f in feeds if f['name'] == '${name}'), None)
    if found: print(found['id'])
except: pass
" 2>/dev/null)

    if [ -n "$feed_id" ] && [ "$feed_id" != "" ]; then
        echo "Feed '${name}' exists (ID=${feed_id}), resetting tag to '${tag}'"
        # Use feed/set.json to reset the tag
        # Note: fields must be a JSON string
        local fields_json="{\"tag\":\"${tag}\"}"
        # URL encode the fields JSON
        local encoded_fields
        encoded_fields=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${fields_json}'))")
        
        curl -s "${EMONCMS_URL}/feed/set.json?apikey=${APIKEY}&id=${feed_id}&fields=${encoded_fields}" > /dev/null 2>&1
    else
        echo "Creating feed '${name}' with tag '${tag}'"
        # Create feed with specific tag
        local options='%7B%22interval%22%3A10%7D' # {"interval":10}
        local result
        result=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=${name}&tag=${tag}&datatype=1&engine=5&options=${options}&unit=${unit}" 2>/dev/null)
        
        # Extract feed ID for confirmation
        feed_id=$(echo "$result" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r.get('feedid',''))" 2>/dev/null)
        echo "  Created ID=${feed_id}"
    fi
}

# -----------------------------------------------------------------------
# Create/reset the four task feeds with their INITIAL (old) tags
# -----------------------------------------------------------------------
ensure_feed "North_Wing_Power"     "electricity"  "W"
ensure_feed "North_Wing_Temp"      "environment"  "°C"
ensure_feed "Rooftop_Solar"        "renewables"   "W"
ensure_feed "Parking_EV_Charger"   "transport"    "W"

sleep 2

# -----------------------------------------------------------------------
# Record initial state for anti-gaming verification
# -----------------------------------------------------------------------
echo "=== Recording initial feed tags ==="
curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" > /tmp/feed_list_initial.raw

python3 << 'PYEOF'
import json

target_names = ["North_Wing_Power", "North_Wing_Temp", "Rooftop_Solar", "Parking_EV_Charger"]

try:
    with open("/tmp/feed_list_initial.raw") as f:
        feeds = json.load(f)
except Exception as e:
    feeds = []
    print(f"Error loading initial list: {e}")

initial = {}
for f in feeds:
    if f["name"] in target_names:
        initial[f["name"]] = {"id": f["id"], "tag": f["tag"]}
        print(f"  Recorded initial state: {f['name']} -> {f['tag']}")

with open("/tmp/initial_feed_tags.json", "w") as fh:
    json.dump(initial, fh, indent=2)
PYEOF

# -----------------------------------------------------------------------
# Launch Firefox to the Feeds page (logged in)
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost/feed/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== update_feed_tags setup complete ==="