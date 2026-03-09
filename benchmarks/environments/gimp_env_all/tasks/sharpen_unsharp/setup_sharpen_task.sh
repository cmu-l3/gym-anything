#!/bin/bash
set -e

echo "=== Setting up sharpen (unsharp mask) task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv

# Download a detailed portrait image that will benefit from sharpening
echo "📥 Downloading portrait image for sharpening..."
cd /home/ga/Desktop/
wget -q -O portrait_sharpen.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_sharpen.jpg "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with edges if download fails
        convert -size 800x600 xc:lightgray -fill black -pointsize 36 -gravity center -annotate +0+0 "SHARPEN\nTHIS IMAGE" -blur 0x1 portrait_sharpen.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_sharpen.jpg
chmod 644 portrait_sharpen.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_sharpen.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_sharpen.jpg > /tmp/gimp_sharpen.log 2>&1 &"

sleep 3

echo "=== Sharpen task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Filters → Enhance → Unsharp Mask"
echo "   3. In the Unsharp Mask dialog:"
echo "      - Set Radius to 1.0-2.0 pixels"
echo "      - Set Amount to 0.8-1.5"
echo "      - Keep Threshold at 0-5"
echo "      - Use Preview to see the effect"
echo "   4. Click OK to apply the sharpening"
echo "   5. The export will be automated after editing"