#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Volume for Distribution Task ==="

# 1. Clean up previous run artifacts
echo "Cleaning up..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/financial_transfer.hc 2>/dev/null || true
rm -f /home/ga/Volumes/data_volume.hc 2>/dev/null || true
rm -rf /home/ga/MountPoints/slot1/* 2>/dev/null || true

# 2. Create the Master Volume (data_volume.hc)
echo "Creating master volume..."
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

# 3. Populate Master Volume with Data
echo "Populating master volume..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_setup_mount \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Check mount success
if mountpoint -q /tmp/vc_setup_mount; then
    # Copy sample data
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/ 2>/dev/null || echo "Budget data missing"
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/ 2>/dev/null || echo "NDA missing"
    
    # Create a unique identifier file to verify cloning later
    echo "MasterID: $(date +%s)" > /tmp/vc_setup_mount/master_id.txt
    
    echo "Data populated."
    ls -la /tmp/vc_setup_mount/
    
    # Dismount
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
    rmdir /tmp/vc_setup_mount
else
    echo "ERROR: Failed to mount master volume for population."
    exit 1
fi

# 4. Set Permissions
chown ga:ga /home/ga/Volumes/data_volume.hc
chmod 600 /home/ga/Volumes/data_volume.hc

# 5. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Volumes/data_volume.hc > /tmp/master_creation_time.txt

# 6. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

# Wait and Focus
wait_for_window "VeraCrypt" 15
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="