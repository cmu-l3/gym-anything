#!/bin/bash
set -e

echo "=== Setting up saturation enhancement task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a nature image that would benefit from saturation enhancement
echo "📥 Downloading nature image..."
cd /home/ga/Desktop/
wget -q -O nature_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O nature_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightgreen -fill darkgreen -draw "rectangle 200,200 600,400" -fill black -pointsize 24 -gravity center -annotate +0+100 "ENHANCE SATURATION" nature_image.jpg
    }
}

# Set proper permissions
chown ga:ga nature_image.jpg
chmod 644 nature_image.jpg

echo "✅ Nature image downloaded to /home/ga/Desktop/nature_image.jpg"

echo "🎨 Opening GIMP with the nature image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/nature_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Saturation enhancement task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The nature image is already open in GIMP"
echo "   2. Go to Colors → Hue-Saturation"
echo "   3. Make sure 'Master' channel is selected"
echo "   4. Move the Saturation slider to the right to increase vibrancy"
echo "   5. Target an increase of approximately +25 to +40 units"
echo "   6. Click OK to apply the enhancement"
echo "   7. The export will be automated after editing"