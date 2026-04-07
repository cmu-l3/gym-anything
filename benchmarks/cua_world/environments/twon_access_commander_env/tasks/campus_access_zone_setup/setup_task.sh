#!/bin/bash
set -e
echo "=== Setting up campus_access_zone_setup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Access Commander to be ready
wait_for_ac_demo
ac_login

# Ensure clean state: delete any existing zones with our target names
echo "Cleaning up any existing target zones..."
ZONES_JSON=$(ac_api GET "/zones" 2>/dev/null || echo "[]")

# If valid JSON was returned, parse and delete target zones
if echo "$ZONES_JSON" | jq -e . >/dev/null 2>&1; then
    for ZNAME in "Main Entrance Lobby" "Server Room A" "Executive Suite"; do
        # Extract IDs for any zone matching the target names
        ZIDS=$(echo "$ZONES_JSON" | jq -r --arg n "$ZNAME" '.[]? | select(.name==$n) | .id // empty' 2>/dev/null)
        for zid in $ZIDS; do
            if [ -n "$zid" ]; then
                ac_api DELETE "/zones/$zid" > /dev/null 2>&1 && echo "Deleted prior zone: $ZNAME (id=$zid)" || true
            fi
        done
    done
fi

# Ensure output directory exists and file is absent
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/zones_configured.txt

# Start Firefox pointing to the dashboard
launch_firefox_to "${AC_URL}/#/dashboard" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="