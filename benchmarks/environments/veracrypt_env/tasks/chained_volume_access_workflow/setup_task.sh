#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Chained Volume Access Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

VOL_DIR="/home/ga/Volumes"
TEMP_MOUNT="/tmp/vc_setup_mount"
mkdir -p "$VOL_DIR" "$TEMP_MOUNT"

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Dismount anything existing
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# --- Step 1: Generate Keyfiles & Data ---
echo "Generating assets..."

# Key for Beta (hidden in Alpha)
dd if=/dev/urandom of=/tmp/beta_token.jpg bs=1024 count=5 2>/dev/null
# Key for Gamma (hidden in Beta)
dd if=/dev/urandom of=/tmp/gamma_token.wav bs=1024 count=10 2>/dev/null

# Target Data (hidden in Gamma)
# We use fixed content to ensure a known MD5 hash for verification
# Content: ID,Latitude,Longitude,Description
# MD5 of this specific content should be: e5b85368670878146958428286594247
cat > /tmp/coordinates.csv << 'EOF'
ID,Latitude,Longitude,Description
1,34.0522,-118.2437,ExtractPoint_Alpha
2,40.7128,-74.0060,DropZone_Bravo
3,51.5074,-0.1278,SafeHouse_Charlie
4,35.6895,139.6917,Relay_Delta
EOF

# --- Step 2: Create Volume Gamma (Vault) ---
# Requires: Password + gamma_token.wav
echo "Creating Gamma Vault..."
veracrypt --text --create "$VOL_DIR/gamma_vault.hc" \
    --size=10M \
    --password="VaultCoreTopSecret" \
    --keyfiles="/tmp/gamma_token.wav" \
    --pim=0 \
    --encryption=Serpent \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# Mount Gamma and add target data
echo "Populating Gamma Vault..."
veracrypt --text --mount "$VOL_DIR/gamma_vault.hc" "$TEMP_MOUNT" \
    --password="VaultCoreTopSecret" \
    --keyfiles="/tmp/gamma_token.wav" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

cp /tmp/coordinates.csv "$TEMP_MOUNT/"
sync
veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive

# --- Step 3: Create Volume Beta (Relay) ---
# Requires: Password + beta_token.jpg
# Contains: gamma_token.wav
echo "Creating Beta Relay..."
veracrypt --text --create "$VOL_DIR/beta_relay.hc" \
    --size=10M \
    --password="RelayStationSecure" \
    --keyfiles="/tmp/beta_token.jpg" \
    --pim=0 \
    --encryption=Twofish \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# Mount Beta and add Gamma key
echo "Populating Beta Relay..."
veracrypt --text --mount "$VOL_DIR/beta_relay.hc" "$TEMP_MOUNT" \
    --password="RelayStationSecure" \
    --keyfiles="/tmp/beta_token.jpg" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

cp /tmp/gamma_token.wav "$TEMP_MOUNT/"
sync
veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive

# --- Step 4: Create Volume Alpha (Entry) ---
# Requires: Password only
# Contains: beta_token.jpg
echo "Creating Alpha Entry..."
veracrypt --text --create "$VOL_DIR/alpha_entry.hc" \
    --size=10M \
    --password="EntryLevelAccess2024" \
    --keyfiles="" \
    --pim=0 \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# Mount Alpha and add Beta key
echo "Populating Alpha Entry..."
veracrypt --text --mount "$VOL_DIR/alpha_entry.hc" "$TEMP_MOUNT" \
    --password="EntryLevelAccess2024" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

cp /tmp/beta_token.jpg "$TEMP_MOUNT/"
sync
veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive

# --- Cleanup & Finalize ---
rm -f /tmp/beta_token.jpg /tmp/gamma_token.wav /tmp/coordinates.csv
rmdir "$TEMP_MOUNT" 2>/dev/null || true
chown -R ga:ga "$VOL_DIR"

# Ensure VeraCrypt window is visible and focused
if wait_for_window "VeraCrypt" 10; then
    wid=$(get_veracrypt_window_id)
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="