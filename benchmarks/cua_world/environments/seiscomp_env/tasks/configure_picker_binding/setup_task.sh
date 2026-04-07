#!/bin/bash
echo "=== Setting up configure_picker_binding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure SeisComP messaging is running
ensure_scmaster_running

# 2. Clean up any existing bindings/profiles for this task to ensure a fresh start
echo "Cleaning up any existing broadband_opt profiles..."
rm -f "$SEISCOMP_ROOT/etc/scautopick/broadband_opt"

echo "Removing any existing scautopick bindings from GE stations..."
for keyfile in "$SEISCOMP_ROOT"/etc/key/station_GE_*; do
    if [ -f "$keyfile" ]; then
        # Delete lines starting with 'scautopick:'
        sed -i '/^scautopick:/d' "$keyfile"
    fi
done

# 3. Ensure scconfig is not running (prevent lock issues)
kill_seiscomp_gui scconfig

# 4. Launch scconfig for the agent
echo "Launching scconfig..."
launch_seiscomp_gui scconfig "--plugins dbmysql"

# Wait for window
wait_for_window "scconfig" 15 || wait_for_window "Configuration" 15
sleep 3

# Dismiss startup dialogs (e.g. "Do you want to run setup?")
dismiss_dialogs 2

# Focus and maximize
focus_and_maximize "scconfig" || focus_and_maximize "Configuration"
sleep 2

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="