#!/bin/bash
set -e
echo "=== Setting up task: setup_store_manager_role ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure all services are running
ensure_services_running 120

# ============================================================
# Record initial state (anti-gaming baseline)
# ============================================================
echo "Recording initial state..."

INITIAL_USER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_USER_COUNT"

INITIAL_ROLE_COUNT=$(cd "$DRUPAL_DIR" && $DRUSH role:list --format=list 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count.txt
echo "Initial role count: $INITIAL_ROLE_COUNT"

# Verify store_manager role does NOT already exist
EXISTING_ROLE=$(cd "$DRUPAL_DIR" && $DRUSH role:list --format=list 2>/dev/null | grep -c "store_manager" || echo "0")
if [ "$EXISTING_ROLE" -gt 0 ]; then
    echo "WARNING: store_manager role already exists, removing..."
    cd "$DRUPAL_DIR" && $DRUSH role:delete store_manager -y 2>/dev/null || true
fi

# Verify sarahchen user does NOT already exist
EXISTING_USER=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE name = 'sarahchen'" 2>/dev/null || echo "0")
if [ "$EXISTING_USER" -gt 0 ]; then
    echo "WARNING: sarahchen user already exists, removing..."
    cd "$DRUPAL_DIR" && $DRUSH user:cancel sarahchen -y --delete-content 2>/dev/null || true
fi

# Clear caches
cd "$DRUPAL_DIR" && $DRUSH cr 2>/dev/null || true

# ============================================================
# Launch Firefox with Drupal admin
# ============================================================
echo "Launching Firefox..."

# Kill existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Get a login URL for admin
LOGIN_URL=$(cd "$DRUPAL_DIR" && $DRUSH uli --uri=http://localhost --no-browser --uid=1 2>/dev/null)
if [ -z "$LOGIN_URL" ]; then
    LOGIN_URL="http://localhost/user/login"
fi

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox '${LOGIN_URL}?destination=admin/people' &" 2>/dev/null
sleep 8

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Initial user count: $INITIAL_USER_COUNT"
echo "Initial role count: $INITIAL_ROLE_COUNT"
echo "Firefox opened to People admin page"