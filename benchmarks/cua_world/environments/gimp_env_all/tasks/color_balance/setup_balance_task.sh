#!/bin/bash
set -e

echo "=== Setting up color balance task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with warm/yellow color cast
echo "📥 Downloading warm-cast landscape image..."
cd /home/ga/Desktop/
wget -q -O warm_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80&sat=2&hue=20" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O warm_landscape.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with warm color cast if download fails
        convert -size 800x600 xc:white \( -size 800x600 gradient:yellow-orange \) -compose multiply -composite \
                -fill black -pointsize 24 -gravity center -annotate +0+200 "COLOR BALANCE NEEDED" warm_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga warm_landscape.jpg
chmod 644 warm_landscape.jpg

echo "✅ Warm landscape image downloaded to /home/ga/Desktop/warm_landscape.jpg"

echo "🎨 Opening GIMP with the warm landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/warm_landscape.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color balance task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The warm landscape image is already open in GIMP"
echo "   2. Notice the warm/yellow color cast in the image"
echo "   3. Go to Colors → Color Balance"
echo "   4. In the Color Balance dialog:"
echo "      - Ensure 'Midtones' is selected"
echo "      - Move Cyan-Red slider toward Cyan (left) to reduce warmth"
echo "      - Move Yellow-Blue slider toward Blue (right) to reduce yellow cast"
echo "      - Make moderate adjustments (around -20 to +20)"
echo "   5. Click OK to apply the color balance correction"
echo "   6. The export will be automated after editing"