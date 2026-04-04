#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Forensic Identification Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_veracrypt
rm -rf /home/ga/Evidence 2>/dev/null || true
mkdir -p /home/ga/Evidence/seized_files

echo "Creating evidence files..."

# 1. archive_2024.dat (AES, SHA-512)
veracrypt --text --create /home/ga/Evidence/seized_files/archive_2024.dat \
    --size=5M --password='Evidence2024!' --encryption=AES --hash=SHA-512 \
    --filesystem=FAT --pim=0 --keyfiles='' --random-source=/dev/urandom --non-interactive

# 2. notes.dat (Serpent, SHA-256)
veracrypt --text --create /home/ga/Evidence/seized_files/notes.dat \
    --size=5M --password='SecretNotes99' --encryption=Serpent --hash=SHA-256 \
    --filesystem=FAT --pim=0 --keyfiles='' --random-source=/dev/urandom --non-interactive

# 3. personal.dat (Twofish, Whirlpool)
veracrypt --text --create /home/ga/Evidence/seized_files/personal.dat \
    --size=5M --password='MyPersonal#1' --encryption=Twofish --hash=Whirlpool \
    --filesystem=FAT --pim=0 --keyfiles='' --random-source=/dev/urandom --non-interactive

# 4. financial.dat (Camellia, SHA-512)
veracrypt --text --create /home/ga/Evidence/seized_files/financial.dat \
    --size=5M --password='Finance$2024' --encryption=Camellia --hash=SHA-512 \
    --filesystem=FAT --pim=0 --keyfiles='' --random-source=/dev/urandom --non-interactive

# Create decoy files (Random data, same size approx)
dd if=/dev/urandom of=/home/ga/Evidence/seized_files/backup_0312.img bs=1M count=5 status=none
dd if=/dev/urandom of=/home/ga/Evidence/seized_files/system_dump.bin bs=1M count=5 status=none
dd if=/dev/urandom of=/home/ga/Evidence/seized_files/swap_backup.raw bs=1M count=5 status=none
dd if=/dev/urandom of=/home/ga/Evidence/seized_files/photos.enc bs=1M count=5 status=none

# Create candidate passwords file
cat > /home/ga/Evidence/candidate_passwords.txt << 'EOF'
Evidence2024!
WrongPassword1
SecretNotes99
AnotherWrong
MyPersonal#1
NotTheRight1
Finance$2024
TryThisOne
EOF

# Set permissions
chown -R ga:ga /home/ga/Evidence

# Start VeraCrypt GUI
echo "Starting VeraCrypt..."
su - ga -c "DISPLAY=:1 veracrypt &"

# Wait for window
wait_for_window "VeraCrypt" 20

# Maximize and focus
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_window "$(get_veracrypt_window_id)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="