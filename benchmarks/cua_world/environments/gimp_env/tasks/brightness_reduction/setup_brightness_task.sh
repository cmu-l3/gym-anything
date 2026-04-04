#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up brightness reduction task ==="

# Ensure required packages are available
if ! command -v wget &> /dev/null; then
    echo "Installing required packages..."
    apt-get update && apt-get install -y wget python3-pil python3-numpy
fi

# Also install Python packages for the verifier
python3 -c "import PIL, numpy" 2>/dev/null || {
    echo "Installing Python packages for verification..."
    apt-get install -y python3-pip python3-pil python3-numpy || pip3 install Pillow numpy
}

# Download the test image
echo "📥 Downloading test image..."
wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/7a4deb26-d57d-4ea9-9a73-630f66a7b568/woman_sitting_by_the_tree.png" \
     -O "/home/ga/Desktop/woman_sitting_by_the_tree.png"

# Set proper ownership
chown ga:ga "/home/ga/Desktop/woman_sitting_by_the_tree.png"
chmod 644 "/home/ga/Desktop/woman_sitting_by_the_tree.png"

echo "✅ Image downloaded to /home/ga/Desktop/woman_sitting_by_the_tree.png"

# Wait a moment for file system sync
sleep 1

# Open GIMP with the image as ga user
echo "🎨 Opening GIMP with the image..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/woman_sitting_by_the_tree.png > /tmp/gimp_task.log 2>&1 &"

# Wait for GIMP to start
sleep 5

echo "=== Task setup completed! Agent should now reduce brightness ==="
echo "💡 Instructions for agent:"
echo "   1. The image is already open in GIMP"
echo "   2. Use Colors > Brightness-Contrast or similar tools"
echo "   3. Reduce brightness while keeping structure intact"
echo "   4. The export will be automated after editing"
