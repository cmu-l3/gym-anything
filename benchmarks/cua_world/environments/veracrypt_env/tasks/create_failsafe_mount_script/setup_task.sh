#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Failsafe Script Task ==="

# 1. Cleanup previous runs
rm -f /home/ga/Documents/safe_log_entry.sh 2>/dev/null || true
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# 2. Create the target volume if it doesn't exist
VOLUME_PATH="/home/ga/Volumes/audit_volume.hc"
if [ ! -f "$VOLUME_PATH" ]; then
    echo "Creating audit volume..."
    veracrypt --text --create "$VOLUME_PATH" \
        --size=10M \
        --password='SecureAudit2024!' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive
fi

# 3. Populate volume with initial log file
echo "Populating audit volume..."
mkdir -p /tmp/setup_mount
veracrypt --text --mount "$VOLUME_PATH" /tmp/setup_mount \
    --password='SecureAudit2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Add some existing log entries
echo "2023-12-01 08:00:00 - System startup" > /tmp/setup_mount/audit_log.txt
echo "2023-12-01 12:00:00 - Scheduled check" >> /tmp/setup_mount/audit_log.txt
chmod 666 /tmp/setup_mount/audit_log.txt

# Count lines for verification later
INITIAL_LINES=$(wc -l < /tmp/setup_mount/audit_log.txt)
echo "$INITIAL_LINES" > /tmp/initial_log_lines.txt

veracrypt --text --dismount /tmp/setup_mount --non-interactive 2>/dev/null || true
rmdir /tmp/setup_mount 2>/dev/null || true

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="