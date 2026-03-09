#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Remediate Read-Only Access Task ==="

# 1. Clean up any previous state
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/department_archive.hc 2>/dev/null
rm -f /home/ga/Documents/diagnosis.txt 2>/dev/null
mkdir -p /home/ga/MountPoints/archive

# 2. Create the volume (RW initially to populate data)
echo "Creating department_archive.hc..."
veracrypt --text --create /home/ga/Volumes/department_archive.hc \
    --size=10M \
    --password='ArchiveAccess2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Populate with data
echo "Populating volume..."
veracrypt --text --mount /home/ga/Volumes/department_archive.hc /home/ga/MountPoints/archive \
    --password='ArchiveAccess2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Add sample data
echo "Budget,Q1,Q2,Q3,Q4" > /home/ga/MountPoints/archive/FY2024_Budget_v1.csv
echo "Marketing,10000,12000,15000,20000" >> /home/ga/MountPoints/archive/FY2024_Budget_v1.csv
echo "R&D,50000,55000,60000,65000" >> /home/ga/MountPoints/archive/FY2024_Budget_v1.csv

# Dismount to reset
veracrypt --text --dismount /home/ga/MountPoints/archive --non-interactive

# 4. Mount in READ-ONLY mode (The Problem State)
echo "Mounting in Read-Only mode..."
veracrypt --text --mount /home/ga/Volumes/department_archive.hc /home/ga/MountPoints/archive \
    --password='ArchiveAccess2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --readonly \
    --non-interactive

# Verify it is actually read-only
if mount | grep "/home/ga/MountPoints/archive" | grep -q "ro,"; then
    echo "Setup Verified: Volume mounted Read-Only"
else
    echo "WARNING: Volume might not be Read-Only. Mount flags: $(mount | grep archive)"
fi

# 5. Launch VeraCrypt GUI for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="