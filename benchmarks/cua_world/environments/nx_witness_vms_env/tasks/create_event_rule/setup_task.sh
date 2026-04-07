#!/bin/bash
set -e
echo "=== Setting up create_event_rule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up existing rules to ensure clean state
# ============================================================
echo "Cleaning up any existing 'Camera Offline Alert' rules..."
RULES_JSON=$(nx_api_get "/rest/v1/rules" 2>/dev/null || echo "[]")

# Extract IDs of rules with our specific comment
IDS_TO_DELETE=$(echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    for r in rules:
        if r.get('comment') == 'Camera Offline Alert':
            print(r.get('id'))
except:
    pass
")

for rule_id in $IDS_TO_DELETE; do
    echo "Deleting pre-existing rule: $rule_id"
    nx_api_delete "/rest/v1/rules/${rule_id}"
done

# ============================================================
# 2. Record initial state
# ============================================================
echo "Recording initial rules state..."
nx_api_get "/rest/v1/rules" > /tmp/initial_rules.json
INITIAL_COUNT=$(python3 -c "import json; print(len(json.load(open('/tmp/initial_rules.json'))))" 2>/dev/null || echo "0")
echo "Initial rule count: $INITIAL_COUNT"

# ============================================================
# 3. Launch Desktop Client
# ============================================================
# The task recommends Desktop Client for Event Rules
echo "Launching Nx Witness Desktop Client..."

# Kill any existing instances
pkill -f "nxwitness" 2>/dev/null || true
pkill -f "applauncher" 2>/dev/null || true
sleep 2

# Find launcher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    # Start client
    DISPLAY=:1 "$APPLAUNCHER" > /dev/null 2>&1 &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window appeared"
            break
        fi
        sleep 1
    done
    
    # Maximize
    sleep 2
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
    
    # Attempt to handle First Run / Login dialogs if they appear is tricky without VLM
    # But usually the client remembers last state or shows the "Connect to Server" tile.
    # The setup_nx_witness.sh installs the client but doesn't configure client-side state.
    # We rely on the agent to click "Connect" or login.
else
    echo "WARNING: Desktop client not found. Agent must use API."
fi

# ============================================================
# 4. Take initial screenshot
# ============================================================
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="