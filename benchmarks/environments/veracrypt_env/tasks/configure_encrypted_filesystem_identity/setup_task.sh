#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Filesystem Identity Task ==="

# 1. Clean up any previous run artifacts
rm -f /home/ga/Volumes/backup_tuesday.hc 2>/dev/null || true
# Ensure no lingering mounts at our verification point
veracrypt --text --dismount /tmp/vc_verify_mount --non-interactive 2>/dev/null || true
rmdir /tmp/vc_verify_mount 2>/dev/null || true

# 2. Record start time for anti-gaming (file timestamp check)
date +%s > /tmp/task_start_time.txt

# 3. Ensure VeraCrypt is running and ready
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# 4. Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 5. Open a terminal for the user (since they need CLI tools like tune2fs)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
fi

sleep 2

echo "=== Setup Complete ==="