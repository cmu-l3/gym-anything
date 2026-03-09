#!/bin/bash
set -e

echo "=== Setting up levels adjustment task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download underexposed (dark) landscape image
echo "📥 Downloading underexposed landscape image..."
cd /home/ga/Desktop/
wget -q -O underexposed_landscape.jpg "https://images.unsplash.com/photo-1506197603052-3cc9c3a201bd?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=30" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O underexposed_landscape.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=30" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple dark test image if download fails
        convert -size 800x600 xc:"rgb(40,50,60)" -fill "rgb(80,90,100)" -draw "rectangle 100,100 700,500" -fill "rgb(60,70,80)" -pointsize 32 -gravity center -annotate +0+0 "UNDEREXPOSED IMAGE" underexposed_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga underexposed_landscape.jpg
chmod 644 underexposed_landscape.jpg

echo "✅ Underexposed landscape image downloaded to /home/ga/Desktop/underexposed_landscape.jpg"

echo "🎨 Opening GIMP with the underexposed image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/underexposed_landscape.jpg > /tmp/gimp_levels.log 2>&1 &"

sleep 3

echo "=== Levels adjustment task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The underexposed landscape image is already open in GIMP"
echo "   2. Go to Colors → Levels"
echo "   3. In the Levels dialog:"
echo "      - Move the right slider (white point) to the left to brighten the image"
echo "      - Optionally adjust the middle slider (gamma) for midtone brightness"
echo "      - Optionally adjust the left slider (black point) for contrast"
echo "   4. Click OK to apply the levels adjustment"
echo "   5. The export will be automated after editing"