#!/bin/bash
set -e

echo "=== Setting up rectangle selection and delete task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a landscape image suitable for rectangular deletion
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_rect.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_rect.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkgreen -draw "rectangle 0,0 400,300" -fill yellow -draw "rectangle 400,0 800,300" -fill red -draw "rectangle 0,300 400,600" -fill purple -draw "rectangle 400,300 800,600" landscape_rect.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_rect.jpg
chmod 644 landscape_rect.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_rect.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_rect.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rectangle selection and delete task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Rectangle Selection tool (R key or from toolbox)"
echo "   3. Click and drag to create a rectangular selection in the upper-right area"
echo "   4. Aim for approximately 150x100 pixel region in the corner"
echo "   5. Press Delete key to remove the selected content"
echo "   6. Go to Select → None (or Ctrl+Shift+A) to clear the selection"
echo "   7. The export will be automated after editing"