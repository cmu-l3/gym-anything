#!/bin/bash
echo "=== Setting up Channel Watchdog Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure NextGen Connect is running and API is ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120

# Authenticate/Clear existing channels to ensure clean slate
echo "Clearing existing channels..."
# Get all channel IDs
CHANNEL_IDS=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" https://localhost:8443/api/channels | python3 -c "import sys, json; print(' '.join([c['id'] for c in json.load(sys.stdin).get('list', [])]))" 2>/dev/null)

for id in $CHANNEL_IDS; do
    echo "Deleting channel $id..."
    curl -sk -u admin:admin -X DELETE -H "X-Requested-With: OpenAPI" "https://localhost:8443/api/channels/$id" > /dev/null
done

# Setup log file with correct permissions (so agent doesn't hit permission errors)
touch /home/ga/watchdog.log
chown ga:ga /home/ga/watchdog.log
chmod 666 /home/ga/watchdog.log

# Ensure Firefox is open to the dashboard
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 10
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="