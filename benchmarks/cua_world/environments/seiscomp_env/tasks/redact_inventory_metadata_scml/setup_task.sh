#!/bin/bash
echo "=== Setting up redact_inventory_metadata_scml task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create export directory and ensure it's clean
mkdir -p /home/ga/exports
rm -f /home/ga/exports/redacted_inventory.scml 2>/dev/null || true
chown -R ga:ga /home/ga/exports

# Ensure SeisComP services are running
echo "Ensuring SeisComP services are running..."
ensure_scmaster_running

# Open a terminal for the user to work in
if ! pgrep -f "xfce4-terminal\|gnome-terminal\|xterm" > /dev/null; then
    echo "Opening terminal..."
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30+100+100 &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 xfce4-terminal &" 2>/dev/null || true
    sleep 3
fi

# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || DISPLAY=:1 wmctrl -a "xterm" 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="