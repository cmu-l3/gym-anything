#!/bin/bash
echo "=== Exporting set_out_of_office_delegate result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Capture Final State ───────────────────────────────────────────────────
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# ── 2. Query ArkCase API for Delegates ───────────────────────────────────────
echo "Querying final user profile for delegates..."
# The delegates are typically nested in the user profile object
PROFILE_RESPONSE=$(arkcase_api GET "users/profile" 2>/dev/null)

# Verify if we got a valid JSON response
if echo "$PROFILE_RESPONSE" | grep -q "username"; then
    API_SUCCESS="true"
else
    API_SUCCESS="false"
    echo "WARNING: Failed to retrieve user profile via API"
fi

# Save raw response for debugging/verification
echo "$PROFILE_RESPONSE" > /tmp/final_profile.json

# ── 3. Check App State ───────────────────────────────────────────────────────
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# ── 4. Create Result JSON ────────────────────────────────────────────────────
# We embed the API response directly into the result JSON for the python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to safely construct the JSON to avoid escaping issues
python3 -c "
import json
import os
import time

try:
    with open('/tmp/final_profile.json', 'r') as f:
        profile_data = json.load(f)
except:
    profile_data = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'api_success': $API_SUCCESS,
    'app_running': $APP_RUNNING,
    'profile_data': profile_data,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="