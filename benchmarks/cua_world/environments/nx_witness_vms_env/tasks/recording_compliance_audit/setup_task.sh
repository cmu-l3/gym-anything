#!/bin/bash
echo "=== Setting up recording_compliance_audit task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Record task start timestamp (AFTER any file cleanup, BEFORE agent starts)
date +%s > /tmp/recording_compliance_audit_start_ts

# Fetch all cameras
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices" 2>/dev/null || echo "[]")

# Extract camera IDs by name
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

echo "Parking Lot Camera ID: $PARKING_ID"
echo "Server Room Camera ID: $SERVER_ID"
echo "Entrance Camera ID: $ENTRANCE_ID"

# Persist IDs for export script
echo "$PARKING_ID"  > /tmp/rca_parking_id
echo "$SERVER_ID"   > /tmp/rca_server_id
echo "$ENTRANCE_ID" > /tmp/rca_entrance_id

# Disable recording on Parking Lot Camera (inject recording gap)
if [ -n "$PARKING_ID" ]; then
    nx_api_patch "/rest/v1/devices/${PARKING_ID}" '{"schedule": {"isEnabled": false, "tasks": []}}' > /dev/null 2>&1 || true
    echo "Recording DISABLED for Parking Lot Camera"
fi

# Disable recording on Server Room Camera (inject recording gap)
if [ -n "$SERVER_ID" ]; then
    nx_api_patch "/rest/v1/devices/${SERVER_ID}" '{"schedule": {"isEnabled": false, "tasks": []}}' > /dev/null 2>&1 || true
    echo "Recording DISABLED for Server Room Camera"
fi

# Ensure Entrance Camera has recording enabled (baseline — left intact for agent to discover)
if [ -n "$ENTRANCE_ID" ]; then
    enable_recording_for_camera "$ENTRANCE_ID" 15 > /dev/null 2>&1 || true
    echo "Recording ENABLED for Entrance Camera (baseline)"
fi

# Record initial layout count (for anti-gaming check)
INITIAL_LAYOUT_COUNT=$(count_layouts 2>/dev/null || echo "0")
echo "$INITIAL_LAYOUT_COUNT" > /tmp/rca_initial_layout_count
echo "Initial layout count: $INITIAL_LAYOUT_COUNT"

# Navigate Firefox to the Cameras section of Web Admin
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

# Take start screenshot
take_screenshot /tmp/recording_compliance_audit_start.png

echo "=== recording_compliance_audit setup complete ==="
echo "State: Parking Lot Camera and Server Room Camera have recording DISABLED"
echo "State: Entrance Camera has recording ENABLED"
echo "Task: Agent must discover gaps, enable 24/7 recording on all cameras, and create layout"
