#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Reset Credentials Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous state
rm -f /home/ga/Volumes/DepartedUser.hc
rm -f /home/ga/Keyfiles/security_token.key
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 2. Create Keyfile
# Create a 64-byte random keyfile
dd if=/dev/urandom of=/home/ga/Keyfiles/security_token.key bs=1 count=64 status=none
chown ga:ga /home/ga/Keyfiles/security_token.key

# 3. Create Complex Volume
# We create a 5MB volume to keep creation time low
# Credentials: Password='Complex#88', PIM=1001, Keyfile='security_token.key'
echo "Creating encrypted volume (this may take a moment)..."
su - ga -c "veracrypt --text --create /home/ga/Volumes/DepartedUser.hc \
    --size=5M \
    --password='Complex#88' \
    --pim=1001 \
    --keyfiles='/home/ga/Keyfiles/security_token.key' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive"

# 4. Inject Data
echo "Injecting data into volume..."
mkdir -p /tmp/setup_mount
# Mount with complex credentials
su - ga -c "veracrypt --text --mount /home/ga/Volumes/DepartedUser.hc /tmp/setup_mount \
    --password='Complex#88' \
    --pim=1001 \
    --keyfiles='/home/ga/Keyfiles/security_token.key' \
    --protect-hidden=no \
    --non-interactive"

# Add files
if mountpoint -q /tmp/setup_mount; then
    # Use existing asset if available, else create dummy
    if [ -f /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt ]; then
        cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/setup_mount/Project_Specs.pdf
    else
        echo "CONFIDENTIAL PROJECT SPECS - DO NOT DISTRIBUTE" > /tmp/setup_mount/Project_Specs.pdf
    fi
    
    echo "Quarter,Budget" > /tmp/setup_mount/Budget_Draft.csv
    echo "Q1,50000" >> /tmp/setup_mount/Budget_Draft.csv
    
    # Ensure correct ownership
    chown ga:ga /tmp/setup_mount/*
    sync
fi

# Dismount
su - ga -c "veracrypt --text --dismount /tmp/setup_mount --non-interactive"
rmdir /tmp/setup_mount 2>/dev/null || true

# 5. Launch VeraCrypt GUI
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize for visibility
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="