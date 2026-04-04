#!/bin/bash
set -e
echo "=== Setting up security configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify GeoServer is running and accessible
verify_geoserver_ready 120 || {
    echo "ERROR: GeoServer not ready, attempting restart..."
    cd /home/ga/geoserver && docker-compose restart gs-app
    sleep 30
    verify_geoserver_ready 120 || { echo "FATAL: GeoServer unavailable"; exit 1; }
}

# Clean slate: Remove artifacts if they exist from previous runs
echo "Cleaning environment..."
# 1. Remove user editor1
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/security/usergroup/user/editor1" >/dev/null 2>&1 || true
# 2. Remove role map_editor (and its assignments)
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/security/roles/role/map_editor" >/dev/null 2>&1 || true
# 3. Remove rule ne.*.w
# Note: REST API for ACL deletion is tricky, usually DELETE /security/acl/layers/ne.*.w
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/security/acl/layers/ne.*.w" >/dev/null 2>&1 || true

# Record initial state counts
echo "Recording initial state..."
INITIAL_ROLES=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles.json" 2>/dev/null || echo "{}")
INITIAL_USERS=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/usergroup/users.json" 2>/dev/null || echo "{}")

# Count items using python
INITIAL_ROLE_COUNT=$(echo "$INITIAL_ROLES" | python3 -c "import sys, json; d=json.load(sys.stdin); rs=d.get('roles',[]); print(len(rs) if isinstance(rs, list) else 0)" 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(echo "$INITIAL_USERS" | python3 -c "import sys, json; d=json.load(sys.stdin); us=d.get('users',[]); print(len(us) if isinstance(us, list) else 0)" 2>/dev/null || echo "0")

echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count.txt
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

echo "Initial roles: $INITIAL_ROLE_COUNT"
echo "Initial users: $INITIAL_USER_COUNT"

# Generate result nonce for integrity
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Ensure Firefox is open to the security page to assist the agent
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/?wicket:bookmarkablePage=:org.geoserver.security.web.SecuritySettingsPage' &" 2>/dev/null
sleep 8

# Wait for Firefox window
wait_for_window "firefox\|mozilla" 30

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="