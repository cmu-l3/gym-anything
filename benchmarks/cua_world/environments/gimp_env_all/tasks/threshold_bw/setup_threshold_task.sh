#!/bin/bash
set -e

echo "=== Setting up threshold black and white task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with good contrast for threshold operation
echo "📥 Downloading color photograph..."
cd /home/ga/Desktop/
wget -q -O color_photo.jpg "https://images.unsplash.com/photo-1549298916-b41d501d3772?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O color_photo.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear contrast if download fails
        convert -size 800x600 xc:lightgray -fill black -draw "circle 300,250 450,250" -fill white -draw "circle 500,350 600,350" color_photo.jpg
    }
}

# Set proper permissions
chown ga:ga color_photo.jpg
chmod 644 color_photo.jpg

echo "✅ Color photograph downloaded to /home/ga/Desktop/color_photo.jpg"

echo "🎨 Opening GIMP with the color photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/color_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Threshold task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The color photograph is already open in GIMP"
echo "   2. Go to Colors → Threshold"
echo "   3. In the Threshold dialog:"
echo "      - Observe the histogram showing brightness distribution"
echo "      - Adjust the threshold slider(s) to find good black/white separation"
echo "      - Preview shows real-time results"
echo "      - Aim to preserve important subject details while creating clear binary result"
echo "   4. Click OK to apply the threshold"
echo "   5. The export will be automated after editing"