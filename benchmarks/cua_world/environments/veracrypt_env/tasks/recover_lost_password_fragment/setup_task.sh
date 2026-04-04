#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recover Lost Password Task ==="

# 1. Generate Random ID (450-499)
# Use shuf or arithmetic expansion
RANGE_START=450
RANGE_END=499
TARGET_ID=$(shuf -i $RANGE_START-$RANGE_END -n 1)
PASSWORD="DevBuild_${TARGET_ID}!"

# Save ground truth to a hidden location (root only) for export script
echo "$TARGET_ID" > /var/lib/task_ground_truth_id.txt
chmod 600 /var/lib/task_ground_truth_id.txt

echo "Setup: Generated target ID $TARGET_ID"

# 2. Clean up previous state
rm -f /home/ga/Volumes/project_archive.hc
rm -f /home/ga/Documents/recovered_id.txt
mkdir -p /home/ga/MountPoints/recovered
# Dismount everything
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 3. Create the encrypted volume with the specific password
echo "Creating encrypted volume..."
veracrypt --text --create /home/ga/Volumes/project_archive.hc \
    --size=10M \
    --password="$PASSWORD" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Add dummy data to the volume
echo "Populating volume with data..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/project_archive.hc /tmp/vc_setup_mount \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Create manifest file
cat > /tmp/vc_setup_mount/project_manifest.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <id>DevBuild_${TARGET_ID}</id>
    <status>Archived</status>
    <files>
        <file>main.cpp</file>
        <file>utils.h</file>
    </files>
</project>
EOF

# Create dummy code files
echo "// Main entry point" > /tmp/vc_setup_mount/main.cpp
echo "// Utilities" > /tmp/vc_setup_mount/utils.h

# Sync and dismount
sync
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
rmdir /tmp/vc_setup_mount

# 5. Set permissions
chown ga:ga /home/ga/Volumes/project_archive.hc
chown ga:ga /home/ga/MountPoints/recovered
chown ga:ga /home/ga/Documents

# 6. Ensure VeraCrypt GUI is running for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="