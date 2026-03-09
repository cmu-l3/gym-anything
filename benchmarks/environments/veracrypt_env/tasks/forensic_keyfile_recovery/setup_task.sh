#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Forensic Keyfile Recovery Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Directories
BASE_DIR="/home/ga/Investigation"
PHOTO_DIR="$BASE_DIR/vacation_photos"
RECOVERY_DIR="/home/ga/recovered_data"
MOUNT_POINT="/home/ga/MountPoints/evidence"
GROUND_TRUTH="/var/lib/app/ground_truth"

# Ensure clean state
rm -rf "$BASE_DIR" "$RECOVERY_DIR" "$MOUNT_POINT" 2>/dev/null || true
mkdir -p "$PHOTO_DIR"
mkdir -p "$RECOVERY_DIR"
mkdir -p "$MOUNT_POINT"
mkdir -p "$GROUND_TRUTH"

# 2. Generate Candidate Images (Decoys + Real Keyfile)
echo "Generating 30 candidate images..."
# We use ImageMagick to create distinct images
for i in {1001..1030}; do
    # Create valid JPEG images with unique colors/text so they are binary distinct
    # Random color for background
    R=$((RANDOM%255))
    G=$((RANDOM%255))
    B=$((RANDOM%255))
    
    convert -size 640x480 xc:"rgb($R,$G,$B)" \
            -gravity center -pointsize 24 -annotate 0 "Vacation Photo $i - $(date)" \
            "$PHOTO_DIR/IMG_$i.jpg"
done

# 3. Select Random Keyfile
# Pick a random number between 1001 and 1030
RAND_NUM=$((1001 + RANDOM % 30))
KEYFILE_NAME="IMG_${RAND_NUM}.jpg"
KEYFILE_PATH="$PHOTO_DIR/$KEYFILE_NAME"
echo "Selected keyfile: $KEYFILE_NAME"

# Store the correct keyfile name for verification (hidden from agent)
echo "$KEYFILE_NAME" > "$GROUND_TRUTH/correct_keyfile.txt"
chmod 600 "$GROUND_TRUTH/correct_keyfile.txt"

# 4. Create Content to Encrypt
SECRET_FILE="/tmp/prototype_specs.txt"
cat > "$SECRET_FILE" << 'EOF'
CONFIDENTIAL - INTERNAL USE ONLY
PROJECT BLUESKY - PROTOTYPE SPECIFICATIONS

Torque Output: 450 Nm @ 4500 RPM
Battery Capacity: 105 kWh
Thermal Cutoff: 145 C
Encryption Key: 77-89-AA-BB-CC-12

Warning: This document contains trade secrets.
Do not distribute outside the engineering team.
EOF

# Store hash for verification
md5sum "$SECRET_FILE" | awk '{print $1}' > "$GROUND_TRUTH/specs_hash.md5"

# 5. Create Encrypted Volume
VOLUME_PATH="$BASE_DIR/design_specs.hc"
echo "Creating encrypted volume..."

# VeraCrypt creation requires non-interactive mode
# We use AES(Twofish(Serpent)) for complexity, standard FAT filesystem
veracrypt --text --create "$VOLUME_PATH" \
    --size=5M \
    --password="BlueSky2024" \
    --keyfiles="$KEYFILE_PATH" \
    --pim=0 \
    --encryption="AES(Twofish(Serpent))" \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# 6. Add Data to Volume
echo "Mounting to add data..."
veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
    --password="BlueSky2024" \
    --keyfiles="$KEYFILE_PATH" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

# Copy secret file in
cp "$SECRET_FILE" "$MOUNT_POINT/prototype_specs.txt"
rm "$SECRET_FILE"

# Dismount
sync
veracrypt --text --dismount "$MOUNT_POINT" --non-interactive

# 7. Final Cleanup and Permissions
chown -R ga:ga "$BASE_DIR"
chown -R ga:ga "$RECOVERY_DIR"
chown -R ga:ga "$MOUNT_POINT"
# Ground truth remains root-owned so agent cannot peek easily

# Ensure VeraCrypt GUI is running for the user
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Maximize VeraCrypt window
if wait_for_window "VeraCrypt" 10; then
    WID=$(get_veracrypt_window_id)
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="