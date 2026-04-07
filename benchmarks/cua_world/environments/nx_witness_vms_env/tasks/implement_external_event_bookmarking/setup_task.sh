#!/bin/bash
set -e
echo "=== Setting up implement_external_event_bookmarking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
# Also in ISO format for API comparisons if needed
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_iso.txt

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# CLEANUP: Remove existing artifacts to ensure clean state
# ==============================================================================

# 1. Remove any existing Generic Event rules with our keywords
echo "Cleaning up existing event rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    # Find rules that match our criteria
    for rule in rules:
        cond = rule.get('eventCondition', '')
        if 'AI_Analytics' in cond or 'Loitering_Detected' in cond:
            print(rule.get('id'))
except:
    pass
" | while read rule_id; do
    if [ -n "$rule_id" ]; then
        echo "Deleting stale rule: $rule_id"
        nx_api_delete "/rest/v1/eventRules/$rule_id"
    fi
done

# 2. Remove existing bookmarks on the Parking Lot Camera
echo "Cleaning up existing bookmarks..."
CAM_ID=$(get_camera_id_by_name "Parking Lot Camera")
if [ -n "$CAM_ID" ]; then
    # Get bookmarks for this camera
    # Note: filter roughly by time/limit isn't strictly necessary if we just scan all recent ones,
    # but let's try to find matching ones to delete.
    BOOKMARKS_JSON=$(nx_api_get "/rest/v1/devices/$CAM_ID/bookmarks?limit=100")
    
    echo "$BOOKMARKS_JSON" | python3 -c "
import sys, json
try:
    bookmarks = json.load(sys.stdin)
    for b in bookmarks:
        if 'Loitering_Detected' in b.get('name', '') or 'Loitering_Detected' in b.get('description', ''):
            print(b.get('id'))
except:
    pass
" | while read b_id; do
    if [ -n "$b_id" ]; then
        echo "Deleting stale bookmark: $b_id"
        nx_api_delete "/rest/v1/devices/$CAM_ID/bookmarks/$b_id"
    fi
done
else
    echo "WARNING: Parking Lot Camera not found during setup!"
fi

# ==============================================================================
# UI SETUP
# ==============================================================================

# Open Firefox to the Event Rules section (Web Admin)
# Note: The Web Admin URL for rules might vary by version, usually under System Administration
# We'll stick to the main settings page or a relevant tab.
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system/rules"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="