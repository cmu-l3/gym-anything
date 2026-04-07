#!/bin/bash
set -e
echo "=== Setting up configure_emergency_overlay task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Refresh auth token for setup operations
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# CLEANUP: Remove any existing "Lockdown" rules to ensure clean state
# ==============================================================================
echo "Checking for existing 'Lockdown' rules..."
EXISTING_RULES=$(nx_api_get "/rest/v1/eventRules")

# Parse and delete any rules containing "Lockdown" text or trigger name
echo "$EXISTING_RULES" | python3 -c "
import sys, json, subprocess
try:
    rules = json.load(sys.stdin)
    for rule in rules:
        # Check trigger name (often in comments or description depending on version) or action params
        text_check = str(rule).lower()
        if 'lockdown' in text_check:
            rule_id = rule.get('id')
            print(f'Deleting existing rule: {rule_id}')
            subprocess.call(['bash', '/workspace/scripts/task_utils.sh', 'nx_api_delete', f'/rest/v1/eventRules/{rule_id}'])
except Exception as e:
    print(f'Error cleaning rules: {e}')
" 2>/dev/null || true

# Record initial rule count
INITIAL_COUNT=$(nx_api_get "/rest/v1/eventRules" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_rule_count.txt
echo "Initial rule count: $INITIAL_COUNT"

# ==============================================================================
# LAUNCH DESKTOP CLIENT
# ==============================================================================
# Kill any existing instances
pkill -f "applauncher" 2>/dev/null || true
pkill -f "Nx Witness" 2>/dev/null || true
sleep 2

# Pre-configure keyring to avoid dialogs
mkdir -p /home/ga/.local/share/keyrings 2>/dev/null || true

# Find applauncher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Desktop Client..."
    # Launch as ga user
    su - ga -c "DISPLAY=:1 \"$APPLAUNCHER\"" &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Nx Witness window detected"
            break
        fi
        sleep 1
    done
    
    # Give it time to initialize
    sleep 10
    
    # Attempt to handle "Welcome" / "Connect" screens via clicks if necessary
    # Note: The agent is expected to click the server tile, but we can try to help focus
    
    # Maximize window
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
else
    echo "WARNING: Desktop client not found, falling back to Firefox"
    ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="