#!/bin/bash
set -e

echo "=== Setting up Configure Automated Report Schedule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for database to be ready
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# RESET STATE: Ensure Scheduled Reports is DISABLED initially
# This forces the agent to go to System Settings first
echo "Resetting System Settings..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE system_settings SET enable_scheduled_reports='0';"

# RESET STATE: Delete the target scheduled report if it exists
echo "Cleaning up existing schedules..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_scheduled_reports WHERE scheduled_id='DAILY_LOG';"

# Launch Firefox to the Admin panel
# We use the standard admin URL
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "Firefox" 60
maximize_active_window

# Ensure we are logged in (Auto-login handling or session check)
# The environment setup script handles basic auth credentials if using URL params,
# but we'll try to ensure we are on a valid page.
navigate_to_url "${VICIDIAL_ADMIN_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="