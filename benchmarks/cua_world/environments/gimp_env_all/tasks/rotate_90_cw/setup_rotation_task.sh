#!/bin/bash
set -e

echo "=== Setting up 90° clockwise rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download landscape image with clear asymmetric features
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear asymmetric elements if download fails
        convert -size 800x600 xc:lightblue \
               -fill darkgreen -draw "rectangle 50,100 300,500" \
               -fill red -draw "circle 600,150 680,200" \
               -fill black -pointsize 36 -gravity northwest -annotate +100+50 "ROTATE 90° CW" \
               landscape_image.jpg
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

echo "=== 90° clockwise rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Navigate to Image → Transform → Rotate 90° clockwise"
echo "   3. The rotation will apply immediately"
echo "   4. Verify the image rotated from landscape to portrait orientation"
echo "   5. The export will be automated after editing"