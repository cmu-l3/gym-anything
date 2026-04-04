#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Upgrade Volume Security Task ==="

# Define paths
VOLUME_PATH="/home/ga/Volumes/legacy_project.hc"
MOUNT_POINT="/tmp/vc_setup_mount"

# Clean up any existing volume
rm -f "$VOLUME_PATH" 2>/dev/null || true
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 1. Create the legacy volume with SHA-256 and PIM 485
echo "Creating legacy volume with SHA-256 and PIM 485..."
# Note: --pim switch sets the PIM. --hash sets the PRF.
if veracrypt --text --create "$VOLUME_PATH" \
    --size=20M \
    --password='UpgradeMe2024' \
    --pim=485 \
    --encryption=AES \
    --hash=SHA-256 \
    --filesystem=FAT \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive; then
    echo "Volume created successfully."
else
    echo "ERROR: Failed to create legacy volume."
    exit 1
fi

# 2. Mount the volume to populate data
echo "Mounting to add data..."
mkdir -p "$MOUNT_POINT"
if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password='UpgradeMe2024' \
    --pim=485 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive; then
    
    # Create dummy project files
    echo "Project Requirements v1.0 - CONFIDENTIAL" > "$MOUNT_POINT/project_requirements.txt"
    echo "Item,Cost" > "$MOUNT_POINT/budget_v1.csv"
    echo "Server,5000" >> "$MOUNT_POINT/budget_v1.csv"
    echo "License,1200" >> "$MOUNT_POINT/budget_v1.csv"
    
    # Calculate checksums for verification later
    md5sum "$MOUNT_POINT/project_requirements.txt" "$MOUNT_POINT/budget_v1.csv" > /tmp/original_checksums.md5
    
    echo "Data added."
    ls -la "$MOUNT_POINT"
    
    # Dismount
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
    rmdir "$MOUNT_POINT"
else
    echo "ERROR: Failed to mount legacy volume for setup."
    exit 1
fi

# 3. Ensure VeraCrypt GUI is running and ready
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="