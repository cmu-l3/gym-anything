#!/bin/bash
set -e

echo "=== Setting up 90-degree clockwise rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a portrait-oriented flower image for rotation
echo "📥 Downloading portrait flower image..."
cd /home/ga/Desktop/
wget -q -O flower_portrait.jpg "https://images.unsplash.com/photo-1518709268805-4e9042af2176?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&h=1031&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_portrait.jpg "https://images.unsplash.com/photo-1490750967868-88aa4486c946?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&h=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear orientation if download fails
        convert -size 400x600 xc:lightblue -fill red -draw "circle 200,150 200,100" -fill green -draw "rectangle 180,400 220,550" -fill black -pointsize 24 -gravity center -annotate +0+250 "ROTATE ME" flower_portrait.jpg
    }
}

# Set proper permissions
chown ga:ga flower_portrait.jpg
chmod 644 flower_portrait.jpg

echo "✅ Portrait flower image downloaded to /home/ga/Desktop/flower_portrait.jpg"

echo "🎨 Opening GIMP with the portrait flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_portrait.jpg > /tmp/gimp_rotate.log 2>&1 &"

sleep 3

echo "=== 90-degree clockwise rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait flower image is already open in GIMP"
echo "   2. Go to Image → Transform → Rotate 90° clockwise"
echo "   3. The image should change from portrait to landscape orientation"
echo "   4. Verify the rotation appears correct (top became right side)"
echo "   5. The export will be automated after editing"