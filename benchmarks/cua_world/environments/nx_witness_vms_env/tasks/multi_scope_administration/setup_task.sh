#!/bin/bash
echo "=== Setting up multi_scope_administration task ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

date +%s > /tmp/msa_start_ts

# Ensure system name is reset to GymAnythingVMS (original state)
SYSTEM_NAME_RESULT=$(nx_api_patch "/rest/v1/system" '{"name": "GymAnythingVMS"}' 2>/dev/null || echo "{}")
echo "System name reset to GymAnythingVMS"

# Fetch camera IDs
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices" 2>/dev/null || echo "[]")

PARKING_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    for c in json.load(sys.stdin):
        if 'parking' in c.get('name','').lower():
            print(c.get('id','')); break
except: pass
" 2>/dev/null || echo "")

ENTRANCE_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    for c in json.load(sys.stdin):
        if 'entrance' in c.get('name','').lower():
            print(c.get('id','')); break
except: pass
" 2>/dev/null || echo "")

SERVER_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    for c in json.load(sys.stdin):
        if 'server' in c.get('name','').lower():
            print(c.get('id','')); break
except: pass
" 2>/dev/null || echo "")

echo "$PARKING_ID"  > /tmp/msa_parking_id
echo "$ENTRANCE_ID" > /tmp/msa_entrance_id
echo "$SERVER_ID"   > /tmp/msa_server_id
echo "Parking Lot: $PARKING_ID | Entrance: $ENTRANCE_ID | Server Room: $SERVER_ID"

# Remove target layouts if they already exist (idempotent)
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")
echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    for l in json.load(sys.stdin):
        name = l.get('name','').lower()
        if 'perimeter surveillance' in name or 'infrastructure monitoring' in name:
            print(l.get('id',''))
except: pass
" 2>/dev/null | while read lid; do
    [ -n "$lid" ] && nx_api_delete "/rest/v1/layouts/${lid}" > /dev/null 2>&1 || true
done
echo "Cleaned up any pre-existing target layouts"

# Remove vendor.tech if it exists (idempotent)
VENDOR_USER=$(get_user_by_name "vendor.tech" 2>/dev/null || echo "")
if [ -n "$VENDOR_USER" ]; then
    VENDOR_ID=$(echo "$VENDOR_USER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    [ -n "$VENDOR_ID" ] && nx_api_delete "/rest/v1/users/${VENDOR_ID}" > /dev/null 2>&1 || true
    echo "Removed existing vendor.tech user"
fi

# Navigate to System settings area to start agent at a relevant page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
sleep 5
maximize_firefox

take_screenshot /tmp/multi_scope_administration_start.png

echo "=== multi_scope_administration setup complete ==="
echo "System name: GymAnythingVMS (agent must rename to 'RetailSecure Pro')"
echo "Task: Rename system + create 2 layouts + create vendor.tech user"
