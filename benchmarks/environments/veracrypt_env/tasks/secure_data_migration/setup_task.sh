#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Secure Data Migration Task ==="

# 1. Clean up previous state
echo "Cleaning up..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/secure_archive.hc 2>/dev/null || true
rm -f /home/ga/Documents/migration_report.txt 2>/dev/null || true
rm -rf /home/ga/Documents/SensitiveData 2>/dev/null || true
rm -rf /var/lib/veracrypt_task 2>/dev/null || true

# 2. Create directory structure
SOURCE_DIR="/home/ga/Documents/SensitiveData"
HIDDEN_GT_DIR="/var/lib/veracrypt_task"
mkdir -p "$SOURCE_DIR"
mkdir -p "$HIDDEN_GT_DIR"

# 3. Generate Sensitive Data Files
echo "Generating sensitive data..."

# File 1: NDA (Text)
cat > "$SOURCE_DIR/SF312_Nondisclosure_Agreement.txt" << 'EOF'
STANDARD FORM 312
CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT

1. Intending to be legally bound, I hereby accept the obligations contained in this Agreement in consideration of my being granted access to classified information. As used in this Agreement, classified information is marked or unmarked classified information, including oral communications, that is classified under the standards of Executive Order 13526, or under any other Executive Order or statute that prohibits the unauthorized disclosure of information in the interest of national security.

2. I understand and accept that by being granted access to classified information, special confidence and trust shall be placed in me by the United States Government.

3. I have been advised that the unauthorized disclosure, modification, or destruction of classified information by me could cause damage or irreparable injury to the United States or could be used to advantage by a foreign nation.

(Signed) ___________________________  Date: 2024-01-15
EOF

# File 2: Budget (CSV)
cat > "$SOURCE_DIR/FY2024_Revenue_Budget.csv" << 'EOF'
Department,Q1_Allocation,Q2_Allocation,Q3_Allocation,Q4_Allocation,Total_YTD
R&D,1500000,1200000,1800000,1600000,6100000
Marketing,800000,950000,1100000,1200000,4050000
Operations,2200000,2100000,2300000,2400000,9000000
Security,450000,450000,500000,550000,1950000
Executive,1200000,1200000,1200000,1200000,4800000
EOF

# File 3: SSH Keys (Key format)
cat > "$SOURCE_DIR/backup_authorized_keys" << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC4...[truncated_signature]... user@workstation-alpha
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK...[truncated_signature]... admin@server-backup
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDO...[truncated_signature]... deploy@jenkins-node
EOF

# File 4: Contacts (VCF)
cat > "$SOURCE_DIR/employee_contacts.vcf" << 'EOF'
BEGIN:VCARD
VERSION:3.0
FN:John Doe
N:Doe;John;;;
EMAIL;TYPE=INTERNET:john.doe@example.com
TEL;TYPE=CELL:(555) 123-4567
END:VCARD
BEGIN:VCARD
VERSION:3.0
FN:Jane Smith
N:Smith;Jane;;;
EMAIL;TYPE=INTERNET:jane.smith@example.com
TEL;TYPE=WORK:(555) 987-6543
END:VCARD
EOF

# File 5: Incident Response (Markdown)
cat > "$SOURCE_DIR/incident_response_plan.md" << 'EOF'
# Incident Response Plan (CONFIDENTIAL)

## Phase 1: Preparation
- Ensure team contact list is up to date (see employee_contacts.vcf)
- Verify backup integrity daily

## Phase 2: Detection and Analysis
1. Monitor SIEM logs for anomalies
2. Validate alerts within 15 minutes
3. Classify incident severity (Low, Medium, High, Critical)

## Phase 3: Containment
- Isolate affected systems from network
- Update firewall rules to block malicious IPs
- **DO NOT** reboot systems (preserve volatile memory)

## Phase 4: Eradication and Recovery
- Re-image compromised hosts
- Restore data from clean backups
EOF

# 4. Create Checksums
echo "Creating checksum manifests..."
cd "$SOURCE_DIR"
sha256sum * > checksums.sha256

# Save ground truth to hidden location
cp checksums.sha256 "$HIDDEN_GT_DIR/ground_truth_checksums.sha256"
chmod 600 "$HIDDEN_GT_DIR/ground_truth_checksums.sha256"

# Set permissions
chown -R ga:ga "$SOURCE_DIR"
chown -R ga:ga /home/ga/Documents

# 5. Start VeraCrypt
echo "Starting VeraCrypt..."
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

wait_for_window "VeraCrypt" 20
focus_window "$(get_veracrypt_window_id)"

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Sensitive data created in $SOURCE_DIR"
ls -la "$SOURCE_DIR"