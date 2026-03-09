#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Provision Volume Migration Task ==="

# 1. Clean up previous run artifacts
echo "Cleaning up..."
rm -rf /home/ga/Volumes/Issued
mkdir -p /home/ga/Volumes/Issued
rm -f /home/ga/Volumes/onboarding_template.hc

# 2. Create the Template Volume (AES)
echo "Creating template volume..."
veracrypt --text --create /home/ga/Volumes/onboarding_template.hc \
    --size=10M \
    --password='TemplatePass123' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Create Sample Data content
# We create these in a temp dir then copy into the volume
mkdir -p /tmp/template_data

# File 1: Project Protocol (Fake PDF content)
cat > /tmp/template_data/Project_Chimera_Protocol.pdf << EOF
%PDF-1.4
%
1 0 obj
<<
/Title (Project Chimera Security Protocol)
/Author (Security Officer)
/Subject (Classified)
>>
endobj
DATA:
1. All participants must use Serpent-encrypted volumes.
2. Communications must be via signal.
3. No physical media allowed in Sector 7.
EOF

# File 2: Contact List (CSV)
cat > /tmp/template_data/Emergency_Contact_List.csv << EOF
ID,Name,Role,SecurePhone,ClearanceLevel
101,John Doe,Project Lead,555-0101,TS/SCI
102,Jane Smith,Cryptanalyst,555-0102,TS
103,Bob Johnson,Sysadmin,555-0103,Secret
104,Alice Brown,Logistics,555-0104,Confidential
105,Charlie Davis,Security,555-0105,TS/SCI
EOF

# File 3: Financial Forecast (Fake Excel/XLSX - just text for this env)
cat > /tmp/template_data/Q3_Financial_Forecast.xlsx << EOF
PK...[header]...
Sheet1:
Category,Budget,Spent,Remaining
Hardware,50000,12000,38000
Software,25000,15000,10000
Personnel,150000,45000,105000
Travel,10000,2000,8000
EOF

# 4. Mount template and copy data
echo "Populating template volume..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/onboarding_template.hc /tmp/vc_setup_mount \
    --password='TemplatePass123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mount; then
    cp /tmp/template_data/* /tmp/vc_setup_mount/
    sync
    ls -la /tmp/vc_setup_mount/
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
else
    echo "ERROR: Failed to mount template volume for setup!"
    exit 1
fi

rm -rf /tmp/template_data
rmdir /tmp/vc_setup_mount

# 5. Calculate hashes of source files for verification later
# We mount read-only just to get hashes then dismount
mkdir -p /tmp/vc_hash_check
veracrypt --text --mount /home/ga/Volumes/onboarding_template.hc /tmp/vc_hash_check \
    --password='TemplatePass123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_hash_check; then
    md5sum /tmp/vc_hash_check/* > /tmp/source_hashes.txt
    veracrypt --text --dismount /tmp/vc_hash_check --non-interactive
fi
rmdir /tmp/vc_hash_check

# 6. Ensure VeraCrypt GUI is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 15
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="