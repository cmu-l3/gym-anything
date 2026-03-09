#!/bin/bash
set -e

echo "=== Setting up sharpen filter task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image that would benefit from sharpening (slightly soft photograph)
echo "📥 Downloading photograph for sharpening..."
cd /home/ga/Desktop/
wget -q -O photo_to_sharpen.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_to_sharpen.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with some detail if download fails
        convert -size 800x600 xc:lightgray \
                -fill darkgray -draw "rectangle 200,200 600,400" \
                -fill black -pointsize 36 -gravity center \
                -annotate +0+0 "SHARPEN THIS IMAGE" \
                photo_to_sharpen.jpg
    }
}

# Set proper permissions
chown ga:ga photo_to_sharpen.jpg
chmod 644 photo_to_sharpen.jpg

echo "✅ Photograph downloaded to /home/ga/Desktop/photo_to_sharpen.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_to_sharpen.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Sharpen filter task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photograph is already open in GIMP"
echo "   2. Go to Filters → Enhance → Sharpen (Unsharp Mask)"
echo "   3. In the Unsharp Mask dialog:"
echo "      - Ensure Preview is checked"
echo "      - Adjust Amount to 1.0-2.0 for sharpening strength"
echo "      - Set Radius to 1.0-3.0 pixels"
echo "      - Keep Threshold low (0-5)"
echo "   4. Click OK to apply the sharpening filter"
echo "   5. The export will be automated after editing"