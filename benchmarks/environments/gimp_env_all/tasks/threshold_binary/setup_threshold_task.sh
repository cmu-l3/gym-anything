#!/bin/bash
set -e

echo "=== Setting up threshold binary task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with good tonal range for threshold conversion
echo "📥 Downloading grayscale-rich image..."
cd /home/ga/Desktop/
wget -q -O grayscale_image.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O grayscale_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with varied gray levels if download fails
        convert -size 800x600 xc:white \
            -fill gray60 -draw "rectangle 100,100 300,300" \
            -fill gray30 -draw "rectangle 400,200 600,400" \
            -fill gray80 -draw "circle 200,450 250,500" \
            -fill black -pointsize 32 -gravity center -annotate +0+200 "THRESHOLD TEST" \
            grayscale_image.jpg
    }
}

# Set proper permissions
chown ga:ga grayscale_image.jpg
chmod 644 grayscale_image.jpg

echo "✅ Grayscale image downloaded to /home/ga/Desktop/grayscale_image.jpg"

echo "🎨 Opening GIMP with the grayscale image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/grayscale_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Threshold binary task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The grayscale image is already open in GIMP"
echo "   2. Go to Colors → Threshold"
echo "   3. Adjust the threshold slider if needed (or use default)"
echo "   4. Click OK to apply the threshold effect"
echo "   5. The image should now be pure black and white"
echo "   6. The export will be automated after editing"