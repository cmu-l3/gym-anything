#!/bin/bash
set -e

echo "=== Setting up eraser transparency task ==="

# Install required packages for image processing
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Download image with a clear subject suitable for erasing
echo "📥 Downloading image for eraser demonstration..."
cd /home/ga/Desktop/
wget -q -O source_image.jpg "https://images.unsplash.com/photo-1574158622682-e40e69881006?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O source_image.jpg "https://images.unsplash.com/photo-1551963831-b3b1ca40c98e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating fallback image..."
        # Create a simple test image with a clear subject if download fails
        convert -size 600x400 xc:lightblue -fill red -draw "circle 300,200 300,100" -fill black -pointsize 24 -gravity center -annotate +0+100 "ERASE PART OF ME" source_image.jpg
    }
}

# Ensure the image has an alpha channel for transparency support
echo "🎨 Converting image to support transparency..."
convert source_image.jpg -alpha set eraseme_image.png

# Set proper permissions
chown ga:ga eraseme_image.png
chmod 644 eraseme_image.png

# Remove original jpg since we have the PNG with alpha
rm -f source_image.jpg

echo "✅ Image with alpha channel created at /home/ga/Desktop/eraseme_image.png"

echo "🎨 Opening GIMP with the image..."
# Launch GIMP with the alpha-enabled image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/eraseme_image.png > /tmp/gimp_eraser.log 2>&1 &"

sleep 3

echo "=== Eraser transparency task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The image is already open in GIMP with alpha channel support"
echo "   2. Select the Eraser tool from the toolbox (or press Shift+E)"
echo "   3. Increase the eraser size in Tool Options (try 100-150 pixels)"
echo "   4. Click and drag to erase part of the image"
echo "   5. Look for the checkerboard pattern showing transparency"
echo "   6. Erase enough to be visible but don't erase everything"
echo "   7. The export will be automated as PNG to preserve transparency"