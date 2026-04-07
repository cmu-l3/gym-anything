#!/bin/bash
# Setup for create_monitoring_user task
# Ensures NextGen Connect is running, cleans up previous state, and records initial metrics

echo "=== Setting up create_monitoring_user task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for NextGen Connect API to be ready
echo "Waiting for NextGen Connect API..."
if ! wait_for_api 120; then
    echo "WARNING: API did not respond in time, continuing anyway..."
fi

# ==============================================================================
# CLEAN STATE: Remove the user if it already exists from a previous run
# ==============================================================================
echo "Checking for existing 'monitor_analyst' user..."
EXISTING_USER_ID=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/users" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    users = data if isinstance(data, list) else data.get('list', {}).get('user', [])
    if not isinstance(users, list): users = [users]
    for u in users:
        if u.get('username') == 'monitor_analyst':
            print(u.get('id', ''))
            break
except: pass" 2>/dev/null)

if [ -n "$EXISTING_USER_ID" ]; then
    echo "Removing pre-existing user (ID: $EXISTING_USER_ID)..."
    curl -sk -X DELETE -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/users/${EXISTING_USER_ID}" 2>/dev/null
    sleep 2
else
    echo "No pre-existing user found."
fi

# ==============================================================================
# RECORD INITIAL STATE
# ==============================================================================
# Record initial user count via API
INITIAL_USER_COUNT=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/users" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list): print(len(data))
    elif isinstance(data, dict) and 'list' in data:
        u = data['list'].get('user', [])
        print(len(u) if isinstance(u, list) else 1)
    else: print(1) # Likely just admin
except: print(1)" 2>/dev/null)

echo "${INITIAL_USER_COUNT:-1}" > /tmp/initial_user_count.txt
echo "Initial user count: ${INITIAL_USER_COUNT:-1}"

# ==============================================================================
# PREPARE UI
# ==============================================================================
# Ensure Firefox is running and showing the landing page
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="