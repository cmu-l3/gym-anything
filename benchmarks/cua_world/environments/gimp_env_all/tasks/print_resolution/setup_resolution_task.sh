#!/bin/bash
set -e

echo "=== Setting up print resolution task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a landscape image with default 72 DPI
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1200&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill black -pointsize 24 -gravity center -annotate +0+0 "LANDSCAPE IMAGE" landscape_image.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_image.jpg
chmod 644 landscape_image.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Print resolution task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Image → Print Size (NOT Scale Image!)"
echo "   3. In the Print Size dialog:"
echo "      - Observe current DPI (likely 72.000)"
echo "      - Change X resolution to 300"
echo "      - Y resolution should change automatically if chain-linked"
echo "      - Notice physical dimensions decrease (same pixels ÷ higher DPI)"
echo "      - Pixel dimensions should remain unchanged"
echo "   4. Click OK to apply the DPI change"
echo "   5. The export will be automated after editing"
echo ""
echo "⚠️  IMPORTANT: Use Print Size, not Scale Image!"
echo "   Print Size changes DPI metadata only"
echo "   Scale Image would resize the actual pixels"