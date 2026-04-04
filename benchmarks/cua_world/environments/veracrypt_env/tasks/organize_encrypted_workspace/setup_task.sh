#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Organize Encrypted Workspace Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 2. Reset the data volume to a clean state (FAT filesystem with loose files in root)
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
echo "Resetting volume at $VOLUME_PATH..."

# Remove existing volume if present to ensure clean state
rm -f "$VOLUME_PATH"

# Create new volume
veracrypt --text --create "$VOLUME_PATH" \
    --size=20M \
    --password='MountMe2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Populate volume with files
echo "Populating volume with initial files..."
mkdir -p /tmp/vc_setup_mount

# Mount
veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_setup_mount \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Check mount
if mountpoint -q /tmp/vc_setup_mount; then
    # Create realistic content for files if they don't exist in assets
    # NDA
    cat > /tmp/vc_setup_mount/SF312_Nondisclosure_Agreement.txt << 'EOF'
CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT
STANDARD FORM 312
...
(This is a sample dummy file for task purposes)
EOF

    # Budget
    cat > /tmp/vc_setup_mount/FY2024_Revenue_Budget.csv << 'EOF'
Department,Category,Q1,Q2,Q3,Q4,Total
IT,Hardware,15000,12000,8000,20000,55000
IT,Software,5000,5000,5000,5000,20000
HR,Recruiting,2000,5000,8000,1000,16000
Ops,Logistics,10000,10000,12000,15000,47000
EOF

    # SSH Keys
    cat > /tmp/vc_setup_mount/backup_authorized_keys << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... user@host1
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host2
EOF

    echo "Files created."
    ls -la /tmp/vc_setup_mount/

    # Sync to ensure data is written
    sync
    sleep 1

    # Dismount
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
else
    echo "ERROR: Failed to mount volume for setup!"
    exit 1
fi

rmdir /tmp/vc_setup_mount 2>/dev/null || true

# 4. Prepare UI
# Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure maximized
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="