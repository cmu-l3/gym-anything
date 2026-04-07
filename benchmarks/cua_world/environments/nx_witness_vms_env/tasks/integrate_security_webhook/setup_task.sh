#!/bin/bash
set -e
echo "=== Setting up integrate_security_webhook task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up existing rules (Idempotency)
# ============================================================
echo "Cleaning up any existing webhook rules..."
refresh_nx_token > /dev/null 2>&1 || true

# Get all event rules
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Parse and find IDs of rules matching our target URLs or Names
IDS_TO_DELETE=$(echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    targets = ['webhooks/health', 'webhooks/panic', 'Panic Alert']
    ids = []
    for r in rules:
        # Check action URL
        action_url = r.get('actionUrl', '')
        # Check trigger caption (for soft triggers)
        caption = r.get('caption', '')
        
        if any(t in action_url for t in targets) or any(t in caption for t in targets):
            ids.append(r['id'])
    print(' '.join(ids))
except:
    pass
")

# Delete found rules
for rule_id in $IDS_TO_DELETE; do
    echo "Deleting stale rule: $rule_id"
    nx_api_delete "/rest/v1/eventRules/$rule_id" || true
done

# Record initial rule count
INITIAL_COUNT=$(count_event_rules 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_rule_count.txt

# ============================================================
# 2. Launch Desktop Client
# ============================================================
# Kill any existing clients
pkill -f "applauncher" 2>/dev/null || true
pkill -f "nxwitness" 2>/dev/null || true

echo "Launching Nx Witness Desktop Client..."
# Find applauncher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    # Launch in background
    DISPLAY=:1 "$APPLAUNCHER" > /dev/null 2>&1 &
    
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
    
    # Focus
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
else
    echo "WARNING: Desktop client not found, agent might need to start it."
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="