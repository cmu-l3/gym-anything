#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Encrypted Archives Task ==="

# Define paths
EVIDENCE_DIR="/home/ga/Volumes/Evidence"
RECOVERY_DIR="/home/ga/Documents/Recovery"
PASSWORD="Evidence2024"

mkdir -p "$EVIDENCE_DIR"
mkdir -p "$RECOVERY_DIR"

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

# Function to create a standard volume
create_volume() {
    local filename="$1"
    local size="$2"
    local pass="$3"
    
    echo "Creating $filename..."
    veracrypt --text --create "$EVIDENCE_DIR/$filename" \
        --size="$size" \
        --password="$pass" \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive
        
    # Add a dummy file inside to make it "Healthy"
    if [ "$pass" == "$PASSWORD" ]; then
        mkdir -p /tmp/vc_setup_mnt
        veracrypt --text --mount "$EVIDENCE_DIR/$filename" /tmp/vc_setup_mnt \
            --password="$pass" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive
            
        if mountpoint -q /tmp/vc_setup_mnt; then
            echo "Secret Evidence Data" > "/tmp/vc_setup_mnt/evidence_log.txt"
            veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
        fi
        rmdir /tmp/vc_setup_mnt 2>/dev/null || true
    fi
}

# --- CASE 001: Healthy ---
create_volume "case_001.hc" "5M" "$PASSWORD"

# --- CASE 002: Header Corrupt (Reparable) ---
create_volume "case_002.hc" "5M" "$PASSWORD"
# 1. Create header backup (VeraCrypt headers are first 128KB)
# We simulate a backup file provided to the user.
# A proper VeraCrypt header backup doesn't have a standard format via dd (it's embedded), 
# but the 'Restore Volume Header' GUI accepts a raw binary dump of the header if we force it,
# OR we can use VeraCrypt to export it properly.
# CLI command --backup-headers is not always strictly non-interactive or easy to target file.
# EASIEST VALID METHOD: Copy the first 128KB (131072 bytes) using dd. VeraCrypt accepts this.
dd if="$EVIDENCE_DIR/case_002.hc" of="$RECOVERY_DIR/case_002_header.bk" bs=131072 count=1 2>/dev/null
# 2. Corrupt the header in the file
dd if=/dev/urandom of="$EVIDENCE_DIR/case_002.hc" bs=131072 count=1 conv=notrunc 2>/dev/null
echo "Corrupted header of case_002.hc"

# --- CASE 003: Filesystem Corrupt ---
create_volume "case_003.hc" "5M" "$PASSWORD"
# Mount it, corrupt the inner filesystem, dismount
mkdir -p /tmp/vc_corrupt_mnt
veracrypt --text --mount "$EVIDENCE_DIR/case_003.hc" /tmp/vc_corrupt_mnt \
    --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive

# Find the loop device or mapper device
# We need to write zeros to the mapped device to destroy the FAT filesystem
MAPPER_DEV=$(mount | grep "/tmp/vc_corrupt_mnt" | awk '{print $1}')
if [ -n "$MAPPER_DEV" ]; then
    echo "Corrupting filesystem on $MAPPER_DEV..."
    # Overwrite the first 1MB of the inner volume
    dd if=/dev/zero of="$MAPPER_DEV" bs=1M count=2 conv=notrunc 2>/dev/null || true
fi
veracrypt --text --dismount /tmp/vc_corrupt_mnt --non-interactive 2>/dev/null || true
rmdir /tmp/vc_corrupt_mnt 2>/dev/null || true

# --- CASE 004: Inaccessible (Wrong Password / No Backup) ---
# We create it with a DIFFERENT password. Agent won't know.
create_volume "case_004.hc" "5M" "ImpossiblePass123"

# Set permissions
chown -R ga:ga "$EVIDENCE_DIR"
chown -R ga:ga "$RECOVERY_DIR"

# Focus VeraCrypt window
if wait_for_window "VeraCrypt" 10; then
    wid=$(get_veracrypt_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Cleanup
rm -f /home/ga/Documents/audit_report.csv 2>/dev/null

echo "=== Setup Complete ==="