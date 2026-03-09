#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Cryptographic Erasure Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

VOLUME_PATH="/home/ga/Volumes/investigation_data.hc"
MOUNT_POINT="/tmp/vc_setup_mount"

# 1. Create the VeraCrypt volume (20MB)
# We use a fixed password for setup, agent doesn't necessarily need it to wipe, 
# but it's good context: 'FreePress2024'
echo "Creating investigation volume..."
rm -f "$VOLUME_PATH" 2>/dev/null
veracrypt --text --create "$VOLUME_PATH" \
    --size=20M \
    --password='FreePress2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 2. Add some dummy data to make it realistic
echo "Populating volume with data..."
mkdir -p "$MOUNT_POINT"
veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password='FreePress2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q "$MOUNT_POINT"; then
    # Create the sensitive file
    cat > "$MOUNT_POINT/source_list.txt" << EOF
CONFIDENTIAL SOURCE LIST - DO NOT DISTRIBUTE
============================================
1. Deep Throat II - 555-0199
2. The Whistleblower - 555-0123
3. Project Blue Book Contact - 555-0988
EOF
    # Ensure data is written
    sync
    sleep 1
    # Dismount
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
else
    echo "ERROR: Failed to mount volume for population"
    exit 1
fi
rmdir "$MOUNT_POINT" 2>/dev/null

# 3. Capture Baseline State (CRITICAL for verification)
# We need to know what the valid headers look like (or their hashes) to prove they changed
echo "Capturing baseline header hashes..."

# Primary Header: First 128KB (131072 bytes)
head -c 131072 "$VOLUME_PATH" > /tmp/original_primary_header.bin
sha256sum /tmp/original_primary_header.bin | cut -d' ' -f1 > /tmp/original_primary_hash.txt

# Backup Header: Last 128KB
# Calculate offset: 20MB = 20971520 bytes. 
# Last 128KB starts at 20971520 - 131072 = 20840448
tail -c 131072 "$VOLUME_PATH" > /tmp/original_backup_header.bin
sha256sum /tmp/original_backup_header.bin | cut -d' ' -f1 > /tmp/original_backup_hash.txt

# File size
stat -c%s "$VOLUME_PATH" > /tmp/original_size.txt

# ensure permissions
chown ga:ga "$VOLUME_PATH"
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Volume created at: $VOLUME_PATH"
echo "Original Size: $(cat /tmp/original_size.txt)"
echo "Primary Hash: $(cat /tmp/original_primary_hash.txt)"
echo "Backup Hash: $(cat /tmp/original_backup_hash.txt)"