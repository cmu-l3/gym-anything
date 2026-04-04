#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Encrypt Existing Data Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous run artifacts
echo "Cleaning up previous runs..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/sensitive_encrypted.hc 2>/dev/null || true
rm -rf /home/ga/SensitiveData 2>/dev/null || true
mkdir -p /home/ga/SensitiveData

# 2. Create Realistic Sample Data
echo "Generating sensitive data files..."
DATA_DIR="/home/ga/SensitiveData"

# File 1: NDA (Simulated content)
cat > "$DATA_DIR/SF312_Nondisclosure_Agreement.txt" << EOF
CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT
STANDARD FORM 312 (Rev. 7-2013)

1. Intending to be legally bound, I hereby accept the obligations contained in this Agreement 
in consideration of my being granted access to classified information. As used in this 
Agreement, classified information is marked or unmarked classified information, including 
oral communications, that is classified under the standards of Executive Order 13526.

2. I understand and accept that by being granted access to classified information, special 
confidence and trust shall be placed in me by the United States Government.
EOF

# File 2: Budget CSV
cat > "$DATA_DIR/FY2024_Revenue_Budget.csv" << EOF
Department,Q1_Projected,Q1_Actual,Q2_Projected,Variance
Sales_East,1250000,1100000,1300000,-150000
Sales_West,1450000,1520000,1600000,+70000
Engineering,500000,485000,550000,-15000
Marketing,200000,195000,220000,-5000
TOTAL,3400000,3300000,3670000,-100000
EOF

# File 3: SSH Keys
cat > "$DATA_DIR/backup_authorized_keys" << EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCv4... user@workstation-legacy
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC... admin@backup-server
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD... automated-backup-service
EOF

# 3. Generate Checksums (Manifest)
echo "Generating checksum manifest..."
cd "$DATA_DIR"
sha256sum SF312_Nondisclosure_Agreement.txt FY2024_Revenue_Budget.csv backup_authorized_keys > data_manifest.sha256

# 4. Save Ground Truth for Verifier (Hidden)
mkdir -p /var/lib/veracrypt_task
cp "$DATA_DIR/data_manifest.sha256" /var/lib/veracrypt_task/original_checksums.txt
chmod 600 /var/lib/veracrypt_task/original_checksums.txt

# 5. Launch VeraCrypt
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

# Wait for window and maximize
if wait_for_window "VeraCrypt" 20; then
    WID=$(get_veracrypt_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: VeraCrypt window did not appear in time."
fi

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

# Set permissions
chown -R ga:ga /home/ga/SensitiveData
chmod 600 /home/ga/SensitiveData/*

echo "=== Setup Complete ==="