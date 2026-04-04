#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Ext4 Permissions Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# clean up previous runs
rm -f /home/ga/Volumes/sysadmin_vault.hc
rm -f /tmp/task_result.json

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Ensure window is visible and maximized
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="