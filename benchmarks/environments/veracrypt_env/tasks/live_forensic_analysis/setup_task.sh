#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Live Forensic Analysis Task ==="

# 1. Clean up previous state
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Documents/forensic_report.json
rm -f /tmp/task_truth.json
kill_veracrypt

# 2. Randomize Parameters
# Arrays of options
ALGOS=("AES" "Twofish" "Serpent" "Camellia")
HASHES=("SHA-512" "Whirlpool" "SHA-256")
PATHS=(
    "/home/ga/.local/share/sys_cache.dat"
    "/home/ga/.config/gnome-session/session.bin"
    "/home/ga/Downloads/iso_update_2024.img"
    "/home/ga/Pictures/thumbnails.db"
    "/home/ga/.cache/mozilla/firefox/profile.dat"
)

# Seed random generator
RANDOM=$$$(date +%s)

# Select random values
ALGO=${ALGOS[$RANDOM % ${#ALGOS[@]}]}
HASH=${HASHES[$RANDOM % ${#HASHES[@]}]}
CONTAINER_PATH=${PATHS[$RANDOM % ${#PATHS[@]}]}
PASSWORD="ForensicTest${RANDOM}"

# Ensure directory exists
DIR_NAME=$(dirname "$CONTAINER_PATH")
mkdir -p "$DIR_NAME"
chown ga:ga "$DIR_NAME"

echo "Setup Config: $ALGO / $HASH @ $CONTAINER_PATH"

# 3. Create the Volume
echo "Creating volume..."
veracrypt --text --create "$CONTAINER_PATH" \
    --size=10M \
    --password="$PASSWORD" \
    --encryption="$ALGO" \
    --hash="$HASH" \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# Fix permissions
chown ga:ga "$CONTAINER_PATH"

# 4. Mount the Volume (at slot 2 specifically)
echo "Mounting volume..."
mkdir -p /home/ga/MountPoints/slot2
chown ga:ga /home/ga/MountPoints/slot2

veracrypt --text --mount "$CONTAINER_PATH" /home/ga/MountPoints/slot2 \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --slot=2 \
    --non-interactive

# 5. Populate with random files
FILE_COUNT=$((5 + $RANDOM % 10)) # 5 to 14 files
echo "Populating with $FILE_COUNT files..."

for i in $(seq 1 $FILE_COUNT); do
    # Create dummy files with random names and sizes
    FNAME="evidence_$(date +%s%N | sha256sum | head -c 8).txt"
    dd if=/dev/urandom of="/home/ga/MountPoints/slot2/$FNAME" bs=1024 count=$((1 + $RANDOM % 10)) 2>/dev/null
done

# Sync to ensure write
sync

# 6. Save Ground Truth (Hidden from agent)
# We save this to a root-owned file to prevent easy peeking, but accessible to export script
cat > /root/.task_truth.json << EOF
{
    "container_path": "$CONTAINER_PATH",
    "encryption_algorithm": "$ALGO",
    "hash_algorithm": "$HASH",
    "file_count": $FILE_COUNT,
    "password": "$PASSWORD"
}
EOF
chmod 600 /root/.task_truth.json

# 7. Start GUI (Agent needs to see it mounted)
echo "Starting VeraCrypt GUI..."
su - ga -c "DISPLAY=:1 veracrypt &"

# Wait for window
wait_for_window "VeraCrypt" 20

# Minimize or leave standard? Task says "already mounted", standard view is fine.
# We ensure the window is visible.
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure it's not minimized
    DISPLAY=:1 wmctrl -i -r "$wid" -b remove,hidden,shaded 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="