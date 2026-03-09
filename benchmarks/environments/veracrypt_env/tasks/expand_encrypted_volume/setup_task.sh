#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Expand Encrypted Volume Task ==="

# Define paths
VOLUME_PATH="/home/ga/Volumes/project_archive.hc"
MOUNT_POINT="/tmp/vc_setup_mount"
CHECKSUM_FILE="/var/lib/veracrypt_task/original_checksums.txt"

# 1. Clean up any previous state
rm -f "$VOLUME_PATH" 2>/dev/null || true
rm -f "/home/ga/Documents/expansion_report.txt" 2>/dev/null || true
mkdir -p /var/lib/veracrypt_task

# 2. Create the initial 10MB volume
echo "Creating initial 10MB volume..."
veracrypt --text --create "$VOLUME_PATH" \
    --size=10M \
    --password='ArchivePass2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Mount and populate with data
echo "Populating volume with data..."
mkdir -p "$MOUNT_POINT"
veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password='ArchivePass2024' --pim=0 --keyfiles='' \
    --protect-hidden=no --non-interactive

# Copy sample data
cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt "$MOUNT_POINT/"
cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv "$MOUNT_POINT/"
cp /workspace/assets/sample_data/backup_authorized_keys "$MOUNT_POINT/"

# 4. Generate Ground Truth Checksums (calculate relative to mount root)
echo "Generating integrity checksums..."
cd "$MOUNT_POINT"
sha256sum SF312_Nondisclosure_Agreement.txt > "$CHECKSUM_FILE"
sha256sum FY2024_Revenue_Budget.csv >> "$CHECKSUM_FILE"
sha256sum backup_authorized_keys >> "$CHECKSUM_FILE"
cd /

# Secure the checksum file
chmod 644 "$CHECKSUM_FILE" # Readable for export script later

# 5. Dismount
veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
rmdir "$MOUNT_POINT" 2>/dev/null || true

# 6. Record Initial State
INITIAL_SIZE=$(stat -c%s "$VOLUME_PATH")
echo "$INITIAL_SIZE" > /tmp/initial_volume_size.txt
date +%s > /tmp/task_start_time.txt

# 7. Launch VeraCrypt GUI for the agent
echo "Launching VeraCrypt..."
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Create Documents directory if not exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Volume created at: $VOLUME_PATH"
echo "Initial size: $((INITIAL_SIZE/1024/1024))MB"