#!/bin/bash
set -e

echo "=== Setting up 90-degree rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a landscape image with clear directional features
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1469474968028-56623f02e42e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple directional test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -pointsize 48 -gravity northwest -annotate +50+50 "TOP LEFT" -gravity southeast -annotate +50+50 "BOTTOM RIGHT" -fill red -draw "circle 200,150 250,200" landscape_image.jpg
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

echo "=== 90-degree rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Image → Transform → Rotate 90° clockwise"
echo "   3. The rotation will apply immediately"
echo "   4. Verify the image has been rotated clockwise (left side now at bottom)"
echo "   5. Check that dimensions are swapped (width becomes height)"
echo "   6. The export will be automated after rotation"