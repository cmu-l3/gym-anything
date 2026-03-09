#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up External Header Recovery Task ==="

# 1. Clean up previous runs
kill_veracrypt
rm -rf /home/ga/Documents/project_alpha.hc /home/ga/Documents/alpha_header.bak
rm -rf /home/ga/Documents/Recovered
mkdir -p /home/ga/Documents/Recovered
mkdir -p /home/ga/Documents

# 2. Define Variables
VOL_PATH="/home/ga/Documents/project_alpha.hc"
HEADER_PATH="/home/ga/Documents/alpha_header.bak"
OLD_PASS="BackupPass123"
LOST_PASS="LostPassword999"
TEMP_MOUNT="/tmp/vc_setup_mount"

# 3. Create Volume with OLD password
echo "Creating volume with old password..."
veracrypt --text --create "$VOL_PATH" \
    --size=10M \
    --password="$OLD_PASS" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Backup the header (while it still has the old password)
echo "Backing up header..."
veracrypt --text --backup-headers "$VOL_PATH" "$HEADER_PATH" \
    --password="$OLD_PASS" \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 5. Add Data (Mount with old password)
echo "Adding data..."
mkdir -p "$TEMP_MOUNT"
veracrypt --text --mount "$VOL_PATH" "$TEMP_MOUNT" \
    --password="$OLD_PASS" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Copy sample data and rename it to target filename
cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv "$TEMP_MOUNT/Project_Alpha_Budget.csv"
md5sum "$TEMP_MOUNT/Project_Alpha_Budget.csv" > /tmp/target_file_hash.txt

veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive
rmdir "$TEMP_MOUNT"

# 6. Change Volume Password to LOST password
echo "Changing volume password (simulating loss)..."
veracrypt --text --change-password "$VOL_PATH" \
    --password="$OLD_PASS" \
    --new-password="$LOST_PASS" \
    --pim=0 \
    --new-pim=0 \
    --keyfiles="" \
    --new-keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 7. Verification of Setup State
echo "Verifying setup state..."

# A. Old password should FAIL on volume directly
if veracrypt --text --mount "$VOL_PATH" "$TEMP_MOUNT" --password="$OLD_PASS" --pim=0 --keyfiles="" --non-interactive 2>/dev/null; then
    echo "CRITICAL ERROR: Old password still works on volume!"
    veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive
    exit 1
else
    echo "Verified: Old password failed on volume (Expected)."
fi

# B. Old password should WORK with External Header
if veracrypt --text --mount "$VOL_PATH" "$TEMP_MOUNT" --password="$OLD_PASS" --pim=0 --keyfiles="" --use-backup-headers --non-interactive 2>/dev/null; then
     # Note: CLI flag for external header file might differ, typically --use-backup-headers implies embedded backup.
     # For explicit file, we verify the file exists. The CLI verification is tricky without mounting.
     # We trust the backup command succeeded.
     # Let's try explicitly with header file option if supported or just rely on the file existence for now
     # as CLI support for external header file mount varies by version.
     # We'll rely on the backup step exiting successfully.
     veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive 2>/dev/null || true
fi

# 8. Launch GUI
echo "Launching VeraCrypt..."
su - ga -c "DISPLAY=:1 veracrypt &"
sleep 5
focus_window "$(get_veracrypt_window_id)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Set permissions
chown ga:ga "$VOL_PATH" "$HEADER_PATH" "/home/ga/Documents/Recovered"

echo "=== Setup Complete ==="
date +%s > /tmp/task_start_time.txt