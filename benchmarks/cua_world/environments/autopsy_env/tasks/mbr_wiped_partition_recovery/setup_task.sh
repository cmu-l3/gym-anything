#!/bin/bash
echo "=== Setting up mbr_wiped_partition_recovery task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/mbr_recovery_result.json /tmp/mbr_recovery_start_time /tmp/ground_truth_hash.txt 2>/dev/null || true
rm -f /home/ga/evidence/recovered_volume.dd 2>/dev/null || true

for d in /home/ga/Cases/MBR_Recovery_2026*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify and prepare disk image ─────────────────────────────────────────────
ORIG_IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$ORIG_IMAGE" ]; then
    echo "ERROR: Original disk image not found at $ORIG_IMAGE"
    exit 1
fi

# Calculate GT hash
GT_HASH=$(md5sum "$ORIG_IMAGE" | awk '{print $1}')
echo "$GT_HASH" > /tmp/ground_truth_hash.txt

# Create the wiped drive image
echo "Creating wiped drive image..."
dd if=/dev/zero of=/home/ga/evidence/wiped_drive.raw bs=512 count=2048 2>/dev/null
cat "$ORIG_IMAGE" >> /home/ga/evidence/wiped_drive.raw

# Hide the original image from the evidence folder so the agent can't cheat
mv "$ORIG_IMAGE" /tmp/ntfs_undel_hidden.dd.bak

chown ga:ga /home/ga/evidence/wiped_drive.raw

echo "Wiped disk image created: /home/ga/evidence/wiped_drive.raw"
echo "Hidden volume starts at sector 2048."

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/mbr_recovery_start_time

# ── Ensure Autopsy is NOT running ─────────────────────────────────────────────
kill_autopsy

# Provide a clean desktop for the agent
DISPLAY=:1 wmctrl -k on 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="