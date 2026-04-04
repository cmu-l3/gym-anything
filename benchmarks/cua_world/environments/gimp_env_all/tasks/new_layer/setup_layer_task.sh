#!/bin/bash
set -e

echo "=== Setting up new layer task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a landscape image to work with
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_base.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_base.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 gradient:blue-green -pointsize 24 -fill white -gravity center -annotate +0+0 "LANDSCAPE IMAGE" landscape_base.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_base.jpg
chmod 644 landscape_base.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_base.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_base.jpg > /tmp/gimp_layer.log 2>&1 &"

sleep 3

echo "=== New layer task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Layer → New Layer in the menu"
echo "   3. In the New Layer dialog:"
echo "      - Set layer name to 'Overlay Layer'"
echo "      - Set fill type to 'White'"
echo "      - Click OK to create the layer"
echo "   4. The new white layer should cover the landscape image"
echo "   5. The export will be automated after layer creation"