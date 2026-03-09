#!/bin/bash
set -e

echo "=== Setting up autocrop to content task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Download or create an image with borders for autocroping
echo "📥 Downloading base image..."
cd /home/ga/Desktop/
wget -q -O base_image.jpg "https://images.unsplash.com/photo-1551963831-b3b1ca40c98e?ixlib=rb-4.0.3&w=400&h=300&fit=crop&crop=center&auto=format" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O base_image.jpg "https://images.unsplash.com/photo-1574169208507-84376144848b?ixlib=rb-4.0.3&w=400&h=300&fit=crop&crop=center&auto=format" || {
        echo "❌ All sources failed, creating synthetic image..."
        # Create a simple test image with content if download fails
        convert -size 400x300 gradient:blue-white -fill black -pointsize 36 -gravity center -annotate +0+0 "SAMPLE\nCONTENT" base_image.jpg
    }
}

# Add significant white borders to the image using ImageMagick
echo "🖼️ Adding borders to create autocrop challenge..."
convert base_image.jpg -background white -gravity center -extent 800x600 bordered_image.jpg

# Remove the original base image
rm base_image.jpg

# Set proper permissions
chown ga:ga bordered_image.jpg
chmod 644 bordered_image.jpg

echo "✅ Bordered image created at /home/ga/Desktop/bordered_image.jpg"

echo "🎨 Opening GIMP with the bordered image..."
# Launch GIMP with the bordered image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/bordered_image.jpg > /tmp/gimp_autocrop.log 2>&1 &"

sleep 3

echo "=== Autocrop task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The bordered image is already open in GIMP"
echo "   2. Go to Image → Crop to Content (or Image → Autocrop Image)"
echo "   3. The autocrop operation will apply immediately"
echo "   4. Observe that the white borders are automatically removed"
echo "   5. The export will be automated after the operation"