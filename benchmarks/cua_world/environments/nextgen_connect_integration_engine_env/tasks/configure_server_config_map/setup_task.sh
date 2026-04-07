#!/bin/bash
set -e
echo "=== Setting up Configuration Map task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for NextGen Connect API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120 || {
    echo "WARNING: API not ready after 120s, continuing anyway..."
}

# Clear any existing configuration map to ensure clean state
# We post an empty map
echo "Resetting configuration map..."
curl -sk -X PUT -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Content-Type: application/xml" \
    -d '<map/>' \
    "https://localhost:8443/api/server/configurationMap" 2>/dev/null

# Record initial state for comparison
INITIAL_MAP=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/server/configurationMap" 2>/dev/null)
echo "$INITIAL_MAP" > /tmp/initial_config_map.xml

# Ensure Firefox is open and focused on landing page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -r "firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="