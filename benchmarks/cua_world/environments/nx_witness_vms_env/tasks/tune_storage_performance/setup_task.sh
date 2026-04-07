#!/bin/bash
set -e
echo "=== Setting up tune_storage_performance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Authenticate and get token
echo "Authenticating..."
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get auth token"
    exit 1
fi

# 2. Get Server ID
echo "Retrieving Server ID..."
SERVER_ID=$(get_server_id)
if [ -z "$SERVER_ID" ]; then
    echo "ERROR: No server found"
    exit 1
fi
echo "Target Server ID: $SERVER_ID"
echo "$SERVER_ID" > /tmp/nx_server_id.txt

# 3. Reset State: Set Backup Bandwidth to Unlimited (0)
# Note: In Nx Witness, this is often a system-wide setting or server setting.
# We will try patching system settings first.
echo "Resetting Backup Bandwidth to Unlimited..."
nx_api_patch "/rest/v1/system/settings" '{"maxBackupBandwidthBps": 0}' > /dev/null 2>&1 || true

# 4. Reset State: Set Storage Reserve to default (e.g., 5GB or 10GB)
echo "Resetting Storage Reserve space..."
# Get the first storage ID for this server
STORAGE_LIST=$(nx_api_get "/rest/v1/servers/${SERVER_ID}/storages")
STORAGE_ID=$(echo "$STORAGE_LIST" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(data[0].get('id'))
    else:
        print('')
except:
    print('')
")

if [ -n "$STORAGE_ID" ]; then
    echo "Resetting storage $STORAGE_ID to 5GB reserve..."
    # 5GB = 5368709120 bytes
    nx_api_patch "/rest/v1/servers/${SERVER_ID}/storages/${STORAGE_ID}" \
        '{"reservedSpaceBytes": 5368709120}' > /dev/null 2>&1 || true
else
    echo "WARNING: No storage found to reset"
fi

# 5. Launch Firefox to the Web Admin
echo "Launching Firefox..."
# Navigate to the general settings or server settings page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/servers/${SERVER_ID}"
sleep 5
maximize_firefox

# 6. Capture Initial State Screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

# Record initial values for debugging/verification
echo "Recording initial state..."
INITIAL_SETTINGS=$(nx_api_get "/rest/v1/system/settings")
echo "$INITIAL_SETTINGS" > /tmp/initial_system_settings.json

echo "=== Task setup complete ==="