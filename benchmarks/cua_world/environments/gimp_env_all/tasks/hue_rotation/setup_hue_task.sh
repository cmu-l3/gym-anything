#!/bin/bash
set -e

echo "=== Setting up hue rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with vibrant colors for hue rotation
echo "📥 Downloading colorful image..."
cd /home/ga/Desktop/
wget -q -O colorful_image.jpg "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O colorful_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with multiple colors if download fails
        convert -size 800x600 xc:white \
            -fill red -draw "rectangle 100,100 250,250" \
            -fill green -draw "rectangle 300,150 450,300" \
            -fill blue -draw "rectangle 500,200 650,350" \
            -fill yellow -draw "rectangle 200,350 350,500" \
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

echo "=== Hue rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful image is already open in GIMP"
echo "   2. Go to Colors → Hue-Saturation"
echo "   3. Ensure 'Master' channel is selected (not individual colors)"
echo "   4. Move the Hue slider to rotate hues by +60 degrees"
echo "   5. Watch the preview to see colors transform"
echo "   6. Click OK to apply the hue rotation"
echo "   7. The export will be automated after editing"