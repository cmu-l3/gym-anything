#!/bin/bash
echo "=== Setting up tiered_recording_policy task ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

date +%s > /tmp/trp_start_ts

# Fetch all camera IDs
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices" 2>/dev/null || echo "[]")

PARKING_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    cams = json.load(sys.stdin)
    for c in cams:
        if 'parking' in c.get('name','').lower():
            print(c.get('id',''))
            break
except: pass
" 2>/dev/null || echo "")

ENTRANCE_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    cams = json.load(sys.stdin)
    for c in cams:
        if 'entrance' in c.get('name','').lower():
            print(c.get('id',''))
            break
except: pass
" 2>/dev/null || echo "")

SERVER_ID=$(echo "$CAMERAS_JSON" | python3 -c "
import sys, json
try:
    cams = json.load(sys.stdin)
    for c in cams:
        if 'server' in c.get('name','').lower():
            print(c.get('id',''))
            break
except: pass
" 2>/dev/null || echo "")

echo "Parking Lot Camera ID: $PARKING_ID"
echo "Entrance Camera ID: $ENTRANCE_ID"
echo "Server Room Camera ID: $SERVER_ID"

echo "$PARKING_ID"  > /tmp/trp_parking_id
echo "$ENTRANCE_ID" > /tmp/trp_entrance_id
echo "$SERVER_ID"   > /tmp/trp_server_id

# Disable recording on ALL cameras (clean starting state — agent must configure all three)
for CAM_ID in "$PARKING_ID" "$ENTRANCE_ID" "$SERVER_ID"; do
    if [ -n "$CAM_ID" ]; then
        nx_api_patch "/rest/v1/devices/${CAM_ID}" '{"schedule": {"isEnabled": false, "tasks": []}}' > /dev/null 2>&1 || true
    fi
done
echo "All cameras set to recording disabled"

# Remove 'Security Operations Center' layout if it exists (idempotent)
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")
echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    for l in layouts:
        if 'security operations center' in l.get('name','').lower():
            print(l.get('id',''))
except: pass
" 2>/dev/null | while read layout_id; do
    if [ -n "$layout_id" ]; then
        nx_api_delete "/rest/v1/layouts/${layout_id}" > /dev/null 2>&1 || true
        echo "Removed existing 'Security Operations Center' layout"
    fi
done

# Navigate to cameras section
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

take_screenshot /tmp/tiered_recording_policy_start.png

echo "=== tiered_recording_policy setup complete ==="
echo "All cameras: recording DISABLED (agent must configure tier-specific schedules)"
