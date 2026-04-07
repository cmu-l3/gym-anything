#!/bin/bash
# Setup: configure_location_tags task
# Ensures 'Isolation Ward' exists and has NO tags initially.

echo "=== Setting up configure_location_tags task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Ensure 'Isolation Ward' exists
echo "Checking for 'Isolation Ward'..."
LOC_UUID=$(omrs_get "/location?q=Isolation+Ward&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -z "$LOC_UUID" ]; then
    echo "Creating 'Isolation Ward'..."
    # Create it as a generic location
    LOC_UUID=$(omrs_post "/location" '{"name":"Isolation Ward","description":"Unit for infectious diseases"}' | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
fi

echo "Target Location UUID: $LOC_UUID"
if [ -z "$LOC_UUID" ]; then
    echo "ERROR: Failed to create/find target location."
    exit 1
fi

# 2. CLEAR any existing tags to ensure clean starting state
echo "Clearing existing tags from Isolation Ward..."
# Sending empty tags list
omrs_post "/location/$LOC_UUID" '{"tags":[]}' > /dev/null

# 3. Verify initial state (should have 0 tags)
TAG_COUNT=$(omrs_get "/location/$LOC_UUID?v=full" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('tags',[])))" 2>/dev/null || echo "0")
echo "Initial tag count: $TAG_COUNT"
echo "$TAG_COUNT" > /tmp/initial_tag_count

# 4. Open Firefox to the System Administration or Home page
# The 'Manage Locations' link is usually in the System Admin app or legacy admin
# We'll start them at the home page (SPA) which links to the Apps
HOME_URL="http://localhost/openmrs/spa/home"
ensure_openmrs_logged_in "$HOME_URL"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== configure_location_tags task setup complete ==="
echo ""
echo "TASK: Configure 'Isolation Ward'"
echo "  Goal: Add 'Admission Location' and 'Transfer Location' tags"
echo "  Target: Isolation Ward (UUID: $LOC_UUID)"
echo ""
echo "Login: admin / Admin123"