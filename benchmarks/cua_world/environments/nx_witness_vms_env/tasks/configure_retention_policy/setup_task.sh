#!/bin/bash
set -e
echo "=== Setting up task: configure_retention_policy ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness server is running
echo "Checking Nx Witness server status..."
systemctl start networkoptix-mediaserver 2>/dev/null || true
sleep 5

# Obtain auth token for setup
TOKEN=$(refresh_nx_token)
echo "Auth token obtained."

# Record initial device states for anti-gaming verification
echo "=== Recording initial device states ==="
DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# Save initial state to file
echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    initial_state = {}
    for d in devices:
        did = d.get('id', '')
        if did:
            initial_state[did] = {
                'name': d.get('name', ''),
                'minArchivePeriodS': d.get('minArchivePeriodS', -1),
                'maxArchivePeriodS': d.get('maxArchivePeriodS', -1)
            }
    with open('/tmp/initial_retention_state.json', 'w') as f:
        json.dump(initial_state, f, indent=2)
    print(f'Recorded initial state for {len(initial_state)} devices')
except Exception as e:
    print(f'Error recording initial state: {e}')
    with open('/tmp/initial_retention_state.json', 'w') as f:
        json.dump({}, f)
" 2>/dev/null

# Clean up previous report file
rm -f /home/ga/retention_policy_report.json

# Verify camera count (should be 5 based on env setup)
CAMERA_COUNT=$(count_cameras)
echo "Cameras available: $CAMERA_COUNT"

# Ensure Firefox is closed (start fresh if they use the GUI, though this is an API task)
pkill -f firefox 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="