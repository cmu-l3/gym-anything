#!/bin/bash
echo "=== Setting up review_event_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming check)
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services are running
echo "Ensuring SeisComP scmaster is running..."
ensure_scmaster_running

# Reset Database State (Anti-Gaming / Clean Slate)
# 1. Reset Event preference back to USGS origin
# 2. Delete any manual objects created by 'GYM' agency
echo "Cleaning up any previous manual commits..."
mysql -u sysop -psysop seiscomp << 'EOF'
UPDATE Event SET 
  preferredOriginID = (SELECT publicID FROM Origin WHERE creationInfo_agencyID != 'GYM' LIMIT 1),
  preferredMagnitudeID = (SELECT publicID FROM Magnitude WHERE creationInfo_agencyID != 'GYM' LIMIT 1)
WHERE 1;
DELETE FROM EventComment WHERE text LIKE '%Depth constrained%';
DELETE FROM Magnitude WHERE creationInfo_agencyID = 'GYM';
DELETE FROM Origin WHERE creationInfo_agencyID = 'GYM';
EOF

# Kill any existing scolv instances
kill_seiscomp_gui scolv

# Launch scolv automatically to save agent terminal boilerplate
echo "Launching scolv..."
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

# Wait for scolv window to appear
wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30
sleep 3

# Dismiss any startup dialogs
dismiss_dialogs 2

# Focus and maximize scolv window
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="