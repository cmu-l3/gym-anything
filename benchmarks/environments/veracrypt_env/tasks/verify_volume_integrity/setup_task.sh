#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Volume Integrity Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data_volume.hc exists (created during env setup)
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "ERROR: data_volume.hc not found, recreating..."
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
    
    # Populate with data
    mkdir -p /tmp/vc_setup_mount
    veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_setup_mount \
        --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive
    
    if mountpoint -q /tmp/vc_setup_mount; then
        cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/
        cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/
        cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup_mount/
        veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
    fi
    rmdir /tmp/vc_setup_mount 2>/dev/null || true
fi

# Remove any previous report or leftovers
rm -f /home/ga/Volumes/integrity_report.txt
rm -f /home/ga/Volumes/integrity_manifest.sha256

# Dismount any existing mounts at slot1 to ensure clean state
veracrypt --text --dismount /home/ga/MountPoints/slot1 --non-interactive 2>/dev/null || true
sleep 1

# Generate the integrity manifest by mounting the volume
echo "Generating integrity manifest..."
mkdir -p /tmp/vc_manifest_tmp
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_manifest_tmp \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive 2>/dev/null

sleep 2

if mountpoint -q /tmp/vc_manifest_tmp 2>/dev/null; then
    # Compute SHA-256 checksums for all files
    cd /tmp/vc_manifest_tmp
    sha256sum * > /home/ga/Volumes/integrity_manifest.sha256 2>/dev/null
    cd /
    
    echo "Manifest generated:"
    cat /home/ga/Volumes/integrity_manifest.sha256
    
    # Store ground truth checksums for verifier (hidden)
    mkdir -p /var/lib/veracrypt_ground_truth
    cp /home/ga/Volumes/integrity_manifest.sha256 /var/lib/veracrypt_ground_truth/
    chmod 700 /var/lib/veracrypt_ground_truth
    
    # Dismount
    veracrypt --text --dismount /tmp/vc_manifest_tmp --non-interactive 2>/dev/null || true
else
    echo "ERROR: Could not mount data_volume for manifest generation"
fi
rmdir /tmp/vc_manifest_tmp 2>/dev/null || true

# Set permissions for agent
chown ga:ga /home/ga/Volumes/integrity_manifest.sha256

# Ensure VeraCrypt GUI is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Focus and maximize
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="