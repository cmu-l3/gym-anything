#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Reformat Volume Filesystem Task ==="

# 1. Clean state: Dismount everything
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# 2. Verify volume exists (should be created by env setup, but ensure it)
VOL_PATH="/home/ga/Volumes/data_volume.hc"
if [ ! -f "$VOL_PATH" ]; then
    echo "Creating data volume..."
    veracrypt --text --create "$VOL_PATH" \
        --size=20M \
        --password='MountMe2024' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles='' \
        --random-source=/dev/urandom \
        --non-interactive
    
    # Mount and add data
    mkdir -p /tmp/vc_setup
    veracrypt --text --mount "$VOL_PATH" /tmp/vc_setup \
        --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive
    
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup/
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup/
    cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup/
    
    veracrypt --text --dismount /tmp/vc_setup --non-interactive
    rmdir /tmp/vc_setup
fi

# 3. Compute Ground Truth (Hidden from agent)
TRUTH_DIR="/var/lib/veracrypt_task"
mkdir -p "$TRUTH_DIR"
chmod 700 "$TRUTH_DIR" # Only root can read

echo "Computing ground truth checksums..."
mkdir -p /tmp/vc_gt
veracrypt --text --mount "$VOL_PATH" /tmp/vc_gt \
    --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive

if mountpoint -q /tmp/vc_gt; then
    cd /tmp/vc_gt
    md5sum * > "$TRUTH_DIR/original_checksums.md5"
    ls -la > "$TRUTH_DIR/original_listing.txt"
    cd /
    veracrypt --text --dismount /tmp/vc_gt --non-interactive
else
    echo "ERROR: Failed to mount volume for setup!"
    exit 1
fi
rmdir /tmp/vc_gt

# 4. Record Timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Application
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 6. Window Management
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="