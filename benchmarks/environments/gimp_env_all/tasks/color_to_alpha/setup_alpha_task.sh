#!/bin/bash
set -e

echo "=== Setting up color to alpha task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with white background suitable for background removal
echo "📥 Downloading logo image with white background..."
cd /home/ga/Desktop/
wget -q -O logo_white_bg.png "https://images.unsplash.com/photo-1611162617474-5b21e879e113?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=500&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O logo_white_bg.png "https://images.unsplash.com/photo-1593642532842-98d0fd5ebc1a?ixlib=rb-4.0.3&auto=format&fit=crop&w=500&q=80" || {
        echo "❌ All sources failed, creating fallback test image..."
        # Create a simple test image with white background if download fails
        convert -size 400x300 xc:white -fill black -draw "circle 200,150 100,100" -fill blue -pointsize 24 -gravity center -annotate +0+50 "REMOVE WHITE BG" logo_white_bg.png
    }
}

# Set proper permissions
chown ga:ga logo_white_bg.png
chmod 644 logo_white_bg.png

echo "✅ Logo image downloaded to /home/ga/Desktop/logo_white_bg.png"

echo "🎨 Opening GIMP with the logo image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/logo_white_bg.png > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color to alpha task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The logo image with white background is already open in GIMP"
echo "   2. Go to Colors → Color to Alpha in the menu"
echo "   3. The dialog should default to white color (#FFFFFF)"
echo "   4. Preview the effect - white areas should become transparent"
echo "   5. Click OK to apply the transparency conversion"
echo "   6. You should see checkerboard pattern where white was removed"
echo "   7. The export will be automated as PNG to preserve transparency"