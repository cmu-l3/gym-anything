#!/bin/bash
# setup_task.sh - Prepare the corrupted header recovery task
set -e

echo "=== Setting up mount_corrupted_header task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous task state
veracrypt --text --dismount /home/ga/MountPoints/slot1 --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/corrupted_volume.hc 2>/dev/null || true
rm -f /home/ga/recovery_report.txt 2>/dev/null || true
rm -rf /tmp/vc_setup_mount 2>/dev/null || true
rm -rf /var/lib/veracrypt_task_data 2>/dev/null || true

# Ensure mount point exists
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /tmp/vc_setup_mount

# Create temporary data directory
mkdir -p /tmp/task_data_gen

# Create sample files
cat > /tmp/task_data_gen/project_ssh_config << 'EOF'
Host bastion-prod
    HostName 203.0.113.50
    User deploy
    IdentityFile ~/.ssh/id_ed25519_prod
Host app-server-*
    ProxyJump bastion-prod
    User appuser
EOF

cat > /tmp/task_data_gen/infrastructure_hosts << 'EOF'
127.0.0.1       localhost
10.0.1.10       app-web-01.prod.internal
10.0.5.10       db-primary.prod.internal
10.0.2.10       prometheus.prod.internal
EOF

cat > /tmp/task_data_gen/quarterly_metrics.csv << 'EOF'
metric_id,metric_name,category,q1_2024
MRR-001,Monthly Recurring Revenue,Revenue,2847500.00
ARR-001,Annual Recurring Revenue,Revenue,34170000.00
EOF

# Step 1: Create the VeraCrypt volume
echo "Creating encrypted volume..."
veracrypt --text --create /home/ga/Volumes/corrupted_volume.hc \
    --size=5M \
    --password='RecoverMe2024!' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Step 2: Mount the volume and add sample files
echo "Mounting volume to add sample data..."
veracrypt --text --mount /home/ga/Volumes/corrupted_volume.hc /tmp/vc_setup_mount \
    --password='RecoverMe2024!' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive

# Copy sample files into the volume
cp /tmp/task_data_gen/* /tmp/vc_setup_mount/
sync

# Step 3: Compute and save ground-truth checksums (hidden from agent)
echo "Computing ground-truth checksums..."
mkdir -p /var/lib/veracrypt_task_data
cd /tmp/vc_setup_mount
sha256sum project_ssh_config infrastructure_hosts quarterly_metrics.csv > /var/lib/veracrypt_task_data/expected_checksums.txt
chmod 600 /var/lib/veracrypt_task_data/expected_checksums.txt # Only root/owner read
cd /

# Step 4: Dismount the volume
echo "Dismounting volume..."
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
sleep 1
rmdir /tmp/vc_setup_mount

# Step 5: Corrupt the primary header
echo "Corrupting primary volume header..."
# Zero out the first 512 bytes (salt + beginning of encrypted header)
dd if=/dev/zero of=/home/ga/Volumes/corrupted_volume.hc bs=1 count=512 conv=notrunc

# Ensure VeraCrypt GUI is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Focus and maximize
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

# Cleanup temp data
rm -rf /tmp/task_data_gen

echo "=== Task setup complete ==="