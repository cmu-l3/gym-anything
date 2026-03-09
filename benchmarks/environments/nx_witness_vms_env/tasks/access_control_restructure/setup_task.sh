#!/bin/bash
echo "=== Setting up access_control_restructure task ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

# Record task start timestamp
date +%s > /tmp/acr_start_ts

# --- Idempotent setup: ensure john.smith and sarah.jones exist ---
ensure_user_exists() {
    local username="$1"
    local fullname="$2"
    local email="$3"
    local password="$4"

    local existing
    existing=$(get_user_by_name "$username" 2>/dev/null || echo "")
    if [ -z "$existing" ]; then
        echo "Creating user: $username"
        nx_api_post "/rest/v1/users" \
            "{\"name\": \"${username}\", \"fullName\": \"${fullname}\", \"email\": \"${email}\", \"password\": \"${password}\", \"permissions\": \"NoGlobalPermissions\"}" \
            > /dev/null 2>&1 || true
        sleep 1
    else
        echo "User already exists: $username"
    fi
}

ensure_user_exists "john.smith"   "John Smith"   "john.smith@gymvms.local"   "JohnSmith2024!"
ensure_user_exists "sarah.jones"  "Sarah Jones"  "sarah.jones@gymvms.local"  "SarahJones2024!"

# --- Remove ext.auditor if it exists (clean state) ---
EXISTING_EXT=$(get_user_by_name "ext.auditor" 2>/dev/null || echo "")
if [ -n "$EXISTING_EXT" ]; then
    EXT_ID=$(echo "$EXISTING_EXT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    if [ -n "$EXT_ID" ]; then
        echo "Removing existing ext.auditor (id: $EXT_ID)"
        nx_api_delete "/rest/v1/users/${EXT_ID}" > /dev/null 2>&1 || true
        sleep 1
    fi
fi

# --- Remove 'Audit Trail View' layout if it exists (clean state) ---
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")
echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    for l in layouts:
        if l.get('name','').strip().lower() == 'audit trail view':
            print(l.get('id',''))
            break
except: pass
" 2>/dev/null | while read layout_id; do
    if [ -n "$layout_id" ]; then
        echo "Removing existing 'Audit Trail View' layout (id: $layout_id)"
        nx_api_delete "/rest/v1/layouts/${layout_id}" > /dev/null 2>&1 || true
    fi
done

# --- Record baseline user count ---
INITIAL_USER_COUNT=$(count_users 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/acr_initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# --- Fetch and save camera IDs for later verification ---
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices" 2>/dev/null || echo "[]")
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

echo "$ENTRANCE_ID" > /tmp/acr_entrance_id
echo "$SERVER_ID"   > /tmp/acr_server_id
echo "Entrance Camera ID: $ENTRANCE_ID"
echo "Server Room Camera ID: $SERVER_ID"

# Navigate to Users section in Web Admin
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/users"
sleep 5
maximize_firefox

take_screenshot /tmp/access_control_restructure_start.png

echo "=== access_control_restructure setup complete ==="
echo "Task: Delete john.smith and sarah.jones; create ext.auditor; create 'Audit Trail View' layout"
