#!/bin/bash
set -e

echo "=== Setting up rectangle selection and fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a clean landscape image suitable for adding rectangles
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_base.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_base.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkgreen -draw "rectangle 300,300 700,500" -fill white -pointsize 24 -gravity center -annotate +0-200 "ADD RED RECTANGLE IN UPPER LEFT" landscape_base.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_base.jpg
chmod 644 landscape_base.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_base.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_base.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rectangle selection and fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Rectangle Select tool (R key or from toolbox)"
echo "   3. Click and drag in the upper-left area to create a rectangular selection"
echo "   4. Click on the foreground color square in the toolbox"
echo "   5. Set the color to bright red (RGB: 255, 0, 0)"
echo "   6. Use Edit → Fill with Foreground Color to fill the selection"
echo "   7. Use Select → None to clear the selection"
echo "   8. The export will be automated after editing"