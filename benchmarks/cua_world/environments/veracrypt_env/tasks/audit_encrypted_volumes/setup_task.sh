#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Encrypted Volumes Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous runs
rm -f /home/ga/Documents/volume_audit_report.json
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/dept_finance.hc
rm -f /home/ga/Volumes/dept_hr.hc

# ------------------------------------------------------------------
# Create Dummy Data Files
# ------------------------------------------------------------------
mkdir -p /tmp/audit_data_setup
cat > /tmp/audit_data_setup/FY2024_Revenue_Budget.csv << 'EOF'
Department,Q1,Q2,Q3,Q4,Total
Public Safety,4.2M,4.2M,4.3M,4.5M,17.2M
Education,8.1M,8.1M,8.3M,8.6M,33.1M
EOF

cat > /tmp/audit_data_setup/SF312_Nondisclosure_Agreement.txt << 'EOF'
CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT
An Agreement Between [Employee Name] and the United States
1. Intending to be legally bound, I hereby accept the obligations...
EOF

cat > /tmp/audit_data_setup/backup_authorized_keys << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbqajDRETbwEsm5aqFMnSgKJkxoHT... admin@server
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHKKhx/FnOzR3bCjLkGTqHR3tcZXRKyhX... deploy@ci
EOF

# ------------------------------------------------------------------
# Create Volume 1: dept_finance.hc (Serpent / SHA-256)
# ------------------------------------------------------------------
echo "Creating dept_finance.hc..."
veracrypt --text --create /home/ga/Volumes/dept_finance.hc \
    --size=15M \
    --password='Finance2024!' \
    --encryption=Serpent \
    --hash=SHA-256 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Populate Volume 1
mkdir -p /tmp/vc_mnt_finance
veracrypt --text --mount /home/ga/Volumes/dept_finance.hc /tmp/vc_mnt_finance \
    --password='Finance2024!' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive

cp /tmp/audit_data_setup/FY2024_Revenue_Budget.csv /tmp/vc_mnt_finance/
cp /tmp/audit_data_setup/SF312_Nondisclosure_Agreement.txt /tmp/vc_mnt_finance/
sync
veracrypt --text --dismount /tmp/vc_mnt_finance --non-interactive
rmdir /tmp/vc_mnt_finance

# ------------------------------------------------------------------
# Create Volume 2: dept_hr.hc (Twofish / Whirlpool)
# ------------------------------------------------------------------
echo "Creating dept_hr.hc..."
veracrypt --text --create /home/ga/Volumes/dept_hr.hc \
    --size=15M \
    --password='HumanRes2024!' \
    --encryption=Twofish \
    --hash=Whirlpool \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# Populate Volume 2
mkdir -p /tmp/vc_mnt_hr
veracrypt --text --mount /home/ga/Volumes/dept_hr.hc /tmp/vc_mnt_hr \
    --password='HumanRes2024!' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive

cp /tmp/audit_data_setup/backup_authorized_keys /tmp/vc_mnt_hr/
sync
veracrypt --text --dismount /tmp/vc_mnt_hr --non-interactive
rmdir /tmp/vc_mnt_hr

# Clean up setup data
rm -rf /tmp/audit_data_setup
chown ga:ga /home/ga/Volumes/*.hc

# ------------------------------------------------------------------
# Application Setup
# ------------------------------------------------------------------
# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Ensure window is visible and maximized
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Dismiss any startup dialogs if they exist
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Audit Task Setup Complete ==="