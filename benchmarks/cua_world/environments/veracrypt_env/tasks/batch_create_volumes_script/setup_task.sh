#!/bin/bash
echo "=== Setting up batch_create_volumes_script task ==="

# Record task start time for anti-gaming (file creation checks)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up any artifacts from previous runs
echo "Cleaning previous artifacts..."
rm -f /home/ga/Volumes/finance_dept.hc
rm -f /home/ga/Volumes/legal_dept.hc
rm -f /home/ga/Volumes/engineering_dept.hc
rm -rf /home/ga/Scripts
rm -f /tmp/vc_verify_*

# Ensure clean mount state
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Scripts
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /home/ga/MountPoints/slot2
mkdir -p /home/ga/MountPoints/slot3
chown -R ga:ga /home/ga/Scripts
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/MountPoints

# Ensure VeraCrypt is running (GUI) - standard environment setup
if ! pgrep -f "veracrypt" > /dev/null; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Wait for VeraCrypt window
wait_for_window "VeraCrypt" 30

# Maximize and focus VeraCrypt
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true
sleep 1

# Open a terminal for the agent to work in (since this is a scripting task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30 &" 2>/dev/null || true
    sleep 2
fi
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="