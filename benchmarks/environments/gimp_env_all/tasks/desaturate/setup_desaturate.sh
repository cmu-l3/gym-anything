#!/bin/bash
set -e

echo "=== Setting up desaturate task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a colorful landscape image for desaturation
echo "📥 Downloading colorful landscape image..."
cd /home/ga/Desktop/
wget -q -O color_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O color_landscape.jpg "https://images.unsplash.com/photo-1439066615861-d1af74d74000?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple colorful test image if download fails
        convert -size 800x600 gradient:red-blue -swirl 30 -fill yellow -draw "circle 400,300 400,200" color_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga color_landscape.jpg
chmod 644 color_landscape.jpg

echo "✅ Colorful landscape image downloaded to /home/ga/Desktop/color_landscape.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/color_landscape.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Desaturate task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful landscape image is already open in GIMP"
echo "   2. Navigate to Colors → Desaturate → Desaturate"
echo "   3. Choose an appropriate desaturation method:"
echo "      - Lightness: Average of max and min RGB"
echo "      - Luminosity: Weighted RGB based on eye sensitivity"
echo "      - Average: Simple arithmetic mean of RGB"
echo "   4. Click OK to apply the desaturation"
echo "   5. The export will be automated after editing"