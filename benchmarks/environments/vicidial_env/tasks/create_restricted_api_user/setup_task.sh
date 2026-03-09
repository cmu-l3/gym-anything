#!/bin/bash
set -e
echo "=== Setting up create_restricted_api_user task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL readiness
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# CLEANUP: Ensure the user doesn't already exist from a previous run
echo "Ensuring clean state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_users WHERE user='leadview_api';" 2>/dev/null || true

# Record initial user count for anti-gaming check
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_users" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt

# Launch Firefox to the Users section to help the agent start
# (Standard Admin URL usually goes to Reports or Main, going straight to Users is helpful but agent still needs to navigate)
TARGET_URL="${VICIDIAL_ADMIN_URL}?ADD=0A"

if ! pgrep -f "firefox" > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /tmp/firefox.log 2>&1 &"
else
    navigate_to_url "$TARGET_URL"
fi

wait_for_window "Firefox"
maximize_active_window

# Dismiss any potential auth dialogs or popups if they appear (simple blind escape)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="