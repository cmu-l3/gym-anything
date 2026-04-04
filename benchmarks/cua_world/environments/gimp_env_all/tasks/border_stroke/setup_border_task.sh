#!/bin/bash
set -e

echo "=== Setting up border stroke task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a photograph suitable for border addition
echo "📥 Downloading photograph for border task..."
cd /home/ga/Desktop/
wget -q -O photo_for_border.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_for_border.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:lightgray -fill blue -draw "rectangle 100,50 500,350" -fill black -pointsize 24 -gravity center -annotate +0+0 "ADD BORDER" photo_for_border.jpg
    }
}

# Set proper permissions
chown ga:ga photo_for_border.jpg
chmod 644 photo_for_border.jpg

echo "✅ Photo downloaded to /home/ga/Desktop/photo_for_border.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_for_border.jpg > /tmp/gimp_border.log 2>&1 &"

sleep 3

echo "=== Border stroke task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photograph is already open in GIMP"
echo "   2. Select all the image content (Select → All or Ctrl+A)"
echo "   3. Go to Edit → Stroke Selection"
echo "   4. Set stroke width to 15-20 pixels"
echo "   5. Ensure stroke color is black (or dark color)"
echo "   6. Click 'Stroke' to apply the border"
echo "   7. Optionally clear selection (Select → None)"
echo "   8. The export will be automated after editing"