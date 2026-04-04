#!/bin/bash
set -e

echo "=== Setting up sharpen details task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image that would benefit from sharpening (slightly soft portrait/landscape)
echo "📥 Downloading slightly soft image for sharpening..."
cd /home/ga/Desktop/
wget -q -O soft_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=70" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O soft_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop&crop=center&q=70" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with some blur if download fails
        convert -size 800x600 xc:lightblue -fill black -pointsize 36 -gravity center -annotate +0+0 "SHARPEN ME" -blur 0x1 soft_image.jpg
    }
}

# Set proper permissions
chown ga:ga soft_image.jpg
chmod 644 soft_image.jpg

echo "✅ Soft image downloaded to /home/ga/Desktop/soft_image.jpg"

echo "🎨 Opening GIMP with the soft image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/soft_image.jpg > /tmp/gimp_sharpen.log 2>&1 &"

sleep 3

echo "=== Sharpen details task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The soft image is already open in GIMP"
echo "   2. Go to Filters → Enhance → Unsharp Mask"
echo "   3. In the Unsharp Mask dialog:"
echo "      - Set Radius to 1.0-3.0 pixels"
echo "      - Set Amount to 0.5-1.5"
echo "      - Set Threshold to 0-5"
echo "   4. Enable Preview to see changes"
echo "   5. Adjust parameters for natural-looking enhancement"
echo "   6. Click OK to apply the sharpening"
echo "   7. The export will be automated after editing"