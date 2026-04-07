#!/bin/bash
echo "=== Setting up Create Visit Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (creation time check)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state: Delete "Telemedicine" visit type if it exists
# We check via REST API and delete if found to ensure the agent actually creates it
echo "Checking for existing Telemedicine visit type..."
EXISTING_UUID=$(omrs_get "/visittype?q=Telemedicine&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null)

if [ -n "$EXISTING_UUID" ]; then
    echo "Removing existing Telemedicine visit type ($EXISTING_UUID)..."
    omrs_delete "/visittype/$EXISTING_UUID"
    echo "Purged."
else
    echo "No existing visit type found. Clean state confirmed."
fi

# 3. Record initial count of visit types
INITIAL_COUNT=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_visittype_count

# 4. Launch Firefox and log in
# We start at the home page, requiring the agent to find the Administration link
echo "Launching Firefox..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: Create Visit Type 'Telemedicine'"