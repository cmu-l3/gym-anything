#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up green background task ==="

# Download the XCF file (GIMP project file)
echo "📥 Downloading XCF project file..."
wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/734d6579-c07d-47a8-9ae2-13339795476b/white_background_with_object.xcf" \
     -O "/home/ga/Desktop/white_background_with_object.xcf"

# Download the reference PNG file
echo "📥 Downloading reference PNG file..."
wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/734d6579-c07d-47a8-9ae2-13339795476b/white_background_with_object.png" \
     -O "/home/ga/Desktop/white_background_with_object.png"

# Set proper ownership
chown ga:ga "/home/ga/Desktop/white_background_with_object.xcf"
chown ga:ga "/home/ga/Desktop/white_background_with_object.png"
chmod 644 "/home/ga/Desktop/white_background_with_object.xcf"
chmod 644 "/home/ga/Desktop/white_background_with_object.png"

echo "✅ Files downloaded to /home/ga/Desktop/"

# Wait a moment for file system sync
sleep 1

# Open GIMP with the XCF file as ga user
echo "🎨 Opening GIMP with the XCF project file..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/white_background_with_object.xcf > /tmp/gimp_green.log 2>&1 &"

# Wait for GIMP to start and load the project
sleep 5

echo "=== Green background task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The XCF project with layers is already open in GIMP"
echo "   2. Select the background layer"
echo "   3. Fill it with green color (use bucket fill or color fill)"
echo "   4. Keep the object layer unchanged"
echo "   5. The export will be automated after editing"
