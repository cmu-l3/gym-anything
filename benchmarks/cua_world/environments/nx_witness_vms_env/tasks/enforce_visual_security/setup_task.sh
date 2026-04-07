#!/bin/bash
set -e
echo "=== Setting up enforce_visual_security task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Nx Witness Server is running and accessible
echo "Checking Nx Witness Server status..."
wait_for_nx_server

# 2. Reset Security Settings to 'Insecure' Defaults
# This ensures the agent must actually perform the task
echo "Resetting security settings..."
TOKEN=$(get_nx_token)

# Construct the settings payload to disable security features
# Note: Parameter names are based on standard Nx Witness API structures.
# We reset watermark, timeout, and https enforcement.
RESET_PAYLOAD='{
  "watermarkSettings": {
    "useUserName": false,
    "opacity": 0.0,
    "frequency": 0
  },
  "sessionTimeoutS": 0,
  "trafficEncryptionForced": false,
  "auditTrailEnabled": false
}'

# Apply reset via API
curl -sk -X PATCH "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$RESET_PAYLOAD" \
    --max-time 15 > /tmp/reset_response.json 2>&1 || true

echo "Security settings reset complete."

# 3. Launch Firefox to the Web Admin Security/General page
# The specific URL fragment might vary, usually #/settings/system
TARGET_URL="https://localhost:7001/static/index.html#/settings/system"

echo "Launching Firefox..."
ensure_firefox_running "$TARGET_URL"

# Wait for browser to settle
sleep 5
maximize_firefox

# 4. Handle SSL Warning if present (since we rely on UI interaction)
dismiss_ssl_warning

# 5. Capture initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="