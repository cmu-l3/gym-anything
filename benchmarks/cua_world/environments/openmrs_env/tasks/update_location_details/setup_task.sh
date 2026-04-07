#!/bin/bash
# Setup: update_location_details task
# Ensures 'Laboratory' location exists with a generic description so the agent can update it.

set -e
echo "=== Setting up update_location_details task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# ── 1. Ensure 'Laboratory' Location Exists & Reset State ─────────────────────
echo "Configuring Laboratory location..."

# Check if location exists
LOC_UUID=$(omrs_get "/location?q=Laboratory&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -z "$LOC_UUID" ]; then
    echo "Creating 'Laboratory' location..."
    # Create if missing
    omrs_post "/location" '{
        "name": "Laboratory",
        "description": "Standard Lab - To be updated",
        "tags": []
    }' > /dev/null
else
    echo "Resetting 'Laboratory' description..."
    # Reset description to ensure the agent has to change it
    # We use a generic description that is clearly different from the target
    omrs_post "/location/$LOC_UUID" '{
        "description": "Standard Lab - To be updated"
    }' > /dev/null
fi

# ── 2. Browser Setup ─────────────────────────────────────────────────────────
# Open Firefox on the Home Page. We don't take them directly to the admin page
# because part of the task is navigating the admin menu.
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="