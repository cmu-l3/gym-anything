#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Rotate Compromised Credentials Task ==="

# 1. Clean up previous runs
echo "Cleaning up..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/project_omega.hc 2>/dev/null
rm -f /home/ga/Pictures/server_rack_001.jpg 2>/dev/null
rm -f /home/ga/Keyfiles/omega_v2.key 2>/dev/null
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/Pictures
mkdir -p /home/ga/Keyfiles
mkdir -p /var/lib/veracrypt_task

# 2. Create the "compromised" keyfile (simulated as an image)
echo "Creating compromised keyfile..."
dd if=/dev/urandom of=/home/ga/Pictures/server_rack_001.jpg bs=1 count=2048 2>/dev/null
# Save a backup for verification later (hidden from agent)
cp /home/ga/Pictures/server_rack_001.jpg /var/lib/veracrypt_task/backup_old.key

# 3. Create the volume with Old Password + Old Keyfile
echo "Creating project_omega.hc..."
# Note: PIM=0 is default.
veracrypt --text --create /home/ga/Volumes/project_omega.hc \
    --size=20M \
    --password='OmegaStart2023' \
    --keyfiles='/home/ga/Pictures/server_rack_001.jpg' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Populate volume with sensitive data
echo "Populating volume..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/project_omega.hc /tmp/vc_setup_mount \
    --password='OmegaStart2023' \
    --keyfiles='/home/ga/Pictures/server_rack_001.jpg' \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mount; then
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/CONFIDENTIAL_NDA.txt 2>/dev/null || true
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/Project_Omega_Budget.csv 2>/dev/null || true
    echo "Secret Project Omega Blueprint Data" > /tmp/vc_setup_mount/blueprint.dat
    sleep 1
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
else
    echo "ERROR: Failed to mount volume for population!"
    exit 1
fi
rmdir /tmp/vc_setup_mount 2>/dev/null || true

# 5. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
focus_window "$(get_veracrypt_window_id)"

# 6. Record timestamps and state
date +%s > /tmp/task_start_time.txt
ls -l /home/ga/Volumes/project_omega.hc > /tmp/initial_volume_state.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="