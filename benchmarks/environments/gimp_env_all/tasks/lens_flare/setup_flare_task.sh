#!/bin/bash
set -e

echo "=== Setting up lens flare task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download outdoor/landscape image suitable for lens flare effect
echo "📥 Downloading outdoor landscape image..."
cd /home/ga/Desktop/
wget -q -O outdoor_scene.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O outdoor_scene.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with sky area if download fails
        convert -size 800x600 xc:lightblue -fill yellow -draw "circle 600,150 650,200" -fill white -pointsize 24 -gravity center -annotate +0+200 "ADD LENS FLARE" outdoor_scene.jpg
    }
}

# Set proper permissions
chown ga:ga outdoor_scene.jpg
chmod 644 outdoor_scene.jpg

echo "✅ Outdoor scene image downloaded to /home/ga/Desktop/outdoor_scene.jpg"

echo "🎨 Opening GIMP with the outdoor scene image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/outdoor_scene.jpg > /tmp/gimp_flare.log 2>&1 &"

sleep 3

echo "=== Lens flare task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The outdoor scene image is already open in GIMP"
echo "   2. Go to Filters → Light and Shadow → Lens Flare"
echo "   3. In the Lens Flare dialog, click in the preview to position the flare"
echo "   4. Place the flare in the upper portion (sky area) of the image"
echo "   5. Click OK to apply the lens flare effect"
echo "   6. The export will be automated after editing"