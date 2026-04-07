#!/bin/bash
echo "=== Setting up configure_event_action_script task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state for the task
mkdir -p /home/ga/scripts
rm -f /home/ga/scripts/log_event.sh
rm -f /home/ga/event_activity.log
# Clean specific config for scevent but leave rest of system intact
sed -i '/^scripts\.script/d' /home/ga/.seiscomp/scevent.cfg 2>/dev/null || true
sed -i '/^scripts\.script/d' "$SEISCOMP_ROOT/etc/scevent.cfg" 2>/dev/null || true

# Ensure SeisComP messaging and event processor are running
ensure_scmaster_running
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp start scevent" 2>/dev/null || true

# Retrieve the actual Event ID from the database
# (This ensures we check for the real dynamic ID in the verifier)
TARGET_EVENT_ID=$(seiscomp_db_query "SELECT publicID FROM Event LIMIT 1" 2>/dev/null || echo "")
echo "$TARGET_EVENT_ID" > /tmp/target_event_id.txt
echo "Target Event ID in DB: $TARGET_EVENT_ID"

# Prepare scolv so the agent has a way to easily trigger an event update
echo "--- Launching scolv ---"
kill_seiscomp_gui scolv
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

# Wait for scolv window to appear
wait_for_window "scolv" 45 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30

# Dismiss dialogs
dismiss_dialogs 2

# Focus and maximize scolv
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Take initial screenshot for evidence
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="