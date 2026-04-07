#!/bin/bash
set -euo pipefail

echo "=== Setting up create_mailing_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming (must happen after task actions)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is not running to reset state
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing existing Thunderbird instances..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 1
fi

# Locate the correct profile directory
PROFILE_DIR=$(grep "Path=" /home/ga/.thunderbird/profiles.ini 2>/dev/null | grep -i "default" | cut -d= -f2 | head -n 1 || echo "default-release")
FULL_PROFILE_DIR="/home/ga/.thunderbird/$PROFILE_DIR"

echo "Using Thunderbird profile: $FULL_PROFILE_DIR"

# Completely clear the address book to ensure a pristine starting state
if [ -d "$FULL_PROFILE_DIR" ]; then
    echo "Clearing existing address book files..."
    find "$FULL_PROFILE_DIR" -maxdepth 1 -name "abook*.sqlite*" -delete 2>/dev/null || true
    find "$FULL_PROFILE_DIR" -maxdepth 1 -name "history.sqlite*" -delete 2>/dev/null || true
fi

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird &" > /dev/null 2>&1
sleep 5

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if su - ga -c "DISPLAY=:1 wmctrl -l" 2>/dev/null | grep -qi "Mozilla Thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# Focus and maximize Thunderbird window
WID=$(su - ga -c "DISPLAY=:1 wmctrl -l" 2>/dev/null | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
fi

# Click center of desktop to ensure interaction state is clean
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" 2>/dev/null || true
sleep 1
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Dismiss any potential startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true

# Take initial state screenshot
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 import -window root /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="