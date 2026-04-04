#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up mount_with_keyfile task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous state
echo "Cleaning up..."
veracrypt --text --dismount /home/ga/MountPoints/slot1 --non-interactive 2>/dev/null || true
rm -f /home/ga/Documents/volume_contents.txt 2>/dev/null || true
rm -rf /home/ga/MountPoints/slot1/* 2>/dev/null || true
rm -f /home/ga/Volumes/secure_finance.hc 2>/dev/null || true
rm -f /home/ga/Keyfiles/finance_key.dat 2>/dev/null || true

# 2. Create the keyfile
echo "Creating keyfile..."
mkdir -p /home/ga/Keyfiles
# Create a 64-byte random keyfile
dd if=/dev/urandom of=/home/ga/Keyfiles/finance_key.dat bs=64 count=1 2>/dev/null
chmod 600 /home/ga/Keyfiles/finance_key.dat
chown ga:ga /home/ga/Keyfiles/finance_key.dat

# 3. Create the encrypted volume with password + keyfile
echo "Creating dual-factor encrypted volume..."
mkdir -p /home/ga/Volumes

# Note: Using --random-source=/dev/urandom for speed in non-interactive mode
veracrypt --text --create /home/ga/Volumes/secure_finance.hc \
    --size=15M \
    --password='Quarterly2024!' \
    --keyfiles='/home/ga/Keyfiles/finance_key.dat' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Mount temporarily to populate with data
echo "Populating volume with data..."
mkdir -p /tmp/vc_setup_mount

veracrypt --text --mount /home/ga/Volumes/secure_finance.hc /tmp/vc_setup_mount \
    --password='Quarterly2024!' \
    --keyfiles='/home/ga/Keyfiles/finance_key.dat' \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

# Copy sample data
if mountpoint -q /tmp/vc_setup_mount; then
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup_mount/
    
    # Ensure data is flushed to disk
    sync
    ls -la /tmp/vc_setup_mount/
else
    echo "ERROR: Failed to mount volume for data population"
    exit 1
fi

# Dismount
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive 2>/dev/null || true
rmdir /tmp/vc_setup_mount 2>/dev/null || true

# 5. Verify the volume requires the keyfile (sanity check)
echo "Verifying security..."
if veracrypt --text --mount /home/ga/Volumes/secure_finance.hc /tmp/vc_setup_mount \
    --password='Quarterly2024!' \
    --keyfiles='' \
    --pim=0 \
    --non-interactive 2>/dev/null; then
    echo "ERROR: Volume mounted without keyfile! Setup failed."
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive 2>/dev/null || true
    exit 1
else
    echo "Verification passed: Volume rejected password-only auth."
fi

# 6. Prepare environment for agent
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Keyfiles
chown -R ga:ga /home/ga/Documents

# 7. Start VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Maximize and focus
wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# 8. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="