#!/bin/bash
echo "=== Setting up task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running
ensure_scmaster_running

# Clean any existing bindings or profiles for GE.TOLI to ensure a clean starting state
echo "Cleaning existing GE.TOLI bindings..."
rm -f $SEISCOMP_ROOT/etc/key/station_GE_TOLI* 2>/dev/null || true
rm -f $SEISCOMP_ROOT/etc/key/profile_scmag_GE_TOLI* 2>/dev/null || true

# Create an empty base key file so the station is visible in scconfig bindings
touch $SEISCOMP_ROOT/etc/key/station_GE_TOLI
chown ga:ga $SEISCOMP_ROOT/etc/key/station_GE_TOLI

# Kill any existing scconfig instances
kill_seiscomp_gui scconfig
sleep 1

# Launch scconfig
echo "Launching scconfig..."
launch_seiscomp_gui scconfig "--plugins dbmysql"

# Wait for scconfig window to appear
wait_for_window "scconfig" 30 || wait_for_window "Configuration" 30
sleep 2

# Dismiss any startup dialogs
dismiss_dialogs 2

# Focus and maximize scconfig window
focus_and_maximize "scconfig" || focus_and_maximize "Configuration"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="