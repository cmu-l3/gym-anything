#!/bin/bash
set -e

echo "=== Setting up hue shift task ==="

# Install required packages for HSV color space analysis verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download colorful image suitable for hue shift demonstration
echo "📥 Downloading colorful image..."
cd /home/ga/Desktop/
wget -q -O colorful_image.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O colorful_image.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple colorful test image if download fails
        convert -size 800x600 xc:white \
            -fill red -draw "circle 200,150 200,250" \
            -fill green -draw "circle 400,150 400,250" \
            -fill blue -draw "circle 600,150 600,250" \
            -fill yellow -draw "circle 300,350 300,450" \
            -fill cyan -draw "circle 500,350 500,450" \
            -fill magenta -draw "circle 400,450 400,550" \
            colorful_image.jpg
    }
}

# Set proper permissions
chown ga:ga colorful_image.jpg
chmod 644 colorful_image.jpg

echo "✅ Colorful image downloaded to /home/ga/Desktop/colorful_image.jpg"

echo "🎨 Opening GIMP with the colorful image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/colorful_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Hue shift task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful image is already open in GIMP"
echo "   2. Go to Colors → Hue-Saturation"
echo "   3. Ensure 'Master' channel is selected (not a specific color)"
echo "   4. Move the Hue slider to shift colors (try +60 degrees)"
echo "   5. Watch the preview to see all colors rotating on the color wheel"
echo "   6. Click OK to apply the hue shift"
echo "   7. The export will be automated after editing"