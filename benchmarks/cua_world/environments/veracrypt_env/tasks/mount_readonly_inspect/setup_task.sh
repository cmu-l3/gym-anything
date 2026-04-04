#!/bin/bash
# NOTE: Do not use set -e - VeraCrypt CLI may return non-zero even on success

echo "=== Setting up mount_readonly_inspect task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure data_volume.hc exists
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "ERROR: data_volume.hc does not exist! Recreating..."
    veracrypt --text --create /home/ga/Volumes/data_volume.hc \
    --size=20M \
    --password='MountMe2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive || true
fi

# Dismount any currently mounted volumes to start clean
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 2

# Verify the volume is not mounted
if mount | grep -q "/home/ga/MountPoints/slot1"; then
    echo "WARNING: slot1 still mounted, force unmount..."
    umount -f /home/ga/MountPoints/slot1 2>/dev/null || true
    sleep 1
fi

# Clean mount point directory
rm -rf /home/ga/MountPoints/slot1/*
mkdir -p /home/ga/MountPoints/slot1

# Create Documents directory and clean up output file
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/volume_inventory.txt

# Verify the volume is mountable and has content (sanity check)
echo "Verifying data_volume.hc integrity..."
mkdir -p /tmp/vc_sanity_check
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_sanity_check \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive 2>&1
MOUNT_EXIT=$?

if mountpoint -q /tmp/vc_sanity_check 2>/dev/null; then
    # Populate data if empty (just in case recreation failed or was empty)
    if [ -z "$(ls -A /tmp/vc_sanity_check)" ]; then
        echo "Populating empty volume..."
        cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_sanity_check/ 2>/dev/null || touch /tmp/vc_sanity_check/SF312_Nondisclosure_Agreement.txt
        cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_sanity_check/ 2>/dev/null || touch /tmp/vc_sanity_check/FY2024_Revenue_Budget.csv
        cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_sanity_check/ 2>/dev/null || touch /tmp/vc_sanity_check/backup_authorized_keys
        sync
    fi
    
    # Record expected content for verification (optional debugging)
    ls -la /tmp/vc_sanity_check/ > /tmp/expected_volume_contents.txt
    
    veracrypt --text --dismount /tmp/vc_sanity_check --non-interactive 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Sanity check mount failed (exit=$MOUNT_EXIT)"
fi
rmdir /tmp/vc_sanity_check 2>/dev/null || true

# Ensure VeraCrypt GUI is running
if ! pgrep -f "veracrypt" > /dev/null; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Maximize and focus VeraCrypt window
sleep 2
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="