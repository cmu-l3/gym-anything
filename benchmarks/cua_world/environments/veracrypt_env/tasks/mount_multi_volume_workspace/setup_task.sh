#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Multi-Volume Workspace Task ==="

# 1. Start fresh - dismount everything
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# 2. Setup Workspace directories
mkdir -p /home/ga/Workspace/project_alpha
mkdir -p /home/ga/Workspace/project_beta
mkdir -p /home/ga/Workspace/project_gamma
rm -f /home/ga/Workspace/mount_manifest.txt

# 3. Create dummy asset files if they don't exist (in case assets dir is empty)
mkdir -p /tmp/assets_prep
echo "INCIDENT REPORT 2024 - CONFIDENTIAL" > /tmp/assets_prep/incident_report_2024.txt
echo "NETWORK TOPOLOGY - INTERNAL USE ONLY" > /tmp/assets_prep/network_topology.txt

# 4. Prepare Volumes
# We need to inject specific files into test_volume and mounted_volume
# data_volume is already populated by environment setup, but we'll double check

# Prepare test_volume.hc (project_alpha)
echo "Preparing test_volume.hc..."
if [ ! -f /home/ga/Volumes/test_volume.hc ]; then
    # Recreate if missing
    veracrypt --text --create /home/ga/Volumes/test_volume.hc \
        --size=10M --password='OldPassword123' --encryption=AES --hash=SHA-512 \
        --filesystem=FAT --pim=0 --keyfiles="" --random-source=/dev/urandom --non-interactive
fi

mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/test_volume.hc /tmp/vc_setup_mount \
    --password='OldPassword123' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive
if mountpoint -q /tmp/vc_setup_mount; then
    cp /tmp/assets_prep/incident_report_2024.txt /tmp/vc_setup_mount/
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
fi

# Prepare mounted_volume.hc (project_gamma)
echo "Preparing mounted_volume.hc..."
if [ ! -f /home/ga/Volumes/mounted_volume.hc ]; then
    veracrypt --text --create /home/ga/Volumes/mounted_volume.hc \
        --size=10M --password='DismountMe123' --encryption=AES --hash=SHA-512 \
        --filesystem=FAT --pim=0 --keyfiles="" --random-source=/dev/urandom --non-interactive
fi

veracrypt --text --mount /home/ga/Volumes/mounted_volume.hc /tmp/vc_setup_mount \
    --password='DismountMe123' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive
if mountpoint -q /tmp/vc_setup_mount; then
    cp /tmp/assets_prep/network_topology.txt /tmp/vc_setup_mount/
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
fi

# cleanup setup mount
rmdir /tmp/vc_setup_mount 2>/dev/null || true
rm -rf /tmp/assets_prep

# 5. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi
wait_for_window "VeraCrypt" 20
maximize_window "VeraCrypt" 2>/dev/null || true

# 6. Record Anti-Gaming Data
date +%s > /tmp/task_start_time.txt
veracrypt --text --list --non-interactive > /tmp/initial_mount_list.txt 2>&1 || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="