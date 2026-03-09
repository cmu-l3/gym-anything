#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up backup_volume_header task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure no volumes are currently mounted
echo "Dismounting any mounted volumes..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 2

# Remove any pre-existing backup file (clean state)
rm -f /home/ga/Volumes/data_volume_header_backup.bin 2>/dev/null || true
rm -f /home/ga/Volumes/*.backup 2>/dev/null || true

# Verify the source volume exists
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "ERROR: data_volume.hc not found! Attempting to recreate..."
    veracrypt --text --create /home/ga/Volumes/data_volume.hc \
        --size=20M \
        --password='MountMe2024' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles='' \
        --random-source=/dev/urandom \
        --non-interactive
fi

# Record the original volume's checksum for integrity verification
sha256sum /home/ga/Volumes/data_volume.hc > /tmp/original_volume_checksum.txt

# Verify the volume is valid by attempting a quick mount/dismount
echo "Verifying source volume is valid..."
mkdir -p /tmp/vc_verify_setup
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_verify_setup \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive 2>&1

if mountpoint -q /tmp/vc_verify_setup 2>/dev/null; then
    echo "Source volume verified."
    veracrypt --text --dismount /tmp/vc_verify_setup --non-interactive 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not verify source volume mount"
fi
rmdir /tmp/vc_verify_setup 2>/dev/null || true

# Ensure VeraCrypt GUI is running
if ! pgrep -f "veracrypt" > /dev/null; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Wait for VeraCrypt window
wait_for_window "VeraCrypt" 30

# Maximize and focus VeraCrypt
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true
sleep 1

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "Source volume: /home/ga/Volumes/data_volume.hc"
echo "Expected backup: /home/ga/Volumes/data_volume_header_backup.bin"
echo "=== Task setup complete ==="