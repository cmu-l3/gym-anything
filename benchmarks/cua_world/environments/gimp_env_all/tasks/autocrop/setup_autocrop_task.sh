#!/bin/bash
set -e

echo "=== Setting up autocrop task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Download a content image and add borders to create autocrop target
echo "📥 Downloading content image..."
cd /home/ga/Desktop/
wget -q -O content_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O content_image.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80" || {
        echo "❌ All sources failed, creating fallback image..."
        # Create a simple test image with content if download fails
        convert -size 400x300 xc:lightblue -fill navy -pointsize 24 -gravity center -annotate +0+0 "AUTOCROP\nTEST IMAGE" content_image.jpg
    }
}

echo "🖼️ Adding uniform borders to create autocrop target..."
# Add white borders around the content image (50px on all sides)
convert content_image.jpg -bordercolor white -border 50x50 bordered_image.png

# Remove the original content image (keep only the bordered version)
rm -f content_image.jpg

# Set proper permissions
chown ga:ga bordered_image.png
chmod 644 bordered_image.png

echo "✅ Bordered image created at /home/ga/Desktop/bordered_image.png"

echo "🎨 Opening GIMP with the bordered image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/bordered_image.png > /tmp/gimp_autocrop.log 2>&1 &"

sleep 3

echo "=== Autocrop task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The bordered image is already open in GIMP"
echo "   2. Go to Image → Autocrop Image (or Image → Crop to Content)"
echo "   3. The uniform white borders should be automatically removed"
echo "   4. The export will be automated after editing"