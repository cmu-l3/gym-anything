#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Keyfile Task ==="

# Remove any existing keyfile at the target path
rm -f /home/ga/Keyfiles/my_keyfile.key 2>/dev/null || true

# Record initial state of keyfiles directory
INITIAL_COUNT=$(ls -1 /home/ga/Keyfiles/ 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_keyfile_count.txt
ls -la /home/ga/Keyfiles/ > /tmp/initial_keyfiles_state.txt 2>/dev/null || true

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

echo "=== Create Keyfile Task Setup Complete ==="
