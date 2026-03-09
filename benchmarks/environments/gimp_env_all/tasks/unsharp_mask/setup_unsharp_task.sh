#!/bin/bash
set -e

echo "=== Setting up Unsharp Mask task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv-contrib-python || true

# Download a portrait photo that would benefit from sharpening
echo "📥 Downloading portrait photo..."
cd /home/ga/Desktop/
wget -q -O portrait_photo.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_photo.jpg "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with details if download fails
        convert -size 800x600 xc:lightgray -fill darkgray -draw "circle 400,300 400,200" -fill black -pointsize 24 -gravity center -annotate +0+100 "SHARPEN THIS IMAGE" portrait_photo.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_photo.jpg
chmod 644 portrait_photo.jpg

echo "✅ Portrait photo downloaded to /home/ga/Desktop/portrait_photo.jpg"

echo "🎨 Opening GIMP with the portrait photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Unsharp Mask task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait photo is already open in GIMP"
echo "   2. Go to Filters → Enhance → Unsharp Mask"
echo "   3. In the dialog that opens:"
echo "      - Set Radius to around 1.5 pixels"
echo "      - Set Amount to around 1.0"
echo "      - Keep Threshold at 0"
echo "   4. Enable Preview to see the effect"
echo "   5. Click OK to apply the sharpening"
echo "   6. The export will be automated after editing"