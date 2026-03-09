#!/bin/bash
set -e

echo "=== Setting up threshold effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with good mid-tone content suitable for thresholding
echo "📥 Downloading portrait image for threshold effect..."
cd /home/ga/Desktop/
wget -q -O portrait_threshold.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_threshold.jpg "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&auto=format&fit=crop&w=688&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:gray70 -fill gray30 -draw "circle 300,200 150,200" -fill black -pointsize 24 -gravity center -annotate +0+150 "THRESHOLD ME" portrait_threshold.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_threshold.jpg
chmod 644 portrait_threshold.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_threshold.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_threshold.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Threshold effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Colors → Threshold"
echo "   3. Adjust the threshold slider to create good black/white balance"
echo "   4. Aim for approximately 120-140 threshold value for good results"
echo "   5. Click OK to apply the threshold effect"
echo "   6. The export will be automated after editing"