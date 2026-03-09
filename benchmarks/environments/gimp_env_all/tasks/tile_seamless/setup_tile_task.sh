#!/bin/bash
set -e

echo "=== Setting up tile seamless task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download texture image that would benefit from seamless tiling
echo "📥 Downloading texture image..."
cd /home/ga/Desktop/
wget -q -O texture_image.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O texture_image.jpg "https://images.unsplash.com/photo-1574755393849-623942496936?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple pattern if download fails
        convert -size 400x400 pattern:checkerboard -scale 50x50 +repage texture_image.jpg
    }
}

# Set proper permissions
chown ga:ga texture_image.jpg
chmod 644 texture_image.jpg

echo "✅ Texture image downloaded to /home/ga/Desktop/texture_image.jpg"

echo "🎨 Opening GIMP with the texture image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/texture_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Tile seamless task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The texture image is already open in GIMP"
echo "   2. Go to Filters → Distorts → Tile Seamless"
echo "   3. Accept default settings if a dialog appears"
echo "   4. The filter will process the image to make edges seamless"
echo "   5. The export will be automated after filtering"