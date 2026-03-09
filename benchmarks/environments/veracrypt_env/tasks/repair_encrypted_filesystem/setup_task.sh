#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Encrypted Filesystem Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
rm -rf /home/ga/Documents/recovered
mkdir -p /home/ga/Documents/recovered
chown ga:ga /home/ga/Documents/recovered
rm -f /home/ga/Volumes/broken_drive.hc

# 2. Create the content file locally first to calculate hash
cat > /tmp/investigation_notes.txt << EOF
CONFIDENTIAL INVESTIGATION NOTES
DATE: 2024-03-15
CASE: PROJECT SKYLARK

Source "DeepThroat" confirmed the leakage happens at the api gateway.
The encryption keys were never rotated since 2019.
Meeting scheduled at the docks for next Tuesday.
Don't trust the administrator.

END OF FILE
EOF
# md5sum of this file is e5828c564f71fea3a12dac8c643933f8

# 3. Create a fresh VeraCrypt volume (FAT format)
echo "Creating volume..."
veracrypt --text --create /home/ga/Volumes/broken_drive.hc \
    --size=50M \
    --password='Journalist2024!' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Mount it to add data
echo "Populating volume..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/broken_drive.hc /tmp/vc_setup_mount \
    --password='Journalist2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Copy the file
cp /tmp/investigation_notes.txt /tmp/vc_setup_mount/
sync

# Dismount
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
rmdir /tmp/vc_setup_mount

# 5. Corrupt the filesystem
# We mount with --filesystem=none to get the block device, then zero the boot signature
echo "Corrupting filesystem..."
veracrypt --text --mount /home/ga/Volumes/broken_drive.hc \
    --password='Journalist2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --filesystem=none \
    --non-interactive

# Find the mapped device (usually /dev/mapper/veracrypt1 if slot 1)
# We assume it's the most recently created mapper device for veracrypt
MAPPER_DEV=$(ls -t /dev/mapper/veracrypt* 2>/dev/null | head -1)

if [ -z "$MAPPER_DEV" ]; then
    echo "ERROR: Could not find mapped device for corruption."
    exit 1
fi

echo "Corrupting device: $MAPPER_DEV"
# Zero out the boot signature (bytes 510 and 511)
# This usually breaks 'mount' but is easily fixable by 'fsck' (restoring from backup boot sector)
dd if=/dev/zero of="$MAPPER_DEV" bs=1 count=2 seek=510 conv=notrunc

# Dismount the corrupted volume
veracrypt --text --dismount "$MAPPER_DEV" --non-interactive

# 6. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wmctrl -a "VeraCrypt" 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="