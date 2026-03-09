#!/bin/bash
echo "=== Setting up create_security_user_role task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is up
verify_geoserver_ready 60

# Clean state: Remove the target user and role if they somehow exist from a previous run
echo "Cleaning previous state..."
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/security/roles/role/ROLE_DATA_ANALYST" 2>/dev/null || true
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/security/usergroup/user/analyst_jones" 2>/dev/null || true
rm -f /home/ga/auth_test_result.txt

# Record initial counts
INITIAL_ROLES=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('roles', [])))" 2>/dev/null || echo "0")
INITIAL_USERS=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/usergroup/users.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('users', [])))" 2>/dev/null || echo "0")

echo "$INITIAL_ROLES" > /tmp/initial_role_count.txt
echo "$INITIAL_USERS" > /tmp/initial_user_count.txt
echo "Initial Roles: $INITIAL_ROLES, Initial Users: $INITIAL_USERS"

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_security_user_role task setup complete ==="