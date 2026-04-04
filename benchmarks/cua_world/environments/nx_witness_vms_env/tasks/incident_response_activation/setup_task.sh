#!/bin/bash
echo "=== Setting up incident_response_activation ==="
source /workspace/scripts/task_utils.sh

refresh_nx_token

# --- Disable recording on ALL cameras (agent must discover this) ---
CAMERAS=$(nx_api_get "/rest/v1/devices?type=Camera" | python3 -c "
import json, sys
devs = json.load(sys.stdin)
for d in devs:
    print(d['id'], d.get('name', ''))
")

echo "Disabling recording on all cameras..."
while IFS= read -r line; do
    CAM_ID=$(echo "$line" | awk '{print $1}')
    CAM_NAME=$(echo "$line" | cut -d' ' -f2-)
    if [ -n "$CAM_ID" ]; then
        echo "  Disabling: $CAM_NAME ($CAM_ID)"
        nx_api_patch "/rest/v1/devices/$CAM_ID" "{\"schedule\":{\"isEnabled\":false,\"tasks\":[]}}" > /dev/null 2>&1
    fi
done <<< "$CAMERAS"

# Save camera IDs for export script
nx_api_get "/rest/v1/devices?type=Camera" | python3 -c "
import json, sys
devs = json.load(sys.stdin)
for d in devs:
    name_lower = d.get('name', '').lower()
    if 'parking' in name_lower:
        print('PARKING_CAM_ID=' + d['id'])
    elif 'entrance' in name_lower:
        print('ENTRANCE_CAM_ID=' + d['id'])
    elif 'server' in name_lower:
        print('SERVER_CAM_ID=' + d['id'])
" > /tmp/ira_camera_ids.sh

echo "Camera IDs saved:"
cat /tmp/ira_camera_ids.sh

# --- Reset security.operator user to original state ---
USERS=$(nx_api_get "/rest/v1/users")
SEC_OP_ID=$(echo "$USERS" | python3 -c "
import json, sys
users = json.load(sys.stdin)
for u in users:
    if u.get('name','').lower() == 'security.operator':
        print(u['id'])
        break
")

if [ -n "$SEC_OP_ID" ]; then
    echo "Resetting security.operator (ID=$SEC_OP_ID) to original state..."
    nx_api_patch "/rest/v1/users/$SEC_OP_ID" \
        "{\"fullName\":\"Security Operator\",\"email\":\"security.operator@facility.com\"}" > /dev/null 2>&1
    echo "SEC_OP_ID=$SEC_OP_ID" > /tmp/ira_sec_op.sh
else
    echo "WARNING: security.operator user not found!"
fi

# --- Remove incident.cmdr if exists ---
ICMDR_ID=$(echo "$USERS" | python3 -c "
import json, sys
users = json.load(sys.stdin)
for u in users:
    if u.get('name','').lower() == 'incident.cmdr':
        print(u['id'])
        break
")
if [ -n "$ICMDR_ID" ]; then
    echo "Removing pre-existing incident.cmdr user..."
    nx_api_delete "/rest/v1/users/$ICMDR_ID" > /dev/null 2>&1
fi

# --- Remove 'Incident Command Center' layout if exists ---
LAYOUTS=$(nx_api_get "/rest/v1/layouts")
ICC_ID=$(echo "$LAYOUTS" | python3 -c "
import json, sys
layouts = json.load(sys.stdin)
for l in layouts:
    if l.get('name','').lower() == 'incident command center':
        print(l['id'])
        break
")
if [ -n "$ICC_ID" ]; then
    echo "Removing pre-existing 'Incident Command Center' layout..."
    nx_api_delete "/rest/v1/layouts/$ICC_ID" > /dev/null 2>&1
fi

# --- Record baseline state ---
LAYOUT_COUNT=$(nx_api_get "/rest/v1/layouts" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
USER_COUNT=$(nx_api_get "/rest/v1/users" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
echo "$LAYOUT_COUNT" > /tmp/ira_initial_layout_count
echo "$USER_COUNT" > /tmp/ira_initial_user_count
date +%s > /tmp/task_start_timestamp

echo "Baseline: $LAYOUT_COUNT layouts, $USER_COUNT users"

ensure_firefox_running
take_screenshot "/tmp/task_start_screenshot.png"

echo "=== Setup Complete ==="
