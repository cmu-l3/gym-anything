#!/bin/bash
echo "=== Setting up configure_custom_message_group task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is initially running
ensure_scmaster_running

CONFIG_FILE="$SEISCOMP_ROOT/etc/scmaster.cfg"

# Strip out 'RISK' from the configuration if it exists to ensure a clean starting state
if [ -f "$CONFIG_FILE" ]; then
    sed -i 's/, RISK//g' "$CONFIG_FILE"
    sed -i 's/RISK, //g' "$CONFIG_FILE"
    sed -i 's/RISK//g' "$CONFIG_FILE"
    chown ga:ga "$CONFIG_FILE"
fi

# Restart scmaster to apply the clean state
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp restart scmaster" > /dev/null 2>&1

# Launch a terminal for the agent positioned at the configuration directory
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SEISCOMP_ROOT/etc" &

# Wait for terminal to load and maximize it
sleep 3
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial state screenshot (mandatory for evidence)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="