#!/bin/bash
set -e

echo "=== Setting up desaturation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a colorful butterfly image for desaturation
echo "📥 Downloading butterfly image..."
cd /home/ga/Desktop/
wget -q -O butterfly_image.jpg "https://images.unsplash.com/photo-1558818498-28c1e002b655?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O butterfly_image.jpg "https://images.unsplash.com/photo-1444927714506-8492d94b5ba0?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a colorful test image if download fails
        convert -size 600x400 xc:blue -fill red -draw "circle 150,100 250,200" -fill green -draw "circle 450,100 550,200" -fill yellow -draw "circle 300,300 400,350" -fill black -pointsize 24 -gravity center -annotate +0-150 "COLORFUL TEST IMAGE" butterfly_image.jpg
    }
}

# Set proper permissions
chown ga:ga butterfly_image.jpg
chmod 644 butterfly_image.jpg

echo "✅ Butterfly image downloaded to /home/ga/Desktop/butterfly_image.jpg"

echo "🎨 Opening GIMP with the butterfly image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/butterfly_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Desaturation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The butterfly image is already open in GIMP"
echo "   2. Go to Colors → Desaturate in the menu"
echo "   3. Choose an appropriate desaturation method (Luminance recommended)"
echo "   4. Click OK to apply the desaturation"
echo "   5. The export will be automated after editing"