#!/bin/bash
set -e
echo "=== Setting up create_agent_user task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be fully ready before executing queries
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Record initial state - check if user 2001 already exists (it should NOT)
INITIAL_USER_EXISTS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN \
  -e "SELECT COUNT(*) FROM vicidial_users WHERE user='2001';" 2>/dev/null || echo "0")
echo "$INITIAL_USER_EXISTS" > /tmp/initial_user_2001_exists.txt

# If user 2001 already exists from a prior run, remove it for clean state
if [ "$INITIAL_USER_EXISTS" != "0" ]; then
  echo "Cleaning up pre-existing user 2001..."
  docker exec vicidial mysql -ucron -p1234 -D asterisk \
    -e "DELETE FROM vicidial_users WHERE user='2001';" 2>/dev/null || true
fi

# Record total user count before task
INITIAL_USER_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN \
  -e "SELECT COUNT(*) FROM vicidial_users;" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# Setup Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

ADMIN_URL="http://localhost/vicidial/admin.php"
echo "Launching Firefox at $ADMIN_URL..."
su - ga -c "DISPLAY=:1 firefox '${ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
for i in {1..30}; do
  if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|vicidial'; then
    echo "Firefox window detected"
    break
  fi
  sleep 1
done

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Basic Auth if needed or Login Page
# Note: The environment might require HTTP Basic Auth or Form Login.
# We will attempt to pre-fill if on the form, but usually, the agent handles this.
# However, for a consistent start state, we ensure the window is ready.

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="