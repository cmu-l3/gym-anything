#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Decommission Task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -rf /home/ga/Documents/DecryptedExport 2>/dev/null || true
rm -f /home/ga/Documents/decommission_report.txt 2>/dev/null || true
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 3. Create the encrypted volume with sample data
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
MOUNT_POINT="/tmp/vc_setup_mount"

echo "Creating encrypted volume at $VOLUME_PATH..."
# Create volume
veracrypt --text --create "$VOLUME_PATH" \
    --size=20M \
    --password='MountMe2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# Mount to populate
mkdir -p "$MOUNT_POINT"
veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Copy sample data
echo "Populating volume..."
cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt "$MOUNT_POINT/"
cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv "$MOUNT_POINT/"
cp /workspace/assets/sample_data/backup_authorized_keys "$MOUNT_POINT/"

# Dismount
veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
rmdir "$MOUNT_POINT" 2>/dev/null || true

# 4. Create directories required for task
mkdir -p /home/ga/Documents
mkdir -p /home/ga/MountPoints/slot1
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Volumes

# 5. Ensure VeraCrypt GUI is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 6. Maximize window for visibility
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="