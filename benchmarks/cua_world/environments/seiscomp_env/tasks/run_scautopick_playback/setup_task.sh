#!/bin/bash
echo "=== Setting up run_scautopick_playback task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running (needed for database connections)
ensure_scmaster_running

# Clean up any existing configurations from previous runs to ensure clean state
echo "Cleaning up configurations and files..."
rm -f "$SEISCOMP_ROOT/etc/scautopick.cfg" 2>/dev/null || true
rm -f /home/ga/Documents/autopicks.xml 2>/dev/null || true
rm -f /home/ga/Documents/pick_summary.txt 2>/dev/null || true
mkdir -p /home/ga/Documents

# Ensure key files exist but are empty (agent needs to add scautopick manually)
mkdir -p "$SEISCOMP_ROOT/etc/key"
for STA in TOLI GSI KWP SANI BKB; do
    echo "default" > "$SEISCOMP_ROOT/etc/key/station_GE_$STA"
done
chown -R ga:ga "$SEISCOMP_ROOT/etc/key"

# Start a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize the terminal for agent visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="