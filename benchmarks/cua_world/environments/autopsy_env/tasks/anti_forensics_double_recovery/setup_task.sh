#!/bin/bash
echo "=== Setting up anti_forensics_double_recovery task ==="

source /workspace/scripts/task_utils.sh

# Clean up prior artifacts
rm -f /tmp/task_result.json /tmp/task_start_time 2>/dev/null || true
for d in /home/ga/Cases/Operation_Phoenix*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

IMAGE="/home/ga/evidence/corrupted_drive.dd"
rm -f "$IMAGE"

echo "Creating forensic image..."
dd if=/dev/zero of=/tmp/fat32.img bs=1M count=20 2>/dev/null
mkfs.vfat -F 32 -n "PHOENIX" /tmp/fat32.img >/dev/null 2>&1

echo "drive i: file=\"/tmp/fat32.img\"" > /tmp/mtoolsrc
export MTOOLSRC=/tmp/mtoolsrc

# Create files locally to inject
mkdir -p /tmp/phoenix_files
echo "INFORMANT_ID,CONTACT_NAME,PHONE" > /tmp/phoenix_files/secret_contact.csv
echo "X-992-ALPHA,John Doe,555-0199" >> /tmp/phoenix_files/secret_contact.csv
echo "Project details and cover info." > /tmp/phoenix_files/cover.txt

# Copy files using mtools to avoid requiring loop mount permissions
mmd i:/Documents
mcopy -i /tmp/fat32.img /tmp/phoenix_files/secret_contact.csv i:/Documents/
mcopy -i /tmp/fat32.img /tmp/phoenix_files/cover.txt i:/Documents/

# Delete the file (so it exists but is marked as deleted in FAT)
mdel -i /tmp/fat32.img i:/Documents/secret_contact.csv

# Create final container disk image (24MB)
dd if=/dev/zero of="$IMAGE" bs=1M count=24 2>/dev/null

# Inject FAT32 image at exactly 1MiB offset (sector 2048)
dd if=/tmp/fat32.img of="$IMAGE" bs=1M seek=1 conv=notrunc 2>/dev/null

# Write MBR boot signature (55 AA) to make it a valid MBR sector
printf '\x55\xAA' | dd of="$IMAGE" bs=1 seek=510 conv=notrunc 2>/dev/null

# NOTE: The partition table (bytes 446-509) remains completely blank.
# This forces the agent to recover the geometry using testdisk or parted!

chown ga:ga "$IMAGE"
rm -f /tmp/fat32.img /tmp/mtoolsrc
rm -rf /tmp/phoenix_files

date +%s > /tmp/task_start_time

# Kill and launch Autopsy
kill_autopsy
launch_autopsy
wait_for_autopsy_window 300

sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="