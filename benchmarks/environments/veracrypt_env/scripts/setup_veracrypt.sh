#!/bin/bash
# NOTE: Do not use set -e here - VeraCrypt CLI may return non-zero even on success

echo "=== Setting up VeraCrypt ==="

# Wait for desktop to be ready
sleep 5

# Create a pre-existing encrypted container for tasks that need one
# This 10MB container uses AES/SHA-512 with password "OldPassword123"
echo "Creating pre-existing test volume..."
veracrypt --text --create /home/ga/Volumes/test_volume.hc \
    --size=10M \
    --password='OldPassword123' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive
echo "test_volume.hc creation exit code: $?"

# Verify the volume was created
if [ -f /home/ga/Volumes/test_volume.hc ]; then
    echo "Test volume created successfully at /home/ga/Volumes/test_volume.hc"
    ls -la /home/ga/Volumes/test_volume.hc
else
    echo "WARNING: Test volume creation may have failed"
fi

# Verify the test volume can be mounted (quick sanity check)
echo "Verifying test_volume.hc is mountable..."
mkdir -p /tmp/vc_verify_tmp
veracrypt --text --mount /home/ga/Volumes/test_volume.hc /tmp/vc_verify_tmp \
    --password='OldPassword123' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive 2>&1 && echo "VERIFY: test_volume mounts OK" || echo "VERIFY: test_volume mount FAILED"
veracrypt --text --dismount /tmp/vc_verify_tmp --non-interactive 2>/dev/null || true
rmdir /tmp/vc_verify_tmp 2>/dev/null || true
sleep 1

# Create a second pre-existing volume for mount tasks
echo "Creating mount test volume with sample data..."
veracrypt --text --create /home/ga/Volumes/data_volume.hc \
    --size=20M \
    --password='MountMe2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive
echo "data_volume.hc creation exit code: $?"

# Mount, add sample data, then dismount
if [ -f /home/ga/Volumes/data_volume.hc ]; then
    echo "Adding sample data to data_volume..."
    mkdir -p /tmp/vc_mount_tmp
    veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_mount_tmp \
        --password='MountMe2024' \
        --pim=0 \
        --keyfiles='' \
        --protect-hidden=no \
        --non-interactive
    echo "data_volume mount exit code: $?"

    # Add real-world sample files to the encrypted volume
    if mountpoint -q /tmp/vc_mount_tmp 2>/dev/null; then
        cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_mount_tmp/
        cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_mount_tmp/
        cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_mount_tmp/
        echo "Real-world sample data added to encrypted volume"
        ls -la /tmp/vc_mount_tmp/
        sync
        sleep 2
    else
        echo "WARNING: data_volume mount point not detected as mounted"
    fi

    # Dismount
    veracrypt --text --dismount /tmp/vc_mount_tmp --non-interactive 2>/dev/null || true
    sleep 1
    rmdir /tmp/vc_mount_tmp 2>/dev/null || true
fi

# Create a third volume for dismount tasks (will be mounted in pre_task)
echo "Creating volume for dismount tasks..."
veracrypt --text --create /home/ga/Volumes/mounted_volume.hc \
    --size=10M \
    --password='DismountMe123' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive
echo "mounted_volume.hc creation exit code: $?"

# Fix ownership
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Keyfiles

# Create desktop shortcut for VeraCrypt
cat > /home/ga/Desktop/veracrypt.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=VeraCrypt
Comment=Disk Encryption
Exec=veracrypt
Icon=veracrypt
Terminal=false
Categories=Utility;Security;
EOF
chmod +x /home/ga/Desktop/veracrypt.desktop
chown ga:ga /home/ga/Desktop/veracrypt.desktop

# Launch VeraCrypt GUI
echo "Launching VeraCrypt GUI..."
su - ga -c "DISPLAY=:1 veracrypt &"

# Wait for VeraCrypt window to appear
sleep 5

# Check if VeraCrypt is running
if pgrep -f "veracrypt" > /dev/null; then
    echo "VeraCrypt is running"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
else
    echo "WARNING: VeraCrypt does not appear to be running"
fi

echo "=== VeraCrypt setup complete ==="
