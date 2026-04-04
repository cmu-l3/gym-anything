#!/bin/bash
set -e

echo "=== Setting up increase saturation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download colorful nature image that will benefit from saturation increase
echo "📥 Downloading colorful nature image..."
cd /home/ga/Desktop/
wget -q -O nature_colors.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O nature_colors.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with various colors if download fails
        convert -size 800x600 xc:lightblue -fill red -draw "circle 200,150 250,200" -fill green -draw "circle 600,150 650,200" -fill yellow -draw "circle 400,450 450,500" -fill black -pointsize 24 -gravity center -annotate +0-200 "INCREASE SATURATION" nature_colors.jpg
    }
}

# Set proper permissions
chown ga:ga nature_colors.jpg
chmod 644 nature_colors.jpg

echo "✅ Nature image downloaded to /home/ga/Desktop/nature_colors.jpg"

echo "🎨 Opening GIMP with the nature image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/nature_colors.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Increase saturation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful nature image is already open in GIMP"
echo "   2. Go to Colors → Hue-Saturation"
echo "   3. In the Hue-Saturation dialog:"
echo "      - Make sure 'Master' channel is selected (affects all colors)"
echo "      - Increase the Saturation slider to the right (+20 to +40 recommended)"
echo "      - Watch the preview to see colors become more vibrant"
echo "   4. Click OK to apply the saturation increase"
echo "   5. The export will be automated after editing"