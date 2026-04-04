#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up horizontal mirror task ==="

# Download the berry image
echo "📥 Downloading berry image..."
wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/72f83cdc-bf76-4531-9a1b-eb893a13f8aa/berry.jpeg" \
     -O "/home/ga/Desktop/berry.png"

# Set proper ownership
chown ga:ga "/home/ga/Desktop/berry.png"
chmod 644 "/home/ga/Desktop/berry.png"

echo "✅ Image downloaded to /home/ga/Desktop/berry.png"

# Wait a moment for file system sync
sleep 1

# Open GIMP with the image as ga user
echo "🎨 Opening GIMP with the berry image..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/berry.png > /tmp/gimp_mirror.log 2>&1 &"

# Wait for GIMP to start
sleep 5

echo "=== Mirror task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The berry image is already open in GIMP"
echo "   2. Use Image > Transform > Flip Horizontally (or similar)"
echo "   3. The export will be automated after editing"
