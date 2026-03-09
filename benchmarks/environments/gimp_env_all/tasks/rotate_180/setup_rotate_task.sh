#!/bin/bash
set -e

echo "=== Setting up rotate 180° task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear directional features for rotation detection
echo "📥 Downloading directional photo..."
cd /home/ga/Desktop/
wget -q -O photo_original.jpg "https://images.unsplash.com/photo-1441986300917-64674bd600d8?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_original.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with clear directional elements if download fails
        convert -size 800x600 xc:lightblue -fill black -pointsize 48 -gravity north -annotate +0+50 "TOP" -gravity south -annotate +0+50 "BOTTOM" -fill red -draw "polygon 400,100 500,200 300,200" photo_original.jpg
    }
}

# Set proper permissions
chown ga:ga photo_original.jpg
chmod 644 photo_original.jpg

echo "✅ Photo downloaded to /home/ga/Desktop/photo_original.jpg"

echo "🎨 Opening GIMP with the photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_original.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rotate 180° task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo is already open in GIMP"
echo "   2. Go to Image → Transform → Rotate 180°"
echo "   3. The rotation will apply immediately"
echo "   4. Verify the image is now upside-down"
echo "   5. The export will be automated after editing"