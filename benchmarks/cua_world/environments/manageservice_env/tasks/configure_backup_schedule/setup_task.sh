#!/bin/bash
# Setup for "configure_backup_schedule" task
# Ensures SDP is running and records initial database state

echo "=== Setting up Configure Backup Schedule task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# Record initial backup configuration for comparison
# We attempt to query common tables for backup schedules
echo "Recording initial DB state..."
sdp_db_exec "SELECT * FROM backupschedule;" > /tmp/initial_backupschedule_dump.txt 2>/dev/null || echo "Table backupschedule not found" > /tmp/initial_backupschedule_dump.txt
sdp_db_exec "SELECT * FROM periodic_backup_schedule;" > /tmp/initial_periodic_dump.txt 2>/dev/null || echo "Table periodic_backup_schedule not found" > /tmp/initial_periodic_dump.txt

# Launch Firefox to the Login page (or Admin page if possible, but login is safer start)
# The agent needs to log in as administrator
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "ServiceDesk Plus is ready."
echo "Please log in (administrator/administrator) and configure the backup schedule."