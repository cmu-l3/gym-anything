#!/bin/bash
set -e
echo "=== Setting up create_gate_control_trigger task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the technical manual
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/gate_controller_manual.txt << EOF
IronSide Access Controller Model X5
API Integration Guide

Control Endpoint: http://192.168.1.200/api/v1/controls/relay1/activate
Method: POST
Authentication: Basic Auth
Username: gate_admin
Password: SecureGatePassword!
Payload: None required
EOF
chown ga:ga /home/ga/Documents/gate_controller_manual.txt
echo "Created gate controller manual."

# 2. Ensure Nx Witness Server is ready and we have a token
refresh_nx_token > /dev/null 2>&1 || true

# 3. Clean up any existing rules that might match (Idempotency)
echo "Cleaning up existing 'OPEN GATE' rules..."
RULES_JSON=$(nx_api_get "/rest/v1/rules")
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    for rule in rules:
        # Check if it looks like our target rule (Soft Trigger + OPEN GATE)
        # Note: In API, Soft Trigger name is often in eventCondition or comments depending on version, 
        # but usually encoded in the condition for softwareTriggerEvent.
        if rule.get('eventType') == 'softwareTriggerEvent':
            print(rule.get('id'))
except:
    pass
" | while read rule_id; do
    if [ -n "$rule_id" ]; then
        echo "Deleting existing soft trigger rule: $rule_id"
        nx_api_delete "/rest/v1/rules/$rule_id"
    fi
done

# 4. Record initial rule count
INITIAL_COUNT=$(nx_api_get "/rest/v1/rules" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_rule_count.txt

# 5. Launch Nx Witness Desktop Client
# Soft Triggers are best configured/visualized in the Desktop Client.
# While they can be done via API, the agent is likely to use the GUI.

# Kill any existing client
pkill -f "Nx Witness" || true
sleep 2

# Launch Client
echo "Launching Nx Witness Desktop Client..."
# Locate applauncher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
if [ -n "$APPLAUNCHER" ]; then
    # Run as ga user
    su - ga -c "DISPLAY=:1 $APPLAUNCHER &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Nx Witness window detected."
            break
        fi
        sleep 1
    done
    
    # Maximize
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Note: We rely on the environment's auto-login or the agent to log in. 
    # If the client starts at the 'Connect' screen, the agent must click the tile.
    # The environment description implies a setup script handles some of this, 
    # but we ensure the window is there.
else
    echo "WARNING: Desktop client not found, agent may need to use Web Admin."
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="