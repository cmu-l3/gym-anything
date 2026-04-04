#!/bin/bash
set -e

echo "=== Setting up 90-degree clockwise rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with distinctive features for rotation verification
echo "📥 Downloading flower image..."
cd /home/ga/Desktop/
wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1518709268805-4e9042af2176?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with directional elements if download fails
        convert -size 600x400 xc:lightblue -fill red -draw "rectangle 50,50 200,150" -fill black -pointsize 24 -gravity northwest -annotate +60+200 "TOP" -gravity southeast -annotate +60+200 "BOTTOM" flower_image.jpg
    }
}

# Set proper permissions
chown ga:ga flower_image.jpg
chmod 644 flower_image.jpg

echo "✅ Flower image downloaded to /home/ga/Desktop/flower_image.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_image.jpg > /tmp/gimp_rotation.log 2>&1 &"

sleep 3

echo "=== 90-degree clockwise rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower image is already open in GIMP"
echo "   2. Go to Image → Transform → Rotate 90° clockwise"
echo "   3. The rotation should apply immediately"
echo "   4. Verify the image is rotated 90 degrees clockwise"
echo "   5. The export will be automated after rotation"