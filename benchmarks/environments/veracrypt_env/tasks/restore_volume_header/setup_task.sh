#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Restore Volume Header Task ==="

# Define paths
VOL_DIR="/home/ga/Volumes"
MOUNT_DIR="/home/ga/MountPoints/slot1"
VOL_PATH="$VOL_DIR/critical_data.hc"
BACKUP_PATH="$VOL_DIR/header_backup_critical.dat"
SAMPLE_DATA_DIR="/workspace/assets/sample_data"
PASSWORD="DR-Restore#2024!"

# Ensure directories exist
mkdir -p "$VOL_DIR"
mkdir -p "$MOUNT_DIR"
mkdir -p "/home/ga/Documents"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the valid volume first
echo "Creating initial volume..."
veracrypt --text --create "$VOL_PATH" \
    --size=20M \
    --password="$PASSWORD" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 2. Mount and populate data
echo "Populating volume with data..."
veracrypt --text --mount "$VOL_PATH" "$MOUNT_DIR" \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Copy sample data
if [ -d "$SAMPLE_DATA_DIR" ]; then
    cp "$SAMPLE_DATA_DIR/SF312_Nondisclosure_Agreement.txt" "$MOUNT_DIR/"
    cp "$SAMPLE_DATA_DIR/FY2024_Revenue_Budget.csv" "$MOUNT_DIR/"
    cp "$SAMPLE_DATA_DIR/backup_authorized_keys" "$MOUNT_DIR/"
else
    # Fallback if sample data missing
    echo "Sample Data Agreement" > "$MOUNT_DIR/SF312_Nondisclosure_Agreement.txt"
    echo "Budget,2024,1000000" > "$MOUNT_DIR/FY2024_Revenue_Budget.csv"
    echo "ssh-rsa AAAAB3..." > "$MOUNT_DIR/backup_authorized_keys"
fi

# Create the recovery verification file
echo "VERIFIED-DR-7F3A9B2E-OK" > "$MOUNT_DIR/RECOVERY_VERIFICATION.txt"

# Sync and dismount
sync
veracrypt --text --dismount "$MOUNT_DIR" --non-interactive
sleep 1

# 3. Create the header backup (extract first 128KB)
# VeraCrypt headers are the first 131072 bytes
echo "Creating header backup..."
head -c 131072 "$VOL_PATH" > "$BACKUP_PATH"

# 4. Corrupt the volume
echo "Corrupting volume headers..."
# Corrupt primary header (first 128KB)
dd if=/dev/urandom of="$VOL_PATH" bs=1 count=131072 conv=notrunc

# Corrupt embedded backup header (last 128KB) to force external backup usage
FILE_SIZE=$(stat -c%s "$VOL_PATH")
OFFSET=$((FILE_SIZE - 131072))
dd if=/dev/urandom of="$VOL_PATH" bs=1 count=131072 seek=$OFFSET oflag=seek_bytes conv=notrunc

# 5. Verify corruption (Mount should fail)
echo "Verifying corruption..."
if veracrypt --text --mount "$VOL_PATH" "$MOUNT_DIR" --password="$PASSWORD" --pim=0 --keyfiles="" --non-interactive 2>/dev/null; then
    echo "ERROR: Volume still mountable! Corruption failed."
    veracrypt --text --dismount "$MOUNT_DIR" --non-interactive
    exit 1
else
    echo "Corruption verified: Volume cannot be mounted."
fi

# 6. Ensure VeraCrypt GUI is running for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 15
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Set permissions
chown ga:ga "$VOL_PATH"
chown ga:ga "$BACKUP_PATH"
chown ga:ga "$MOUNT_DIR"

echo "=== Setup Complete ==="