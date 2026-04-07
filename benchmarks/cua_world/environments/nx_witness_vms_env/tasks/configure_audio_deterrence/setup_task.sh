#!/bin/bash
set -e
echo "=== Setting up configure_audio_deterrence task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# 1. Ensure Target Camera Exists
# ==============================================================================
TARGET_NAME="Loading Dock Camera"
TARGET_ID=$(get_camera_id_by_name "$TARGET_NAME")

if [ -z "$TARGET_ID" ]; then
    echo "Target camera '$TARGET_NAME' not found. Renaming a spare camera..."
    # Get the last camera in the list to minimize conflict with other tasks
    SPARE_ID=$(nx_api_get "/rest/v1/devices" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[-1]['id'] if d else '')" 2>/dev/null)
    
    if [ -n "$SPARE_ID" ]; then
        nx_api_patch "/rest/v1/devices/${SPARE_ID}" "{\"name\": \"$TARGET_NAME\"}" > /dev/null
        TARGET_ID="$SPARE_ID"
        echo "Renamed camera $SPARE_ID to '$TARGET_NAME'"
    else
        echo "ERROR: No cameras available to configure!"
        exit 1
    fi
else
    echo "Found target camera: $TARGET_NAME ($TARGET_ID)"
fi

# Save Target ID for export script
echo "$TARGET_ID" > /tmp/target_camera_id.txt

# ==============================================================================
# 2. Clean Slate: Remove conflicting Event Rules
# ==============================================================================
echo "Cleaning up existing event rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Parse JSON to find rules involving this camera or motion/sound
# We simply delete ALL rules to ensure a clean state for the agent, 
# or specific ones if we want to be less destructive. 
# For this task, wiping user-created rules is safer.
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    ids = [r['id'] for r in rules if not r.get('isSystem', False)] # Don't delete system rules
    print(' '.join(ids))
except:
    pass
" | while read -r rule_id; do
    if [ -n "$rule_id" ]; then
        for rid in $rule_id; do
            echo "Deleting existing rule: $rid"
            nx_api_delete "/rest/v1/eventRules/$rid" > /dev/null 2>&1 || true
        done
    fi
done

# ==============================================================================
# 3. Setup Browser
# ==============================================================================
# Open Firefox to the Event Rules page (or General Settings if deep link fails)
# Note: The Web Admin URL for Event Rules might differ by version, 
# usually it's under System Administration or Camera Settings.
# We'll send them to the main settings page.
URL="https://localhost:7001/static/index.html#/settings/system"

echo "Starting Firefox at $URL..."
ensure_firefox_running "$URL"
sleep 5
maximize_firefox

# Dismiss SSL warning if it appears
dismiss_ssl_warning

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="