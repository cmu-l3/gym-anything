#!/bin/bash
set -e
echo "=== Setting up forensic_evidence_extraction task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -rf /home/ga/Evidence 2>/dev/null || true
mkdir -p /home/ga/Evidence

# Ensure data_volume.hc is NOT currently mounted
echo "Ensuring volume is unmounted..."
veracrypt --text --dismount /home/ga/MountPoints/slot1 --non-interactive 2>/dev/null || true
veracrypt --text --dismount /home/ga/Volumes/data_volume.hc --non-interactive 2>/dev/null || true
sleep 1

# Verify data_volume.hc exists
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "ERROR: data_volume.hc not found! Recreating..."
    /workspace/scripts/setup_veracrypt.sh
fi

# ------------------------------------------------------------------
# GENERATE GROUND TRUTH (Hidden from agent)
# ------------------------------------------------------------------
echo "Generating ground truth data..."
mkdir -p /tmp/vc_gt_mount
mkdir -p /var/lib/veracrypt_task
chmod 700 /var/lib/veracrypt_task

# Mount locally to read contents
veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_gt_mount \
    --password='MountMe2024' --pim=0 --keyfiles='' \
    --protect-hidden=no --non-interactive

# Save ground truth details
cd /tmp/vc_gt_mount
# 1. File count
ls -1 | wc -l > /var/lib/veracrypt_task/gt_file_count.txt
# 2. File list
ls -1 > /var/lib/veracrypt_task/gt_filenames.txt
# 3. Hashes (filename-agnostic checks)
sha256sum * > /var/lib/veracrypt_task/gt_hashes.txt
# 4. Total size
du -sb . | awk '{print $1}' > /var/lib/veracrypt_task/gt_size_bytes.txt
cd /

# Dismount ground truth check
veracrypt --text --dismount /tmp/vc_gt_mount --non-interactive
rmdir /tmp/vc_gt_mount 2>/dev/null || true
echo "Ground truth generated."

# ------------------------------------------------------------------
# PREPARE ENVIRONMENT
# ------------------------------------------------------------------

# Ensure mount point exists and is empty
mkdir -p /home/ga/MountPoints/slot1
chown ga:ga /home/ga/MountPoints/slot1

# Ensure VeraCrypt GUI is running for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Wait for window and maximize
if wait_for_window "VeraCrypt" 15; then
    wid=$(get_veracrypt_window_id)
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="