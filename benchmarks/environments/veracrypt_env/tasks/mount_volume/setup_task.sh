#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mount Volume Task ==="

# Ensure no volumes are currently mounted
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# Record initial mount state
INITIAL_MOUNTS=$(veracrypt --text --list --non-interactive 2>&1 || echo "none")
echo "$INITIAL_MOUNTS" > /tmp/initial_mount_state.txt

# Verify the data volume exists
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "ERROR: data_volume.hc not found, recreating..."
    veracrypt --text --create /home/ga/Volumes/data_volume.hc \
        --size=20M \
        --password='MountMe2024' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive || true
fi

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

echo "=== Mount Volume Task Setup Complete ==="
