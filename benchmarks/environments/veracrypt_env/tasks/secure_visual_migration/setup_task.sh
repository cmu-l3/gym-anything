#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Secure Visual Migration Task ==="

# 1. Setup Directories
TOKEN_DIR="/home/ga/Documents/Token_Images"
mkdir -p "$TOKEN_DIR"
rm -f "$TOKEN_DIR"/*

# 2. Generate Visual Keyfiles (using ImageMagick to create robust "visual" tokens)
# We use text burned into images to ensure fair "visual" identification without 
# relying on external VLM stability for natural scene recognition of downloaded images.
# To the agent, these are just images they need to open/preview to identify.

echo "Generating visual tokens..."

# Define tokens
TOKENS=("Lighthouse" "Mountain" "Forest" "Desert" "Ocean")
# Array to store filenames for answer key
declare -A KEYFILES

# Generate images with randomized filenames
for label in "${TOKENS[@]}"; do
    # Generate random filename hash
    FNAME="token_$(echo "$label$RANDOM" | md5sum | cut -c1-8).jpg"
    
    # Create image: 400x400 background with label text centered
    convert -size 400x400 xc:lightblue \
        -gravity Center -pointsize 40 -fill black -annotate 0 "$label" \
        "$TOKEN_DIR/$FNAME"
    
    KEYFILES[$label]="$TOKEN_DIR/$FNAME"
done

SOURCE_KEY="${KEYFILES[Lighthouse]}"
DEST_KEY="${KEYFILES[Mountain]}"

echo "Source Key (Lighthouse): $SOURCE_KEY"
echo "Dest Key (Mountain): $DEST_KEY"

# Save answer key for export script (hidden location)
mkdir -p /var/lib/veracrypt_task
cat > /var/lib/veracrypt_task/answers.env << EOF
SOURCE_KEY_PATH="$SOURCE_KEY"
DEST_KEY_PATH="$DEST_KEY"
EOF
chmod 600 /var/lib/veracrypt_task/answers.env

# 3. Create Source Volume
echo "Creating source volume..."
# We must use CLI to create volume with keyfile
# Note: VeraCrypt CLI keyfile syntax can be tricky.
veracrypt --text --create /home/ga/Volumes/old_storage.hc \
    --size=20M \
    --password='VisualAccess2024' \
    --keyfiles="$SOURCE_KEY" \
    --pim=0 \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Populate Source Volume
echo "Populating source volume..."
mkdir -p /tmp/vc_setup_mount

veracrypt --text --mount /home/ga/Volumes/old_storage.hc /tmp/vc_setup_mount \
    --password='VisualAccess2024' \
    --keyfiles="$SOURCE_KEY" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

if mountpoint -q /tmp/vc_setup_mount; then
    # Copy sample data
    cp /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/FY2024_Revenue_Budget.csv /tmp/vc_setup_mount/
    cp /workspace/assets/sample_data/backup_authorized_keys /tmp/vc_setup_mount/
    
    # Verify copy
    ls -la /tmp/vc_setup_mount/
    
    # Dismount
    veracrypt --text --dismount /tmp/vc_setup_mount --non-interactive
    sleep 1
else
    echo "ERROR: Failed to mount source volume for population"
    exit 1
fi
rmdir /tmp/vc_setup_mount 2>/dev/null || true

# 5. Create Instructions File (optional, as task desc is primary, but good for immersion)
cat > /home/ga/Documents/instructions.txt << EOF
MIGRATION INSTRUCTIONS
----------------------
Source Volume: /home/ga/Volumes/old_storage.hc
Source Password: VisualAccess2024
Source Keyfile: The image containing a "Lighthouse"

Destination Volume: /home/ga/Volumes/new_storage.hc (CREATE THIS)
Destination Password: Migrated#Secure99
Destination Keyfile: The image containing a "Mountain"
Destination PIM: 485

Task: Transfer all files from Source to Destination.
EOF

# 6. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20

# Maximize and Focus
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 7. Record Start Time
date +%s > /tmp/task_start_time.txt

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="