#!/bin/bash
set -e

echo "=== Setting up 90° counter-clockwise rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with distinctive features to verify rotation direction
echo "📥 Downloading test image..."
cd /home/ga/Desktop/
wget -q -O rotate_test_image.jpg "https://images.unsplash.com/photo-1551963831-b3b1ca40c98e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O rotate_test_image.jpg "https://images.unsplash.com/photo-1486312338219-ce68e2c6b87d?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with directional elements if download fails
        convert -size 600x400 xc:lightblue -fill red -draw "rectangle 50,50 150,150" -fill yellow -draw "rectangle 450,50 550,150" -fill black -pointsize 24 -gravity center -annotate +0-100 "TOP" -annotate +0+100 "BOTTOM" rotate_test_image.jpg
    }
}

# Set proper permissions
chown ga:ga rotate_test_image.jpg
chmod 644 rotate_test_image.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/rotate_test_image.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/rotate_test_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== 90° counter-clockwise rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Go to Image → Transform → Rotate 90° counter-clockwise"
echo "   3. **IMPORTANT**: Select counter-clockwise, NOT clockwise"
echo "   4. The rotation should make what was on the RIGHT become the TOP"
echo "   5. The export will be automated after rotation"
echo "   6. Expected result: Portrait becomes landscape (or vice versa)"