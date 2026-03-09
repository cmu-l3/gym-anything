#!/bin/bash
set -e

echo "=== Setting up rectangle stroke task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv-python || {
    echo "⚠️ OpenCV installation failed, will use fallback methods"
    apt-get install -y -qq python3-pil python3-numpy
}

# Download a landscape image with good background for rectangle stroke
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_stroke.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_stroke.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 gradient:blue-green -pointsize 24 -gravity center -annotate +0+200 "Draw Rectangle Here" landscape_stroke.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_stroke.jpg
chmod 644 landscape_stroke.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_stroke.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_stroke.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rectangle stroke task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Rectangle Select Tool (R key or from toolbox)"
echo "   3. Draw a rectangular selection in the center of the image"
echo "   4. Set a bright foreground color (click color square in toolbox)"
echo "   5. Go to Edit → Stroke Selection"
echo "   6. Set stroke width to 8-10 pixels"
echo "   7. Click 'Stroke' to apply the rectangular outline"
echo "   8. Optionally clear selection with Select → None"
echo "   9. The export will be automated after editing"