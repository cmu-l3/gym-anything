#!/bin/bash
set -e

echo "=== Setting up drop shadow task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear object for drop shadow effect
echo "📥 Downloading object image..."
cd /home/ga/Desktop/
wget -q -O object_image.png "https://images.unsplash.com/photo-1542291026-7eec264c27ff?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O object_image.png "https://images.unsplash.com/photo-1549298916-b41d501d3772?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating fallback..."
        # Create a simple test object if download fails
        convert -size 400x400 xc:white -fill red -draw "circle 200,200 200,100" -fill black -pointsize 24 -gravity center -annotate +0+80 "ADD SHADOW" object_image.png
    }
}

# Set proper permissions
chown ga:ga object_image.png
chmod 644 object_image.png

echo "✅ Object image downloaded to /home/ga/Desktop/object_image.png"

echo "🎨 Opening GIMP with the object image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/object_image.png > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Drop shadow task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The object image is already open in GIMP"
echo "   2. Go to Filters → Light and Shadow → Drop Shadow"
echo "   3. In the Drop Shadow dialog:"
echo "      - Set X and Y offset (try 5-10 pixels each)"
echo "      - Set blur radius (try 10-20 pixels)"
echo "      - Set opacity (try 60-80%)"
echo "      - Ensure shadow color is black or dark gray"
echo "   4. Click OK to apply the drop shadow"
echo "   5. The export will be automated after editing"