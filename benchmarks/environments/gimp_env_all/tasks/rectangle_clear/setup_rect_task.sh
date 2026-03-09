#!/bin/bash
set -e

echo "=== Setting up rectangle clear task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image for rectangle selection and clearing
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with distinct quadrants if download fails
        convert -size 800x600 xc:lightblue -fill red -draw "rectangle 0,0 400,300" -fill green -draw "rectangle 400,0 800,300" -fill yellow -draw "rectangle 0,300 400,600" -fill purple -draw "rectangle 400,300 800,600" landscape_image.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_image.jpg
chmod 644 landscape_image.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rectangle clear task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Rectangle Select tool (R key or from toolbox)"
echo "   3. Click and drag to select the top-left quarter of the image"
echo "   4. Press Delete key or go to Edit → Clear to clear the selection"
echo "   5. Go to Select → None to deselect (optional)"
echo "   6. The export will be automated after editing"