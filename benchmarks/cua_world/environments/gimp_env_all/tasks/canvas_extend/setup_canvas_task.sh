#!/bin/bash
set -e

echo "=== Setting up canvas extension task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a portrait image suitable for canvas extension
echo "📥 Downloading portrait image for canvas extension..."
cd /home/ga/Desktop/
wget -q -O base_image.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=500&h=400&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O base_image.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&auto=format&fit=crop&w=500&h=400&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 500x400 xc:lightgray -fill darkblue -draw "rectangle 100,100 400,300" -fill white -pointsize 24 -gravity center -annotate +0+0 "EXTEND CANVAS" base_image.jpg
    }
}

# Set proper permissions
chown ga:ga base_image.jpg
chmod 644 base_image.jpg

echo "✅ Base image downloaded to /home/ga/Desktop/base_image.jpg"

echo "🎨 Opening GIMP with the base image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/base_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Canvas extension task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The base image is already open in GIMP"
echo "   2. Go to Image → Canvas Size"
echo "   3. Increase width by 200 pixels (e.g., 500→700)"
echo "   4. Increase height by 150 pixels (e.g., 400→550)"
echo "   5. Set anchor to center position in the 3x3 grid"
echo "   6. Choose fill color (white or foreground color)"
echo "   7. Click Resize to apply the canvas extension"
echo "   8. The export will be automated after editing"