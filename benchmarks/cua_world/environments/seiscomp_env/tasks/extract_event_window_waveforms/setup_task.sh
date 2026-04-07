#!/bin/bash
echo "=== Setting up extract_event_window_waveforms task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Ensure services are running
echo "Ensuring SeisComP services are running..."
ensure_scmaster_running
systemctl start mariadb || true

# 3. Ensure clean initial state (remove any existing target output)
rm -f /home/ga/noto_event_data.mseed 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 4. Open a terminal for the agent to use
echo "Opening terminal for the agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
sleep 3

# Focus the terminal to ensure it is the active window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# 5. Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="