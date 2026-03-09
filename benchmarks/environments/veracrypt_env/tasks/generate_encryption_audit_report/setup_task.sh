#!/bin/bash
# setup_task.sh for generate_encryption_audit_report
set -e
echo "=== Setting up encryption audit report task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up any previously mounted volumes
echo "Cleaning up any existing mounts..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 2

# Remove any previous task artifacts
rm -f /home/ga/Volumes/finance_dept.hc
rm -f /home/ga/Volumes/hr_dept.hc
rm -f /home/ga/Volumes/engineering_dept.hc
rm -f /home/ga/Documents/encryption_audit_report.json

# Ensure directories exist
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/MountPoints
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Volumes /home/ga/MountPoints /home/ga/Documents

# Create Volume 1: finance_dept.hc — AES + SHA-512
echo "Creating finance_dept.hc (AES, SHA-512)..."
veracrypt --text --create /home/ga/Volumes/finance_dept.hc \
    --size=15M \
    --password='Fin@nce2024Secure' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Create Volume 2: hr_dept.hc — Serpent + SHA-256
echo "Creating hr_dept.hc (Serpent, SHA-256)..."
veracrypt --text --create /home/ga/Volumes/hr_dept.hc \
    --size=10M \
    --password='HR#Dept!2024Safe' \
    --encryption=Serpent \
    --hash=SHA-256 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Create Volume 3: engineering_dept.hc — Twofish + Whirlpool
echo "Creating engineering_dept.hc (Twofish, Whirlpool)..."
veracrypt --text --create /home/ga/Volumes/engineering_dept.hc \
    --size=12M \
    --password='Eng1neer$2024Key' \
    --encryption=Twofish \
    --hash=Whirlpool \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Add sample data to one volume for realism
echo "Adding sample data..."
mkdir -p /tmp/vc_setup_mnt
if veracrypt --text --mount /home/ga/Volumes/finance_dept.hc /tmp/vc_setup_mnt \
    --password='Fin@nce2024Secure' --pim=0 --keyfiles='' \
    --protect-hidden=no --non-interactive; then
    
    echo "CONFIDENTIAL FINANCE DATA" > /tmp/vc_setup_mnt/financial_summary_q3.txt
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mnt/ 2>/dev/null || true
    sync
    veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
fi
rmdir /tmp/vc_setup_mnt 2>/dev/null || true

# Fix ownership
chown ga:ga /home/ga/Volumes/*.hc

# Ensure VeraCrypt GUI is running
if ! pgrep -f "veracrypt" > /dev/null; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Maximize VeraCrypt window
wait_for_window "VeraCrypt" 20
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="