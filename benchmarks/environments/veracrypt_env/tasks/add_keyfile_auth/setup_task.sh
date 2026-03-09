#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Keyfile Auth Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous state
echo "Cleaning up previous state..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Keyfiles/* 2>/dev/null || true
rm -f /home/ga/Documents/volume_contents.txt 2>/dev/null || true
mkdir -p /home/ga/Keyfiles
mkdir -p /home/ga/Documents
mkdir -p /home/ga/MountPoints/slot1

# 2. Recreate the data volume to ensure known starting state (Password only)
echo "Recreating data_volume.hc..."
rm -f /home/ga/Volumes/data_volume.hc 2>/dev/null || true
veracrypt --text --create /home/ga/Volumes/data_volume.hc \
    --size=20M \
    --password='MountMe2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Populate volume with data
echo "Populating volume with data..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_setup_mount \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mount; then
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup_mount/
    sync
    sleep 1
    # Calculate checksums of original data for later verification
    md5sum /tmp/vc_setup_mount/* > /tmp/original_data_checksums.txt 2>/dev/null || true
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
else
    echo "ERROR: Failed to mount volume for data population"
    exit 1
fi
rmdir /tmp/vc_setup_mount 2>/dev/null || true

# Record original volume stats
stat --format='%s %Y' /home/ga/Volumes/data_volume.hc > /tmp/original_volume_stat.txt

# 4. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 5. Position Window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="