#!/bin/bash
set -e
echo "=== Setting up Create Cascade Volume Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous run artifacts
echo "Cleaning previous artifacts..."
rm -f /home/ga/Volumes/classified_volume.hc
rm -f /home/ga/Documents/volume_security_report.txt
rm -rf /home/ga/Documents/classified
# Force dismount everything to ensure clean slate
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# 2. Prepare Source Data
echo "Staging classified documents..."
mkdir -p /home/ga/Documents/classified

# Copy sample data assets
cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /home/ga/Documents/classified/
cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /home/ga/Documents/classified/
cp /workspace/assets/sample_data/backup_authorized_keys /home/ga/Documents/classified/

# Set ownership
chown -R ga:ga /home/ga/Documents/classified

# Calculate SHA256 checksums of source files for later verification
# Format: "checksum  filename"
sha256sum /home/ga/Documents/classified/SF312_Nondisclosure_Agreement.txt | awk '{print $1}' > /tmp/sum_file1.txt
sha256sum /home/ga/Documents/classified/FY2024_Revenue_Budget.csv | awk '{print $1}' > /tmp/sum_file2.txt
sha256sum /home/ga/Documents/classified/backup_authorized_keys | awk '{print $1}' > /tmp/sum_file3.txt

# 3. Ensure Environment Readiness
# Create target directories if they don't exist
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/MountPoints/slot1
chown ga:ga /home/ga/Volumes
chown ga:ga /home/ga/MountPoints/slot1

# 4. Start VeraCrypt
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Wait for window
if ! wait_for_window "VeraCrypt" 30; then
    echo "WARNING: VeraCrypt window not detected"
fi

# Maximize and focus
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Source files located in: /home/ga/Documents/classified/"
ls -la /home/ga/Documents/classified/