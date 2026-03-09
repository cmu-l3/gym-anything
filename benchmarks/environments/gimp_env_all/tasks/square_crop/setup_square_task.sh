#!/bin/bash
set -e

echo "=== Setting up square crop task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download rectangular landscape image for square cropping
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a rectangular test image if download fails
        convert -size 1000x600 xc:lightblue -fill darkblue -draw "rectangle 200,150 800,450" -fill white -pointsize 48 -gravity center -annotate +0+0 "CROP TO SQUARE" landscape_image.jpg
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

echo "=== Square crop task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The rectangular landscape image is already open in GIMP"
echo "   2. Select the Crop Tool from toolbox (or press Shift+C)"
echo "   3. In Tool Options, enable 'Fixed Aspect Ratio' or 'Fixed' constraint"
echo "   4. Set the aspect ratio to 1:1 (width:height = 1:1)"
echo "   5. Click and drag to create a square selection around the best area"
echo "   6. Adjust the selection position and size as needed"
echo "   7. Press Enter or click inside the selection to apply the crop"
echo "   8. The export will be automated after editing"