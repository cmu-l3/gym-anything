#!/bin/bash
set -e
echo "=== Setting up migrate_volume_twofish task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Dismount everything
echo "Dismounting any existing volumes..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# Cleanup previous artifacts
rm -f /home/ga/Volumes/twofish_volume.hc 2>/dev/null || true
rm -f /home/ga/Documents/migration_manifest.txt 2>/dev/null || true
rm -rf /home/ga/MountPoints/slot1 /home/ga/MountPoints/slot2
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /home/ga/MountPoints/slot2
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Volumes /home/ga/MountPoints /home/ga/Documents

# Verify source volume exists; if not, recreate it (using setup logic)
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "Recreating source volume..."
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
    
    # Populate source volume
    mkdir -p /tmp/vc_populate
    veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_populate \
        --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive
    
    if mountpoint -q /tmp/vc_populate; then
        cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_populate/
        cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_populate/
        cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_populate/
        sync
        veracrypt --text --dismount /tmp/vc_populate --non-interactive
    fi
    rmdir /tmp/vc_populate 2>/dev/null || true
fi

# Record ground truth (file sizes) from source volume
echo "Recording ground truth data..."
mkdir -p /var/lib/veracrypt_ground_truth
mkdir -p /tmp/vc_check
if veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_check \
    --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive; then
    
    rm -f /var/lib/veracrypt_ground_truth/source_files.json
    # Create JSON with filenames and sizes
    python3 -c "import os, json; 
files = {f: os.path.getsize(os.path.join('/tmp/vc_check', f)) for f in os.listdir('/tmp/vc_check') if os.path.isfile(os.path.join('/tmp/vc_check', f))};
print(json.dumps(files))" > /var/lib/veracrypt_ground_truth/source_files.json
    
    veracrypt --text --dismount /tmp/vc_check --non-interactive
else
    echo "ERROR: Failed to mount source volume for ground truth generation"
fi
rmdir /tmp/vc_check 2>/dev/null || true

# Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_window "$(get_veracrypt_window_id)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="