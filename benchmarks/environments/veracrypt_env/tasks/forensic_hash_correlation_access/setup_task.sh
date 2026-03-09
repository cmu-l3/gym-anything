#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Forensic Hash Correlation Task ==="

# 1. Prepare Directory Structure
EVIDENCE_DIR="/home/ga/Evidence"
KEYFILES_DIR="$EVIDENCE_DIR/Keyfiles"
GROUND_TRUTH_DIR="/var/lib/veracrypt"

mkdir -p "$KEYFILES_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "/home/ga/MountPoints/slot1"

# Clean up any previous run artifacts
rm -f "$EVIDENCE_DIR/sequestered_data.hc"
rm -f "$EVIDENCE_DIR/clue.txt"
rm -f "$EVIDENCE_DIR/extracted_flag.txt"
rm -f "$KEYFILES_DIR"/*
rm -f "$GROUND_TRUTH_DIR/ground_truth_flag.txt"

# 2. Generate Candidate Keyfiles (Noise)
echo "Generating candidate keyfiles..."
# Create 50 random files with random names and content
for i in {1..50}; do
    # Generate random filename
    FNAME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1).dat
    # Generate random content (1KB - 4KB)
    dd if=/dev/urandom of="$KEYFILES_DIR/$FNAME" bs=1024 count=$((1 + RANDOM % 4)) status=none
done

# 3. Select one file as the "Correct" Keyfile
CORRECT_KEYFILE=$(ls "$KEYFILES_DIR" | sort -R | head -n 1)
CORRECT_KEYFILE_PATH="$KEYFILES_DIR/$CORRECT_KEYFILE"
echo "Selected keyfile: $CORRECT_KEYFILE"

# 4. Calculate Hash and Create Clue
FULL_HASH=$(sha256sum "$CORRECT_KEYFILE_PATH" | awk '{print $1}')
# Take first 10 characters
HASH_FRAGMENT=${FULL_HASH:0:10}

echo "Keyfile SHA256 starts with: $HASH_FRAGMENT" > "$EVIDENCE_DIR/clue.txt"
chmod 644 "$EVIDENCE_DIR/clue.txt"

# 5. Create Encrypted Volume with this Keyfile
VOLUME_PATH="$EVIDENCE_DIR/sequestered_data.hc"
PASSWORD="Investigation2024"

echo "Creating encrypted volume..."
# Note: VeraCrypt CLI requires careful handling.
# --keyfiles arg takes the path.
veracrypt --text --create "$VOLUME_PATH" \
    --size=5M \
    --password="$PASSWORD" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="$CORRECT_KEYFILE_PATH" \
    --random-source=/dev/urandom \
    --non-interactive

# 6. Mount volume to insert the Flag
echo "Mounting to insert flag..."
mkdir -p /tmp/vc_setup_mount

veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_setup_mount \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="$CORRECT_KEYFILE_PATH" \
    --protect-hidden=no \
    --non-interactive

# Generate Flag
FLAG_CONTENT="FLAG-$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 16 | head -n 1)"
echo "$FLAG_CONTENT" > /tmp/vc_setup_mount/flag.txt
# Save ground truth (hidden from agent)
echo "$FLAG_CONTENT" > "$GROUND_TRUTH_DIR/ground_truth_flag.txt"
chmod 600 "$GROUND_TRUTH_DIR/ground_truth_flag.txt"

# Add some dummy files
echo "Confidential data..." > /tmp/vc_setup_mount/case_notes.doc
dd if=/dev/urandom of=/tmp/vc_setup_mount/image001.jpg bs=1024 count=10 status=none

# Dismount
veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
rmdir /tmp/vc_setup_mount

# 7. Final Environment State
chown -R ga:ga "$EVIDENCE_DIR"
chown -R ga:ga "/home/ga/MountPoints"

# Record Start Time
date +%s > /tmp/task_start_time.txt

# Start VeraCrypt GUI for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

# Wait for window and focus
wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Keyfile: $CORRECT_KEYFILE"
echo "Hash Fragment: $HASH_FRAGMENT"
echo "Flag: $FLAG_CONTENT"