#!/bin/bash
set -e

echo "=== Setting up grayscale mode conversion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a colorful image suitable for grayscale conversion
echo "📥 Downloading color flower image..."
cd /home/ga/Desktop/
wget -q -O color_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O color_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop&crop=center" || {
        echo "❌ All sources failed, using fallback..."
        # Create a colorful test image if download fails
        convert -size 800x600 -gradient "red:blue" -swirl 45 color_image.jpg
    }
}

# Set proper permissions
chown ga:ga color_image.jpg
chmod 644 color_image.jpg

echo "✅ Color image downloaded to /home/ga/Desktop/color_image.jpg"

echo "🎨 Opening GIMP with the color image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/color_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Grayscale mode conversion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The color image is already open in GIMP"
echo "   2. Go to Image → Mode → Grayscale"
echo "   3. If a dialog appears asking about flattening, confirm with OK"
echo "   4. The image should now be in true Grayscale mode (single channel)"
echo "   5. You can verify by checking Image → Mode again (Grayscale should be marked)"
echo "   6. The export will be automated after conversion"