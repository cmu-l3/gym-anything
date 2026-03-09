#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_security_role task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be fully ready
wait_for_orientdb 120

# Connect details
DB="demodb"

# --- Clean up previous state ---
echo "Cleaning up any existing role or user..."

# Delete user 'maria_garcia' if exists
orientdb_sql "$DB" "DELETE FROM OUser WHERE name = 'maria_garcia'" > /dev/null 2>&1 || true

# Delete role 'data_analyst' if exists
# Note: Deleting a role might fail if users are assigned, but we just deleted the user.
orientdb_sql "$DB" "DELETE FROM ORole WHERE name = 'data_analyst'" > /dev/null 2>&1 || true

sleep 2

# --- Record Initial State ---
# Verify they are gone
ROLE_CHECK=$(orientdb_sql "$DB" "SELECT count(*) as cnt FROM ORole WHERE name = 'data_analyst'" 2>/dev/null)
ROLE_COUNT=$(echo "$ROLE_CHECK" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

USER_CHECK=$(orientdb_sql "$DB" "SELECT count(*) as cnt FROM OUser WHERE name = 'maria_garcia'" 2>/dev/null)
USER_COUNT=$(echo "$USER_CHECK" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "Initial State - Roles: $ROLE_COUNT, Users: $USER_COUNT"
echo "$ROLE_COUNT" > /tmp/initial_role_count.txt
echo "$USER_COUNT" > /tmp/initial_user_count.txt

# --- Launch Application ---
echo "Launching Firefox to OrientDB Studio..."
# Kill any existing instances to ensure clean start
kill_firefox

# Launch Firefox
launch_firefox "http://localhost:2480/studio/index.html" 10

# Maximize Firefox window for better visibility
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="