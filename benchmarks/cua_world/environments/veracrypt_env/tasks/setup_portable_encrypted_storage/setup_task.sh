#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Portable Encrypted Storage Task ==="

# 1. Clean up any previous run artifacts
echo "Cleaning up previous attempts..."
# Dismount everything first
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1
# Remove the target directory
rm -rf /home/ga/PortableDrive 2>/dev/null || true

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure VeraCrypt is running (GUI convenience for agent)
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# 4. Wait for window and focus
if wait_for_window "VeraCrypt" 15; then
    wid=$(get_veracrypt_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Maximize for visibility
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: VeraCrypt window not detected, but process might be running."
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: Create portable kit in /home/ga/PortableDrive/"