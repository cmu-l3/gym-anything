#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Key Rotation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Start VeraCrypt
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 2. Maximize and focus Window
wait_for_window "VeraCrypt" 20
WID=$(get_veracrypt_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 3. Create Compromised Keyfile
KEY_DIR="/home/ga/Keyfiles"
OLD_KEY="$KEY_DIR/lab_access_compromised.key"
mkdir -p "$KEY_DIR"
chown ga:ga "$KEY_DIR"

# Create a 64-byte random keyfile
head -c 64 /dev/urandom > "$OLD_KEY"
chown ga:ga "$OLD_KEY"

# 4. Create Volume with Password + Keyfile
VOL_PATH="/home/ga/Volumes/lab_data.hc"
PASS="Research2024!"

# Remove existing if any
rm -f "$VOL_PATH"

echo "Creating volume with keyfile protection..."
veracrypt --text --create "$VOL_PATH" \
    --size=10M \
    --password="$PASS" \
    --keyfiles="$OLD_KEY" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --random-source=/dev/urandom \
    --non-interactive

# 5. Add Data to Volume
echo "Populating volume..."
MOUNT_TMP="/tmp/vc_setup_mount"
mkdir -p "$MOUNT_TMP"
veracrypt --text --mount "$VOL_PATH" "$MOUNT_TMP" \
    --password="$PASS" \
    --keyfiles="$OLD_KEY" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

# Copy sample data
cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv "$MOUNT_TMP/experiment_results.csv"
echo "Confidential Lab Data - DO NOT LEAK" > "$MOUNT_TMP/README.txt"

# Dismount
sync
veracrypt --text --dismount "$MOUNT_TMP" --non-interactive
rmdir "$MOUNT_TMP" 2>/dev/null || true

# 6. Record Inode for Anti-Gaming Verification (In-place check)
# If the agent deletes and recreates the volume, the inode will change.
STAT_INODE=$(stat -c %i "$VOL_PATH")
echo "$STAT_INODE" > /tmp/initial_inode.txt
chown ga:ga "$VOL_PATH"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Initial Inode: $STAT_INODE"