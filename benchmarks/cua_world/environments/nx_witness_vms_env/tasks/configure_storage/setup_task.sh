#!/bin/bash
set -e
echo "=== Setting up storage management task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure server is running
systemctl start networkoptix-mediaserver 2>/dev/null || true
sleep 5

# Refresh auth token
TOKEN=$(refresh_nx_token)
echo "Auth token refreshed"

# Get server ID
SERVER_ID=$(get_server_id)
echo "Server ID: $SERVER_ID"
echo "$SERVER_ID" > /tmp/nx_server_id.txt

# Record initial storage state for anti-gaming
INITIAL_STORAGES=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://localhost:7001/rest/v1/servers/${SERVER_ID}/storages" \
    --max-time 15 2>/dev/null || echo "[]")
echo "$INITIAL_STORAGES" > /tmp/initial_storages.json

INITIAL_COUNT=$(echo "$INITIAL_STORAGES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data) if isinstance(data, list) else 0)
except:
    print(0)
" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_storage_count.txt
echo "Initial storage count: $INITIAL_COUNT"

# Create storage directories with proper permissions
# The media server runs as 'networkoptix-mediaserver' usually, or root in some docker setups
mkdir -p /opt/nx_storage/primary
mkdir -p /opt/nx_storage/backup

# Determine user (process owner)
NX_USER=$(ps -eo user,comm | grep mediaserver | head -1 | awk '{print $1}')
if [ -z "$NX_USER" ]; then NX_USER="networkoptix-mediaserver"; fi

echo "Setting permissions for $NX_USER..."
chown -R $NX_USER:$NX_USER /opt/nx_storage 2>/dev/null || true
chmod -R 777 /opt/nx_storage

# Open Firefox to web admin storage page (if possible, otherwise just index)
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/servers/${SERVER_ID}"
sleep 5
dismiss_ssl_warning
sleep 3
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Storage management task setup complete ==="