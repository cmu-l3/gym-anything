#!/bin/bash
set -e
echo "=== Setting up nested encryption workflow task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Dismount any existing VeraCrypt volumes to ensure clean slate
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# Clean up any previous task artifacts
rm -f /home/ga/Volumes/outer_vault.hc
rm -rf /home/ga/Documents/sensitive_files

# Create the outer vault volume (50MB, AES, SHA-512, FAT)
echo "Creating outer vault volume..."
veracrypt --text --create /home/ga/Volumes/outer_vault.hc \
    --size=50M \
    --password='OuterVault2024!' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive
echo "Outer vault created."

# Prepare sensitive files directory with real document data
mkdir -p /home/ga/Documents/sensitive_files
# Use existing assets if available, or create realistic dummy data if not
if [ -f /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt ]; then
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /home/ga/Documents/sensitive_files/
else
    # Fallback creation
    echo "CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT" > /home/ga/Documents/sensitive_files/SF312_Nondisclosure_Agreement.txt
    echo "Standard Form 312" >> /home/ga/Documents/sensitive_files/SF312_Nondisclosure_Agreement.txt
    for i in {1..100}; do echo "Confidential data line $i" >> /home/ga/Documents/sensitive_files/SF312_Nondisclosure_Agreement.txt; done
fi

if [ -f /workspace/assets/sample_data/FY2024_Revenue_Budget.csv ]; then
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /home/ga/Documents/sensitive_files/
else
    # Fallback creation
    echo "Department,Q1,Q2,Q3,Q4,Total" > /home/ga/Documents/sensitive_files/FY2024_Revenue_Budget.csv
    echo "R&D,150000,160000,145000,180000,635000" >> /home/ga/Documents/sensitive_files/FY2024_Revenue_Budget.csv
    echo "Operations,500000,510000,520000,550000,2080000" >> /home/ga/Documents/sensitive_files/FY2024_Revenue_Budget.csv
fi

chown -R ga:ga /home/ga/Documents/sensitive_files
chmod 644 /home/ga/Documents/sensitive_files/*

# Store checksums for verification
md5sum /home/ga/Documents/sensitive_files/SF312_Nondisclosure_Agreement.txt > /tmp/expected_checksums.txt
md5sum /home/ga/Documents/sensitive_files/FY2024_Revenue_Budget.csv >> /tmp/expected_checksums.txt
chmod 644 /tmp/expected_checksums.txt

# Ensure mount points exist and are empty
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /home/ga/MountPoints/slot2
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Volumes

# Ensure VeraCrypt is running
if ! pgrep -f "veracrypt" > /dev/null; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Wait for VeraCrypt window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "VeraCrypt"; then
        break
    fi
    sleep 1
done

# Maximize and focus VeraCrypt window
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="