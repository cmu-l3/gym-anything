#!/bin/bash
set -e

echo "=== Setting up brightness adjustment task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download underexposed portrait image
echo "📥 Downloading underexposed portrait image..."
cd /home/ga/Desktop/
wget -q -O dark_portrait.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=50&brightness=-50" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O dark_portrait.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=40" || {
        echo "❌ All sources failed, creating test image..."
        # Create a dark test image if download fails
        convert -size 800x600 xc:"rgb(30,30,30)" -fill "rgb(80,70,60)" -draw "circle 400,300 400,200" -fill white -pointsize 24 -gravity center -annotate +0+150 "BRIGHTEN ME" dark_portrait.jpg
    }
}

# Set proper permissions
chown ga:ga dark_portrait.jpg
chmod 644 dark_portrait.jpg

echo "✅ Dark portrait image downloaded to /home/ga/Desktop/dark_portrait.jpg"

echo "🎨 Opening GIMP with the dark portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/dark_portrait.jpg > /tmp/gimp_brightness.log 2>&1 &"

sleep 3

echo "=== Brightness adjustment task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The dark portrait image is already open in GIMP"
echo "   2. Go to Colors → Brightness-Contrast"
echo "   3. Increase the Brightness slider to the right (positive values)"
echo "   4. Aim for +20 to +40 points to make the image more visible"
echo "   5. Use the preview to judge when details become clearly visible"
echo "   6. Click OK to apply the brightness adjustment"
echo "   7. The export will be automated after editing"