#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Secure Mount Permissions Task ==="

# 1. Create directory structure
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/MountPoints/project
chown ga:ga /home/ga/MountPoints/project
chmod 755 /home/ga/MountPoints/project

# 2. Clean up previous volume if exists
rm -f /home/ga/Volumes/project_alpha.hc

# 3. Create the specific task volume (exFAT is key here as it doesn't support native perms)
# We create a temporary mount to populate it, then unmount
echo "Creating exFAT volume..."
veracrypt --text --create /home/ga/Volumes/project_alpha.hc \
    --size=50M \
    --password='AlphaTeam2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=exFAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Populate with some dummy data (as root, since default mount is root)
echo "Populating volume..."
mkdir -p /tmp/vc_setup_mnt
# Mount without special options first (default behavior)
veracrypt --text --mount /home/ga/Volumes/project_alpha.hc /tmp/vc_setup_mnt \
    --password='AlphaTeam2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mnt; then
    # Create some structure
    mkdir -p /tmp/vc_setup_mnt/src
    mkdir -p /tmp/vc_setup_mnt/docs
    echo "CONFIDENTIAL PROJECT ALPHA" > /tmp/vc_setup_mnt/README.md
    echo "def main(): pass" > /tmp/vc_setup_mnt/src/main.py
    echo "Specs v1.0" > /tmp/vc_setup_mnt/docs/specs.txt
    
    # Dismount
    veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
else
    echo "ERROR: Failed to mount volume for setup"
    exit 1
fi
rmdir /tmp/vc_setup_mnt 2>/dev/null || true

# 5. Set ownership of the container file
chown ga:ga /home/ga/Volumes/project_alpha.hc

# 6. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 7. Setup anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="