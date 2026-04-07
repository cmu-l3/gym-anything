#!/bin/bash
echo "=== Setting up tune_event_association_scevent task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Ensure core SeisComP services are running
ensure_scmaster_running

echo "Ensuring scevent is running initially..."
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp start scevent" > /dev/null 2>&1 || true
sleep 2

# 2. Set up a clean configuration state for scevent
CONFIG_FILE="$SEISCOMP_ROOT/etc/scevent.cfg"
rm -f "$CONFIG_FILE"
touch "$CONFIG_FILE"
chown ga:ga "$CONFIG_FILE"

# Record the initial modification time of the config file
stat -c %Y "$CONFIG_FILE" > /tmp/initial_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_mtime.txt

# Record the initial PID of the scevent process (to verify they actually restart it)
INITIAL_PID=$(pgrep -u ga -x scevent | head -n 1 || echo "0")
echo "$INITIAL_PID" > /tmp/initial_scevent_pid.txt
echo "Initial scevent PID: $INITIAL_PID"

# 3. Open a terminal for the user to work from
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga" &
sleep 3
focus_and_maximize "Terminal"

# 4. Take the initial screenshot to prove task starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="