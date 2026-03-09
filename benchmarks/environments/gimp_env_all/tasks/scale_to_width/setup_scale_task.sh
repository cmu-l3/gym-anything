#!/bin/bash
set -e

echo "=== Setting up scale to width task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download landscape image for scaling
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1200&h=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&h=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 1200x800 xc:lightblue -fill darkblue -pointsize 36 -gravity center -annotate +0+0 "SCALE TO 800px WIDTH" landscape_image.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_image.jpg
chmod 644 landscape_image.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_scale.log 2>&1 &"

sleep 3

echo "=== Scale to width task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Image → Scale Image"
echo "   3. Make sure the chain-link icon is connected (aspect ratio locked)"
echo "   4. Change the width to 800 pixels"
echo "   5. The height should automatically adjust to maintain aspect ratio"
echo "   6. Click 'Scale' to apply the resize"
echo "   7. The export will be automated after scaling"