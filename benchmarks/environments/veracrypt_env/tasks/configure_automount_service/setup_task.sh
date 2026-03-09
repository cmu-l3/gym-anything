#!/bin/bash
set -e
echo "=== Setting up Configure Automount Service Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
VOL_PATH="/home/ga/Volumes/media_vault.hc"
KEY_PATH="/home/ga/Keyfiles/media_server.key"
MOUNT_POINT="/mnt/media_vault"

# 1. Clean up previous state
echo "Cleaning up previous state..."
veracrypt --text --dismount --force >/dev/null 2>&1 || true
# Stop and remove service if exists
if systemctl is-active --quiet veracrypt-media.service; then
    systemctl stop veracrypt-media.service
fi
if systemctl is-enabled --quiet veracrypt-media.service; then
    systemctl disable veracrypt-media.service
fi
rm -f "/etc/systemd/system/veracrypt-media.service"
systemctl daemon-reload 2>/dev/null || true

rm -f "$VOL_PATH"
rm -f "$KEY_PATH"
rm -rf "$MOUNT_POINT"

# 2. Create Mount Point
mkdir -p "$MOUNT_POINT"

# 3. Generate Keyfile (64 bytes random)
echo "Generating keyfile..."
mkdir -p "$(dirname "$KEY_PATH")"
dd if=/dev/urandom of="$KEY_PATH" bs=1 count=64 status=none
chown ga:ga "$KEY_PATH"
chmod 600 "$KEY_PATH"

# 4. Create Volume with Keyfile AND NO PASSWORD
# Note: --password="" is required for keyfile-only auth
echo "Creating encrypted volume (this may take a moment)..."
veracrypt --text --create "$VOL_PATH" \
    --size=10M \
    --password="" \
    --keyfiles="$KEY_PATH" \
    --pim=0 \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --random-source=/dev/urandom \
    --non-interactive

# 5. Populate Volume with Data
echo "Populating volume with sample data..."
mkdir -p /tmp/vc_setup_mnt
veracrypt --text --mount "$VOL_PATH" /tmp/vc_setup_mnt \
    --password="" \
    --keyfiles="$KEY_PATH" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

# Create sample data files
cat > /tmp/vc_setup_mnt/catalog.csv << EOF
ID,Title,Format,Duration,Size_MB
101,"Corporate Overview 2024",MP4,04:23,150
102,"Product Demo v2",MOV,02:15,85
103,"Q1 All Hands",MP4,58:10,1200
104,"Safety Training",AVI,12:00,450
EOF

cat > /tmp/vc_setup_mnt/playlist.m3u << EOF
#EXTM3U
#EXTINF:263,Corporate Overview
/storage/media/corp_overview.mp4
#EXTINF:135,Product Demo
/storage/media/prod_demo.mov
EOF

# Dismount setup mount
veracrypt --text --dismount /tmp/vc_setup_mnt --non-interactive
rmdir /tmp/vc_setup_mnt

# Set permissions
chown ga:ga "$VOL_PATH"
# Mount point ownership
chown ga:ga "$MOUNT_POINT"

# Record start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Volume: $VOL_PATH"
echo "Keyfile: $KEY_PATH"
echo "Target Mount: $MOUNT_POINT"