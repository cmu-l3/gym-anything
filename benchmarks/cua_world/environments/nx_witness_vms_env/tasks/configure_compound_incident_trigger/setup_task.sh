#!/bin/bash
set -e
echo "=== Setting up configure_compound_incident_trigger task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Ensure clean state: Remove any existing rules with the target name
# ==============================================================================
echo "Cleaning up existing 'Report Incident' rules..."
TOKEN=$(get_nx_token)

# Get all rules
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Parse and delete existing rules matching our target caption
echo "$RULES_JSON" | python3 -c "
import sys, json, requests
token = '$TOKEN'
base_url = 'https://localhost:7001'
try:
    rules = json.load(sys.stdin)
    if not isinstance(rules, list): sys.exit(0)
    
    for rule in rules:
        # Check if caption matches 'Report Incident'
        # The API field might be 'caption' inside 'eventCondition' or similar depending on version, 
        # but for softwareTrigger it's usually in eventCondition params.
        # However, typically simple GET /eventRules returns flat objects.
        # We'll check generic properties.
        
        # In Nx Witness API, softwareTrigger conditions often store the name in 'caption' or parameters
        should_delete = False
        
        # Check event type
        if rule.get('eventType') == 'softwareTrigger':
            # Check condition params for the name
            params = rule.get('eventCondition', {}).get('params', {})
            # Sometimes params is a JSON string, sometimes an object
            if isinstance(params, str):
                try: params = json.loads(params)
                except: pass
            
            caption = params.get('caption', '')
            if 'Report Incident' in caption:
                should_delete = True
                
        if should_delete:
            print(f'Deleting rule {rule.get(\"id\")}')
            requests.delete(
                f'{base_url}/rest/v1/eventRules/{rule.get(\"id\")}',
                headers={'Authorization': f'Bearer {token}'},
                verify=False
            )
except Exception as e:
    print(f'Error cleaning rules: {e}', file=sys.stderr)
"

# ==============================================================================
# 2. Ensure Desktop Client is running and ready
# ==============================================================================
echo "Checking Nx Witness Desktop Client..."

# Kill any existing instances to ensure fresh login/state
pkill -f "applauncher" 2>/dev/null || true
pkill -f "nxwitness-client" 2>/dev/null || true
sleep 2

# Find launcher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Desktop Client..."
    # Launch in background
    DISPLAY=:1 "$APPLAUNCHER" > /dev/null 2>&1 &
    
    # Wait loop for window
    echo "Waiting for client window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window found."
            break
        fi
        sleep 1
    done
    
    sleep 5
    
    # Maximize window
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Handle potential first-run dialogs (Keyring, EULA) - standard for this env
    # (Coordinates are approximate based on 1920x1080 resolution)
    # Dismiss Keyring "Continue" (if it appears)
    DISPLAY=:1 xdotool mousemove 1060 678 click 1 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool mousemove 1060 628 click 1 2>/dev/null || true
    sleep 2
    # Dismiss EULA "I Agree"
    DISPLAY=:1 xdotool mousemove 1327 783 click 1 2>/dev/null || true
    sleep 2
    
    # Connect to local server (Click the tile if it's the welcome screen)
    # Usually the tile is in the middle. We can try to click or just assume 
    # the agent will handle the connection if it's at the welcome screen.
    # But for "Starting State", let's try to get it connected.
    # Press "Enter" often connects to the selected tile
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    
else
    echo "WARNING: Desktop client launcher not found. Agent may need to launch it manually."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="