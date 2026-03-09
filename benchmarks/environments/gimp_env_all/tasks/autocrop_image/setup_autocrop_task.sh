#!/bin/bash
set -e

echo "=== Setting up autocrop image task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Download an image with clear borders that can be autocropped
echo "📥 Downloading image with borders..."
cd /home/ga/Desktop/
wget -q -O bordered_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&h=400&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O bordered_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&h=400&q=80" || {
        echo "❌ All sources failed, creating test image..."
        # Create a simple test image with borders if download fails
        convert -size 800x600 xc:white -fill lightblue -draw "rectangle 100,100 700,500" -fill black -pointsize 24 -gravity center -annotate +0+0 "CONTENT TO CROP" bordered_image.jpg
    }
}

# Add white borders to the image to make it suitable for autocrop testing
echo "🖼️ Adding borders to create test case for autocrop..."
convert bordered_image.jpg -bordercolor white -border 50x50 bordered_image_with_padding.jpg
mv bordered_image_with_padding.jpg bordered_image.jpg

# Set proper permissions
chown ga:ga bordered_image.jpg
chmod 644 bordered_image.jpg

echo "✅ Bordered image created at /home/ga/Desktop/bordered_image.jpg"

echo "🎨 Opening GIMP with the bordered image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/bordered_image.jpg > /tmp/gimp_autocrop.log 2>&1 &"

sleep 3

echo "=== Autocrop image task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The bordered image is already open in GIMP"
echo "   2. Go to Image menu in the menu bar"
echo "   3. Look for 'Crop to Content' or 'Autocrop Image' option"
echo "   4. Click on it to automatically remove borders"
echo "   5. Observe that the image dimensions decrease and borders are removed"
echo "   6. The export will be automated after the autocrop operation"