#!/bin/bash
set -e

echo "=== Setting up Troubleshoot Mount Failure Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/Keyfiles
mkdir -p /home/ga/MountPoints/slot2
mkdir -p /home/ga/Documents
mkdir -p /opt/backups/old_keys

# 1. Create the keyfile in "original" location first
echo "Generating keyfile..."
dd if=/dev/urandom of=/home/ga/Keyfiles/project.key bs=64 count=1 2>/dev/null
chown ga:ga /home/ga/Keyfiles/project.key

# 2. Create the volume with password + keyfile
echo "Creating encrypted volume..."
if [ -f /home/ga/Volumes/project_vault.hc ]; then
    rm -f /home/ga/Volumes/project_vault.hc
fi

veracrypt --text --create /home/ga/Volumes/project_vault.hc \
    --size=15M \
    --password='ProjectVault2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='/home/ga/Keyfiles/project.key' \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Mount, add data, dismount
echo "Populating volume with data..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/project_vault.hc /tmp/vc_setup_mount \
    --password='ProjectVault2024' \
    --pim=0 \
    --keyfiles='/home/ga/Keyfiles/project.key' \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mount; then
    # Add real-world sample files
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/
    
    # Create the project plan file
    cat > /tmp/vc_setup_mount/project_plan.txt << 'EOF'
CONFIDENTIAL PROJECT DATA - Q4 2024 Sprint Plan
===============================================
Release target: 2024-12-15
Team lead: J. Martinez
Budget code: EXT-9942
Status: ON TRACK
EOF
    
    sync
    sleep 2
else
    echo "ERROR: Failed to mount volume for population"
    exit 1
fi

veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
rmdir /tmp/vc_setup_mount 2>/dev/null || true

# 4. Move keyfile to hidden location (The Problem)
echo "Hiding keyfile..."
cp /home/ga/Keyfiles/project.key /opt/backups/old_keys/project.key
rm -f /home/ga/Keyfiles/project.key
chmod 644 /opt/backups/old_keys/project.key

# 5. Plant Breadcrumbs

# Clue 1: Admin Notes
cat > /home/ga/Documents/admin_handoff_notes.txt << 'EOF'
Admin Handoff Notes - Last updated 2024-10-28
==============================================

Hi,

I'm leaving the company next week. Here are some notes on the systems:

- The project vault (project_vault.hc) in ~/Volumes/ contains all
  the confidential project files. Password is on the sticky note.
  IMPORTANT: This volume requires a keyfile in addition to the password.
  The keyfile was originally in ~/Keyfiles/ but I moved things around
  during the server cleanup last month. Check the old backup location
  if you can't find it — I think I consolidated keys somewhere under /opt.

- Database backups run nightly at 2 AM via cron.

- The monitoring dashboard is at http://internal:3000

Good luck!
- Alex
EOF

# Clue 2: Bash History
cat >> /home/ga/.bash_history << 'EOF'
ls ~/Keyfiles/
mkdir -p /opt/backups/old_keys
mv ~/Keyfiles/project.key /opt/backups/old_keys/
ls /opt/backups/old_keys/
veracrypt --text --dismount /home/ga/MountPoints/slot2 --non-interactive
EOF

# Clue 3: Cleanup Log
cat > /home/ga/Documents/cleanup_log_2024-10-15.txt << 'EOF'
Filesystem cleanup performed 2024-10-15
Moved stale keyfiles to consolidated backup:
  /home/ga/Keyfiles/project.key -> /opt/backups/old_keys/project.key
  /home/ga/Keyfiles/old_server.key -> /opt/backups/old_keys/old_server.key (deleted - no longer needed)
Freed 2.1 GB in /home/ga/Downloads (removed old ISOs)
EOF

# Fix permissions
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Keyfiles

# Launch VeraCrypt GUI
echo "Starting VeraCrypt GUI..."
if ! pgrep -f "veracrypt" > /dev/null; then
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Wait for and maximize window
wait_for_window "VeraCrypt" 15
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="