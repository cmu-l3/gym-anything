#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up mount_secure_fs_options task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data_volume.hc exists
if [ ! -f /home/ga/Volumes/data_volume.hc ]; then
    echo "Creating data volume..."
    veracrypt --text --create /home/ga/Volumes/data_volume.hc \
        --size=20M \
        --password='MountMe2024' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles='' \
        --random-source=/dev/urandom \
        --non-interactive
    
    # Add sample data
    mkdir -p /tmp/vc_setup_mnt
    veracrypt --text --mount /home/ga/Volumes/data_volume.hc /tmp/vc_setup_mnt \
        --password='MountMe2024' --pim=0 --keyfiles='' --non-interactive
    
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mnt/ 2>/dev/null || true
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mnt/ 2>/dev/null || true
    cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup_mnt/ 2>/dev/null || true
    
    veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
    rmdir /tmp/vc_setup_mnt
fi

# Ensure mount point exists and is empty
mkdir -p /home/ga/MountPoints/secure_data
chown ga:ga /home/ga/MountPoints/secure_data

# Ensure nothing is mounted there
if mountpoint -q /home/ga/MountPoints/secure_data; then
    veracrypt --text --dismount /home/ga/MountPoints/secure_data --non-interactive 2>/dev/null || umount -f /home/ga/MountPoints/secure_data
fi

# Clean up report
rm -f /home/ga/Documents/mount_security_report.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state
cat /proc/mounts > /tmp/initial_mounts.txt
mount | grep "veracrypt" | wc -l > /tmp/initial_mount_count.txt

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi
wait_for_window "VeraCrypt" 20

# Maximize and focus
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="