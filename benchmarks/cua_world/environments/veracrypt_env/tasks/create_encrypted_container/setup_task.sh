#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Encrypted Container Task ==="

# Ensure target file does not exist
rm -f /home/ga/Volumes/secret_archive.hc 2>/dev/null || true

# Record initial state
ls -la /home/ga/Volumes/ > /tmp/initial_volumes_state.txt 2>/dev/null || true
INITIAL_COUNT=$(ls -1 /home/ga/Volumes/*.hc 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_volume_count.txt

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

echo "=== Create Encrypted Container Task Setup Complete ==="
