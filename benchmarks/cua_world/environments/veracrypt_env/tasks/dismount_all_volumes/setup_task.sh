#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Dismount All Volumes Task ==="

# First dismount everything clean
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# Mount two volumes so the agent has something to dismount

# Mount test_volume.hc
echo "Mounting test_volume.hc..."
veracrypt --text --mount /home/ga/Volumes/test_volume.hc /media/veracrypt1 \
    --password='OldPassword123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --slot=1 \
    --non-interactive 2>/dev/null || true
sleep 1

# Mount mounted_volume.hc
echo "Mounting mounted_volume.hc..."
veracrypt --text --mount /home/ga/Volumes/mounted_volume.hc /media/veracrypt2 \
    --password='DismountMe123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --slot=2 \
    --non-interactive 2>/dev/null || true
sleep 1

# Record initial mount state
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
echo "$MOUNT_LIST" > /tmp/initial_mount_state.txt
INITIAL_MOUNTED=$(echo "$MOUNT_LIST" | grep -c "^[0-9]" 2>/dev/null || echo "0")
echo "$INITIAL_MOUNTED" > /tmp/initial_mounted_count.txt

echo "Initially mounted volumes: $INITIAL_MOUNTED"
echo "$MOUNT_LIST"

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

echo "=== Dismount All Volumes Task Setup Complete ==="
