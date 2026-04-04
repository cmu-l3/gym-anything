#!/bin/bash
set -e

echo "=== Setting up solarize effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with good brightness distribution for solarization
echo "📥 Downloading landscape image with varied brightness..."
cd /home/ga/Desktop/
wget -q -O landscape_bright.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_bright.jpg "https://images.unsplash.com/photo-1469474968028-56623f02e42e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with varied brightness if download fails
        convert -size 800x600 gradient:black-white -fill black -pointsize 32 -gravity center -annotate +0+0 "SOLARIZE ME" landscape_bright.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_bright.jpg
chmod 644 landscape_bright.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_bright.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_bright.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Solarize effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Colors → Solarize (or Colors → Filter → Solarize)"
echo "   3. The effect should apply immediately or with default settings"
echo "   4. The export will be automated after applying the effect"