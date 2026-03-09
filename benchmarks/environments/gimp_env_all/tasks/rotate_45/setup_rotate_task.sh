#!/bin/bash
set -e

echo "=== Setting up 45-degree rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Optional: Install opencv for advanced rotation detection
apt-get install -y -qq python3-opencv || echo "OpenCV not available, using fallback methods"

# Download image with clear geometric features that show rotation well
echo "📥 Downloading geometric landscape image..."
cd /home/ga/Desktop/
wget -q -O rotation_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O rotation_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear geometric features if download fails
        convert -size 800x600 xc:lightblue -fill red -draw "rectangle 100,100 300,200" -fill blue -draw "rectangle 500,300 700,500" -fill black -pointsize 32 -gravity center -annotate +0-200 "ROTATE 45°" rotation_image.jpg
    }
}

# Set proper permissions
chown ga:ga rotation_image.jpg
chmod 644 rotation_image.jpg

echo "✅ Rotation image downloaded to /home/ga/Desktop/rotation_image.jpg"

echo "🎨 Opening GIMP with the image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/rotation_image.jpg > /tmp/gimp_rotation.log 2>&1 &"

sleep 3

echo "=== 45-degree rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The image is already open in GIMP"
echo "   2. Go to Image → Transform → Arbitrary Rotation"
echo "   3. OR use Layer → Transform → Rotate"
echo "   4. In the rotation dialog, enter 45 in the angle field"
echo "   5. Make sure angle is in degrees (not radians)"
echo "   6. Click Rotate or OK to apply the transformation"
echo "   7. The export will be automated after rotation"