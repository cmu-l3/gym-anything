#!/bin/bash
set -e

echo "=== Setting up sharpen filter task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a slightly blurry image that would benefit from sharpening
echo "📥 Downloading slightly blurry image..."
cd /home/ga/Desktop/
wget -q -O blurry_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O blurry_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, creating test image..."
        # Create a simple test image with some blur if download fails
        convert -size 800x600 xc:white -fill black -pointsize 24 -gravity center -annotate +0+0 "SHARPEN THIS TEXT" -blur 0x1 blurry_image.jpg
    }
}

# Set proper permissions
chown ga:ga blurry_image.jpg
chmod 644 blurry_image.jpg

echo "✅ Blurry image downloaded to /home/ga/Desktop/blurry_image.jpg"

echo "🎨 Opening GIMP with the blurry image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blurry_image.jpg > /tmp/gimp_sharpen.log 2>&1 &"

sleep 3

echo "=== Sharpen filter task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blurry image is already open in GIMP"
echo "   2. Go to Filters → Enhance → Sharpen (Unsharp Mask)"
echo "   3. Adjust parameters if needed (default settings usually work well)"
echo "   4. Click OK to apply the sharpening filter"
echo "   5. The export will be automated after editing"