#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Access Recovery Task ==="

# 1. Clean up previous runs
rm -rf /home/ga/Documents/Recovered
mkdir -p /home/ga/Documents/Recovered
rm -f /home/ga/Volumes/project_alpha_archive.hc
rm -f /home/ga/Documents/potential_passwords.txt
rm -f /root/task_ground_truth.json

# 2. Generate Candidate Passwords
# We create a list of 8 plausible passwords
cat > /tmp/all_passwords.txt << EOF
AlphaProject2023!
ProjectAlpha_2024
Alpha_Main_Secure
P@ssw0rd_Alpha
Secure!Alpha#99
AlphaTeam_Archive
Project_A_Backup
Alpha2024_Admin
EOF

# 3. Select one random password as correct
CORRECT_PASSWORD=$(shuf -n 1 /tmp/all_passwords.txt)
echo "Selected correct password: $CORRECT_PASSWORD"

# 4. Create the Password List file for the agent (shuffle them so position doesn't give it away)
shuf /tmp/all_passwords.txt > /home/ga/Documents/potential_passwords.txt
chown ga:ga /home/ga/Documents/potential_passwords.txt

# 5. Create the PDF file to be hidden
# Create a dummy PDF with unique content for this run to verify integrity
PDF_CONTENT="CONFIDENTIAL PROJECT ALPHA SUMMARY - $(date +%s)"
echo "$PDF_CONTENT" > /tmp/Project_Alpha_Summary.pdf
# Calculate hash of the source file
EXPECTED_HASH=$(sha256sum /tmp/Project_Alpha_Summary.pdf | awk '{print $1}')

# 6. Create the Encrypted Volume with the CORRECT password
echo "Creating encrypted volume..."
veracrypt --text --create /home/ga/Volumes/project_alpha_archive.hc \
    --size=10M \
    --password="$CORRECT_PASSWORD" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 7. Mount, Copy Data, Dismount
echo "Populating volume..."
mkdir -p /tmp/vc_setup_mount
veracrypt --text --mount /home/ga/Volumes/project_alpha_archive.hc /tmp/vc_setup_mount \
    --password="$CORRECT_PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Copy the file in
cp /tmp/Project_Alpha_Summary.pdf /tmp/vc_setup_mount/
ls -la /tmp/vc_setup_mount/

# Dismount
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
rmdir /tmp/vc_setup_mount
rm -f /tmp/Project_Alpha_Summary.pdf

# 8. Store Ground Truth (Hidden from agent in /root)
# We escape the password for JSON
SAFE_PASSWORD=$(echo "$CORRECT_PASSWORD" | sed 's/"/\\"/g')
cat > /root/task_ground_truth.json << EOF
{
    "correct_password": "$SAFE_PASSWORD",
    "expected_file_hash": "$EXPECTED_HASH"
}
EOF
chmod 600 /root/task_ground_truth.json

# 9. UI Setup
# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="