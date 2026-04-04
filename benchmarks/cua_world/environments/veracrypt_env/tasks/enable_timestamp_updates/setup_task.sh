#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Enable Timestamp Updates Task ==="

# 1. Establish clean state
pkill -f veracrypt 2>/dev/null || true
sleep 1

# 2. Ensure configuration directory exists and set default (PreserveTimestamp = 1)
mkdir -p /home/ga/.config/VeraCrypt
cat > /home/ga/.config/VeraCrypt/Configuration.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<VeraCrypt>
    <Configuration>
        <PreserveTimestamp>1</PreserveTimestamp>
    </Configuration>
</VeraCrypt>
EOF
chown -R ga:ga /home/ga/.config

# 3. Create the evidence volume
echo "Creating evidence volume..."
# We create it with a specific password
veracrypt --text --create /home/ga/Volumes/evidence_locker.hc \
    --size=10M \
    --password='Audit2024!' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Set an old timestamp for the volume file (Anti-gaming baseline)
# Set to Jan 1, 2023
touch -t 202301011200 /home/ga/Volumes/evidence_locker.hc
INITIAL_MTIME=$(stat -c %Y /home/ga/Volumes/evidence_locker.hc)
echo "$INITIAL_MTIME" > /tmp/initial_volume_mtime.txt

# 5. Create the evidence file to be copied
echo "CONFIDENTIAL EVIDENCE FILE" > /home/ga/Documents/new_evidence.txt
echo "CASE ID: 99-4421" >> /home/ga/Documents/new_evidence.txt
echo "Collected: $(date)" >> /home/ga/Documents/new_evidence.txt
chown ga:ga /home/ga/Documents/new_evidence.txt

# 6. Start VeraCrypt GUI
echo "Starting VeraCrypt..."
su - ga -c "DISPLAY=:1 veracrypt &"
wait_for_window "VeraCrypt" 20

# 7. Record task start time
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Volume created: /home/ga/Volumes/evidence_locker.hc"
echo "Initial MTime: $(date -d @$INITIAL_MTIME)"